//! One walk of a file system, in the order the folders are met, keeping only what is big enough to see on the panel.
//! An entry smaller than the floor is added into its folder's "rest" the moment it is finished, so memory grows with what is kept,
//! not with how many files the disk holds. Sizes are the space really taken (blocks), and a file with several hard links is counted once.
use super::kinds::{Kind, Reclaim};
use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const BLOCK_BYTES: u64 = 512;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntryType {
    Dir,
    File,
    /// The smaller entries of one folder, added together.
    Rest,
}

impl EntryType {
    pub const fn word(self) -> &'static str {
        match self {
            Self::Dir => "dir",
            Self::File => "file",
            Self::Rest => "rest",
        }
    }
}

/// Names inside a folder that the kind rules look for. Seen during the walk, because small files are not kept.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Marks(u8);

impl Marks {
    pub const CARGO_TOML: Marks = Marks(1);
    pub const PACKAGE_JSON: Marks = Marks(1 << 1);
    pub const APPLICATION_SUPPORT: Marks = Marks(1 << 2);
    /// `objects`, `refs` and `HEAD` together: a git object store.
    pub const GIT_STORE: Marks = Marks(0b111 << 3);

    pub fn contains(self, wanted: Marks) -> bool {
        self.0 & wanted.0 == wanted.0
    }

    fn of_name(name: &str) -> Marks {
        match name {
            "Cargo.toml" => Self::CARGO_TOML,
            "package.json" => Self::PACKAGE_JSON,
            "Application Support" => Self::APPLICATION_SUPPORT,
            "objects" => Marks(1 << 3),
            "refs" => Marks(1 << 4),
            "HEAD" => Marks(1 << 5),
            _ => Marks(0),
        }
    }

    fn add(&mut self, other: Marks) {
        self.0 |= other.0;
    }
}

#[derive(Debug)]
pub struct Entry {
    pub name: String,
    pub kind_of: EntryType,
    pub bytes: u64,
    /// Files below it, folders not counted.
    pub files: u64,
    /// A folder: the entries right inside it. A rest: how many entries it stands for. A file: 0.
    pub items: u64,
    /// Unix seconds of the newest change below it.
    pub modified: Option<i64>,
    /// Largest first.
    pub children: Vec<Entry>,
    pub marks: Marks,
    pub kind: Kind,
    pub reclaim: Option<Reclaim>,
}

impl Entry {
    fn new(name: String, kind_of: EntryType, bytes: u64, files: u64, modified: Option<i64>) -> Entry {
        Entry { name, kind_of, bytes, files, items: 0, modified, children: Vec::new(), marks: Marks::default(), kind: Kind::Other, reclaim: None }
    }

    fn folder(name: String, meta: &fs::Metadata) -> Entry {
        Entry::new(name, EntryType::Dir, meta.blocks() * BLOCK_BYTES, 0, Some(meta.mtime()))
    }

    /// An empty rest, for a folder whose small entries are about to be added in.
    pub fn rest() -> Entry {
        Entry::new(String::new(), EntryType::Rest, 0, 0, None)
    }

    /// Adds `other` into this rest.
    pub fn absorb(&mut self, other: &Entry) {
        self.bytes += other.bytes;
        self.files += other.files;
        self.items += if other.kind_of == EntryType::Rest { other.items } else { 1 };
        self.modified = newest(self.modified, other.modified);
    }

    pub fn count(&self) -> usize {
        1 + self.children.iter().map(Entry::count).sum::<usize>()
    }
}

fn newest(a: Option<i64>, b: Option<i64>) -> Option<i64> {
    a.max(b)
}

pub struct Settings {
    /// Smaller than this, an entry goes into its folder's rest.
    pub floor: u64,
    /// Below this many levels nothing is kept, only added up.
    pub keep_depth: usize,
    /// Folders not to go into: the other mounts on this machine (another file system, or a bind mount of a folder already counted).
    pub skip: HashSet<PathBuf>,
}

/// How far the walk has got, read by the routes while it runs.
#[derive(Default)]
pub struct Counters {
    pub entries: AtomicU64,
    pub bytes: AtomicU64,
}

impl Counters {
    pub fn reset(&self) {
        self.entries.store(0, Ordering::Relaxed);
        self.bytes.store(0, Ordering::Relaxed);
    }
}

pub struct Walked {
    pub root: Entry,
    /// Files and folders looked at.
    pub entries: u64,
    /// Folders that could not be opened (another user's, or root's).
    pub unreadable: u64,
}

struct Open {
    reader: fs::ReadDir,
    entry: Entry,
    rest: Entry,
    depth: usize,
}

impl Open {
    fn attach(&mut self, child: Entry, settings: &Settings) {
        self.entry.bytes += child.bytes;
        self.entry.files += child.files;
        self.entry.modified = newest(self.entry.modified, child.modified);
        let floor = if self.depth >= settings.keep_depth { u64::MAX } else { settings.floor };
        if child.bytes >= floor {
            self.entry.children.push(child);
        } else {
            self.rest.absorb(&child);
        }
    }

    fn finish(self) -> Entry {
        let mut entry = self.entry;
        if self.rest.items > 0 {
            let mut rest = self.rest;
            rest.marks = Marks::default();
            entry.children.push(rest);
        }
        entry.children.sort_by_key(|child| std::cmp::Reverse(child.bytes));
        entry
    }
}

/// Walks `root` without leaving its file system. Blocking; may take minutes on a big disk.
pub fn walk(root: &Path, settings: &Settings, counters: &Counters) -> std::io::Result<Walked> {
    let meta = fs::symlink_metadata(root)?;
    let device = meta.dev();
    let name = root.file_name().map_or_else(|| root.to_string_lossy().into_owned(), |name| name.to_string_lossy().into_owned());
    let mut stack = vec![Open { reader: fs::read_dir(root)?, entry: Entry::folder(name, &meta), rest: Entry::rest(), depth: 0 }];
    let mut linked: HashSet<(u64, u64)> = HashSet::new();
    let (mut entries, mut unreadable) = (0_u64, 0_u64);
    loop {
        let Some(top) = stack.last_mut() else { unreachable!("the root is popped last and returns") };
        let Some(next) = top.reader.next() else {
            let done = stack.pop().map(Open::finish).expect("an open folder");
            match stack.last_mut() {
                Some(parent) => parent.attach(done, settings),
                None => return Ok(Walked { root: done, entries, unreadable }),
            }
            continue;
        };
        let Ok(found) = next else { continue };
        entries += 1;
        counters.entries.fetch_add(1, Ordering::Relaxed);
        let name = found.file_name().to_string_lossy().into_owned();
        top.entry.marks.add(Marks::of_name(&name));
        top.entry.items += 1;
        // Gone since the folder was listed: nothing to count.
        let Ok(meta) = found.metadata() else { continue };
        if meta.is_dir() {
            let path = found.path();
            if meta.dev() != device || settings.skip.contains(&path) {
                continue;
            }
            match fs::read_dir(&path) {
                Ok(reader) => {
                    let depth = top.depth + 1;
                    stack.push(Open { reader, entry: Entry::folder(name, &meta), rest: Entry::rest(), depth });
                }
                Err(_) => {
                    unreadable += 1;
                    top.attach(Entry::folder(name, &meta), settings);
                }
            }
            continue;
        }
        let counted = meta.nlink() <= 1 || linked.insert((meta.dev(), meta.ino()));
        let bytes = if counted { meta.blocks() * BLOCK_BYTES } else { 0 };
        counters.bytes.fetch_add(bytes, Ordering::Relaxed);
        top.attach(Entry::new(name, EntryType::File, bytes, 1, Some(meta.mtime())), settings);
    }
}

/// The mount points in /proc/self/mountinfo other than `root`: the walk does not go into them.
pub fn other_mounts(mountinfo: &str, root: &Path) -> HashSet<PathBuf> {
    mountinfo
        .lines()
        .filter_map(|line| line.split(' ').nth(4))
        .map(|field| PathBuf::from(unescape(field)))
        .filter(|path| path != root)
        .collect()
}

/// mountinfo writes a space as \040, a tab as \011, a newline as \012 and a backslash as \134.
fn unescape(text: &str) -> String {
    let mut out = Vec::with_capacity(text.len());
    let bytes = text.as_bytes();
    let mut at = 0;
    while at < bytes.len() {
        let code = (bytes[at] == b'\\').then(|| text.get(at + 1..at + 4)).flatten().and_then(|digits| u8::from_str_radix(digits, 8).ok());
        match code {
            Some(byte) => {
                out.push(byte);
                at += 4;
            }
            None => {
                out.push(bytes[at]);
                at += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

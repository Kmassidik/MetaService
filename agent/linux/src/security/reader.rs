//! Streams a log (and the file it was rotated to) from a cursor position. It never holds more than one line in memory, stops after `max_items`
//! events or `SCAN_CAP_BYTES` of text, and says where the next unread line starts. The first read of a big file bisects for the window instead of scanning it.
use super::cursor::{FileMark, Position};
use std::fs::File;
use std::io::{self, BufRead, BufReader, Read, Seek, SeekFrom};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

/// A file smaller than this is read from its start on a first read; a bigger one is bisected for the first line of the window.
pub const WHOLE_FILE_BYTES: u64 = 64 * 1024 * 1024;
/// The most text one call reads from one source, so a call on a huge backlog answers in a bounded time and the next call goes on.
const SCAN_CAP_BYTES: u64 = 32 * 1024 * 1024;
/// A longer line is skipped (it is not an SSH line), though its bytes count as read.
const MAX_LINE_BYTES: u64 = 8 * 1024;
const BUFFER_BYTES: usize = 64 * 1024;
/// The bisection stops when the window is this small; the scan from there is cheap.
const BISECT_STOP_BYTES: u64 = 256 * 1024;
/// When a bisection probe lands on lines with no time, it looks at this many lines on before it gives up on the probe.
const PROBE_LINES: usize = 50;

/// A line read for its time and, when it is an event, the event.
pub struct Line<T> {
    pub epoch: i64,
    pub item: Option<T>,
}

pub type Parse<'a, T> = &'a dyn Fn(&str) -> Option<Line<T>>;

pub struct Source {
    pub current: PathBuf,
    pub rotated: PathBuf,
}

pub struct Outcome<T> {
    pub position: Position,
    pub reset: bool,
    pub items: Vec<T>,
}

/// What stops a read: the file is not there, or it cannot be read as this user.
#[derive(Debug)]
pub enum Unavailable {
    Missing,
    Io(io::Error),
}

#[derive(Clone, Copy)]
enum Start {
    At(u64),
    Window,
}

struct Step<'a> {
    path: &'a Path,
    start: Start,
    /// The last line of a file that will not grow any more counts even without its newline.
    closed: bool,
}

struct Budget {
    items_left: usize,
    bytes_left: u64,
}

impl Budget {
    fn spent(&self) -> bool {
        self.items_left == 0 || self.bytes_left == 0
    }
}

/// `cutoff` is the oldest second a first read keeps; reads that continue from a cursor keep everything.
pub fn read<T>(
    source: &Source,
    from: Position,
    max_items: usize,
    cutoff: i64,
    parse: Parse<'_, T>,
) -> Result<Outcome<T>, Unavailable> {
    let current = identity(&source.current)?;
    let rotated = identity(&source.rotated).ok();
    let (steps, reset) = plan(source, from, &current, rotated.as_ref());
    let mut outcome = Outcome {
        position: from,
        reset,
        items: Vec::new(),
    };
    let mut budget = Budget {
        items_left: max_items,
        bytes_left: SCAN_CAP_BYTES,
    };
    for step in steps {
        let readable = run_step(&step, cutoff, parse, &mut budget, &mut outcome);
        match readable {
            Err(Unavailable::Missing) if step.closed => continue,
            Err(Unavailable::Io(cause))
                if step.closed && cause.kind() == io::ErrorKind::PermissionDenied =>
            {
                continue
            }
            other => other?,
        }
        if budget.spent() {
            break;
        }
    }
    Ok(outcome)
}

#[derive(Clone, Copy, Debug)]
struct Identity {
    dev: u64,
    inode: u64,
    len: u64,
}

fn identity(path: &Path) -> Result<Identity, Unavailable> {
    match std::fs::metadata(path) {
        Ok(meta) => Ok(Identity {
            dev: meta.dev(),
            inode: meta.ino(),
            len: meta.len(),
        }),
        Err(cause) if cause.kind() == io::ErrorKind::NotFound => Err(Unavailable::Missing),
        Err(cause) => Err(Unavailable::Io(cause)),
    }
}

impl Identity {
    fn is(&self, mark: &FileMark) -> bool {
        (self.dev, self.inode) == (mark.dev, mark.inode)
    }
}

/// Which files to read and from where, and whether the cursor could not be honoured.
fn plan<'a>(
    source: &'a Source,
    from: Position,
    current: &Identity,
    rotated: Option<&Identity>,
) -> (Vec<Step<'a>>, bool) {
    let window = |reset| {
        let mut steps = Vec::new();
        if rotated.is_some() {
            steps.push(Step {
                path: &source.rotated,
                start: Start::Window,
                closed: true,
            });
        }
        steps.push(Step {
            path: &source.current,
            start: Start::Window,
            closed: false,
        });
        (steps, reset)
    };
    let mark = match from {
        Position::Unknown => return window(false),
        Position::Journal(_) => return window(true),
        Position::File(mark) => mark,
    };
    if current.is(&mark) {
        return if mark.offset <= current.len {
            (
                vec![Step {
                    path: &source.current,
                    start: Start::At(mark.offset),
                    closed: false,
                }],
                false,
            )
        } else {
            window(true)
        };
    }
    match rotated {
        Some(old) if old.is(&mark) && mark.offset <= old.len => (
            vec![
                Step {
                    path: &source.rotated,
                    start: Start::At(mark.offset),
                    closed: true,
                },
                Step {
                    path: &source.current,
                    start: Start::At(0),
                    closed: false,
                },
            ],
            false,
        ),
        _ => window(true),
    }
}

fn run_step<T>(
    step: &Step<'_>,
    cutoff: i64,
    parse: Parse<'_, T>,
    budget: &mut Budget,
    outcome: &mut Outcome<T>,
) -> Result<(), Unavailable> {
    let mut file = File::open(step.path).map_err(|cause| {
        if cause.kind() == io::ErrorKind::NotFound {
            Unavailable::Missing
        } else {
            Unavailable::Io(cause)
        }
    })?;
    let meta = file.metadata().map_err(Unavailable::Io)?;
    let (start, keep_from) = match step.start {
        Start::At(offset) => (offset, i64::MIN),
        Start::Window => (
            window_start(&mut file, meta.len(), cutoff, parse).map_err(Unavailable::Io)?,
            cutoff,
        ),
    };
    let reached = scan(
        &mut file,
        start,
        keep_from,
        step.closed,
        parse,
        budget,
        &mut outcome.items,
    )
    .map_err(Unavailable::Io)?;
    outcome.position = Position::File(FileMark {
        dev: meta.dev(),
        inode: meta.ino(),
        offset: reached,
    });
    Ok(())
}

/// Reads lines from `start`; returns the offset of the first unread byte.
fn scan<T>(
    file: &mut File,
    start: u64,
    keep_from: i64,
    closed: bool,
    parse: Parse<'_, T>,
    budget: &mut Budget,
    items: &mut Vec<T>,
) -> io::Result<u64> {
    file.seek(SeekFrom::Start(start))?;
    let mut reader = BufReader::with_capacity(BUFFER_BYTES, file);
    let (mut offset, mut buffer) = (start, Vec::new());
    while !budget.spent() {
        buffer.clear();
        let read = (&mut reader)
            .take(MAX_LINE_BYTES)
            .read_until(b'\n', &mut buffer)? as u64;
        let ended = buffer.last() == Some(&b'\n');
        if read == 0 || (!ended && read < MAX_LINE_BYTES && !closed) {
            break;
        }
        let skipped = if ended || read < MAX_LINE_BYTES {
            0
        } else {
            skip_rest_of_line(&mut reader)?
        };
        offset += read + skipped;
        budget.bytes_left = budget.bytes_left.saturating_sub(read + skipped);
        if skipped > 0 {
            continue;
        }
        keep(&buffer, keep_from, parse, budget, items);
    }
    Ok(offset)
}

fn keep<T>(
    raw: &[u8],
    keep_from: i64,
    parse: Parse<'_, T>,
    budget: &mut Budget,
    items: &mut Vec<T>,
) {
    let Some(Line {
        epoch,
        item: Some(item),
    }) = parse(&String::from_utf8_lossy(raw))
    else {
        return;
    };
    if epoch < keep_from {
        return;
    }
    items.push(item);
    budget.items_left -= 1;
}

/// Throws away the rest of a line longer than MAX_LINE_BYTES; returns how many bytes that was.
fn skip_rest_of_line<R: BufRead>(reader: &mut R) -> io::Result<u64> {
    let (mut skipped, mut scratch) = (0, Vec::new());
    loop {
        scratch.clear();
        let read = reader
            .take(MAX_LINE_BYTES)
            .read_until(b'\n', &mut scratch)? as u64;
        skipped += read;
        if read == 0 || scratch.last() == Some(&b'\n') {
            return Ok(skipped);
        }
    }
}

/// Where a first read starts: the start of a small file, or (for a big one) near the first line not older than `cutoff`.
fn window_start<T>(file: &mut File, len: u64, cutoff: i64, parse: Parse<'_, T>) -> io::Result<u64> {
    if len <= WHOLE_FILE_BYTES {
        return Ok(0);
    }
    let (mut low, mut high) = (0, len);
    while high - low > BISECT_STOP_BYTES {
        let middle = low + (high - low) / 2;
        match epoch_after(file, middle, parse)? {
            Some(epoch) if epoch < cutoff => low = middle,
            _ => high = middle,
        }
    }
    line_start_after(file, low)
}

fn line_start_after(file: &mut File, offset: u64) -> io::Result<u64> {
    if offset == 0 {
        return Ok(0);
    }
    file.seek(SeekFrom::Start(offset))?;
    let skipped = BufReader::new(&mut *file)
        .take(MAX_LINE_BYTES)
        .read_until(b'\n', &mut Vec::new())? as u64;
    Ok(offset + skipped)
}

/// The time of the first line with one that starts after `offset`.
fn epoch_after<T>(file: &mut File, offset: u64, parse: Parse<'_, T>) -> io::Result<Option<i64>> {
    file.seek(SeekFrom::Start(offset))?;
    let mut reader = BufReader::new(&mut *file);
    let mut buffer = Vec::new();
    reader
        .by_ref()
        .take(MAX_LINE_BYTES)
        .read_until(b'\n', &mut buffer)?;
    for _ in 0..PROBE_LINES {
        buffer.clear();
        if reader
            .by_ref()
            .take(MAX_LINE_BYTES)
            .read_until(b'\n', &mut buffer)?
            == 0
        {
            return Ok(None);
        }
        if let Some(line) = parse(&String::from_utf8_lossy(&buffer)) {
            return Ok(Some(line.epoch));
        }
    }
    Ok(None)
}

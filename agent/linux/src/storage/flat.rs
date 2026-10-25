//! The walked tree as the contract sends it: a flat list, each entry naming its folder by place, at most `MAX_NODES` long.
use super::walk::{Entry, EntryType};
use serde::Serialize;

pub const MAX_NODES: usize = 12_000;
pub const MAX_NAME_CHARS: usize = 255;
/// Rounds of folding before giving up on getting under the limit (each round folds strictly more).
const MAX_FOLD_ROUNDS: usize = 16;

#[derive(Debug, Serialize, PartialEq)]
pub struct Node {
    /// The place of its folder in the list; -1 for the first entry, the scanned folder itself.
    pub parent: i64,
    pub name: String,
    #[serde(rename = "type")]
    pub kind_of: &'static str,
    pub bytes: u64,
    pub files: u64,
    pub items: u64,
    pub kind: &'static str,
    pub reclaim: Option<&'static str>,
    pub modified: Option<i64>,
}

/// Folds the smallest entries into their folder's rest until the tree has at most `max` entries.
pub fn fit(root: &mut Entry, max: usize) {
    let mut floor = 0;
    for _ in 0..MAX_FOLD_ROUNDS {
        let count = root.count();
        if count <= max {
            return;
        }
        let mut sizes = Vec::with_capacity(count);
        for child in &root.children {
            sizes_of(child, &mut sizes);
        }
        let keep = max.saturating_sub(1).max(1).min(sizes.len());
        sizes.select_nth_unstable_by(keep - 1, |a, b| b.cmp(a));
        floor = sizes[keep - 1].max(floor + 1);
        fold(root, floor);
    }
}

fn sizes_of(entry: &Entry, into: &mut Vec<u64>) {
    into.push(entry.bytes);
    for child in &entry.children {
        sizes_of(child, into);
    }
}

/// Children under `floor` (and their own children) join the folder's rest.
fn fold(entry: &mut Entry, floor: u64) {
    let children = std::mem::take(&mut entry.children);
    let mut rest: Option<Entry> = None;
    for mut child in children {
        if child.bytes >= floor && child.kind_of != EntryType::Rest {
            fold(&mut child, floor);
            entry.children.push(child);
            continue;
        }
        let gathered = rest.get_or_insert_with(|| {
            let mut fresh = Entry::rest();
            fresh.kind = entry.kind;
            fresh.reclaim = entry.reclaim;
            fresh
        });
        gathered.absorb(&child);
    }
    if let Some(rest) = rest {
        entry.children.push(rest);
    }
    entry.children.sort_by_key(|child| std::cmp::Reverse(child.bytes));
}

/// The tree in walk order (a folder before what it holds), each entry pointing back at its folder.
pub fn flatten(root: &Entry) -> Vec<Node> {
    let mut nodes = Vec::with_capacity(root.count());
    let mut stack: Vec<(&Entry, i64)> = vec![(root, -1)];
    while let Some((entry, parent)) = stack.pop() {
        let place = nodes.len() as i64;
        nodes.push(Node {
            parent,
            name: entry.name.chars().take(MAX_NAME_CHARS).collect(),
            kind_of: entry.kind_of.word(),
            bytes: entry.bytes,
            files: entry.files,
            items: entry.items,
            kind: entry.kind.word(),
            reclaim: entry.reclaim.map(|reclaim| reclaim.word()),
            modified: entry.modified,
        });
        // Pushed smallest first, so the largest child comes out (and is listed) first.
        for child in entry.children.iter().rev() {
            stack.push((child, place));
        }
    }
    nodes
}

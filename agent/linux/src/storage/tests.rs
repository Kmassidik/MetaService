use super::flat::{fit, flatten, Node};
use super::kinds::{classify, Kind, Reclaim};
use super::walk::{other_mounts, walk, Counters, Entry, EntryType, Settings};
use super::{Answer, Storage};
use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

fn scratch(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("ms-storage-{name}-{}", rand::random::<u64>()));
    fs::create_dir_all(&path).unwrap();
    path
}

fn write(path: &Path, bytes: usize) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, vec![7_u8; bytes]).unwrap();
}

fn taken(path: &Path) -> u64 {
    fs::symlink_metadata(path).unwrap().blocks() * 512
}

fn settings(floor: u64) -> Settings {
    Settings { floor, keep_depth: 24, skip: HashSet::new() }
}

fn child<'a>(entry: &'a Entry, name: &str) -> &'a Entry {
    entry.children.iter().find(|child| child.name == name).unwrap_or_else(|| panic!("no {name} in {}", entry.name))
}

fn rest(entry: &Entry) -> Option<&Entry> {
    entry.children.iter().find(|child| child.kind_of == EntryType::Rest)
}

/// A home-like tree: a Rust project with its build folder, a web project with node_modules, a repo, a cache, small notes, an Incus folder.
fn sample() -> PathBuf {
    let root = scratch("sample");
    write(&root.join("projects/app/Cargo.toml"), 10);
    write(&root.join("projects/app/target/debug/big.bin"), 600_000);
    write(&root.join("projects/web/package.json"), 10);
    write(&root.join("projects/web/node_modules/left-pad/index.js"), 300_000);
    write(&root.join("projects/web/.git/objects/pack/pack.pack"), 200_000);
    write(&root.join("projects/web/.git/HEAD"), 10);
    fs::create_dir_all(root.join("projects/web/.git/refs")).unwrap();
    write(&root.join(".cache/pip/wheel.whl"), 250_000);
    for index in 0..20 {
        write(&root.join(format!("notes/note-{index}.md")), 100);
    }
    write(&root.join("incus/disks/default.img"), 400_000);
    root
}

#[test]
fn sizes_add_up_and_small_entries_join_the_rest() {
    let root = sample();
    let walked = walk(&root, &settings(100_000), &Counters::default()).unwrap();
    let tree = walked.root;
    let big = root.join("projects/app/target/debug/big.bin");
    let debug = child(child(child(child(&tree, "projects"), "app"), "target"), "debug");
    assert_eq!(child(debug, "big.bin").bytes, taken(&big));
    assert_eq!(child(debug, "big.bin").kind_of, EntryType::File);
    // The 20 notes are each under the floor, and so is their folder: one rest at the top stands for the whole folder.
    let top_rest = rest(&tree).expect("a rest for the small entries");
    assert!(tree.children.iter().all(|child| child.name != "notes"));
    assert_eq!(top_rest.items, 1);
    assert_eq!(top_rest.files, 20);
    // Folders hold their own block too, so the root is at least the sum of the files.
    let files: u64 = ["projects/app/Cargo.toml", "projects/app/target/debug/big.bin", "projects/web/package.json", "projects/web/node_modules/left-pad/index.js",
        "projects/web/.git/objects/pack/pack.pack", "projects/web/.git/HEAD", ".cache/pip/wheel.whl", "incus/disks/default.img"]
        .iter()
        .map(|file| taken(&root.join(file)))
        .sum::<u64>()
        + (0..20).map(|index| taken(&root.join(format!("notes/note-{index}.md")))).sum::<u64>();
    assert!(tree.bytes >= files);
    assert_eq!(tree.files, 28);
    assert_eq!(walked.unreadable, 0);
    assert_eq!(tree.bytes, tree.children.iter().map(|child| child.bytes).sum::<u64>() + taken(&root));
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn a_hard_linked_file_is_counted_once() {
    let root = scratch("links");
    write(&root.join("a/data.bin"), 500_000);
    fs::create_dir_all(root.join("b")).unwrap();
    fs::hard_link(root.join("a/data.bin"), root.join("b/data.bin")).unwrap();
    // Floor 0: APFS reports no blocks for a directory that holds only a hard link, and the test needs both folders to stay.
    let tree = walk(&root, &settings(0), &Counters::default()).unwrap().root;
    let once = taken(&root.join("a/data.bin"));
    let a = child(&tree, "a").bytes - taken(&root.join("a"));
    let b = child(&tree, "b").bytes - taken(&root.join("b"));
    assert_eq!(a + b, once, "one copy charged, the other free");
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn nothing_below_the_keep_depth_is_kept() {
    let root = scratch("deep");
    write(&root.join("one/two/three/big.bin"), 300_000);
    let shallow = Settings { floor: 1, keep_depth: 1, skip: HashSet::new() };
    let tree = walk(&root, &shallow, &Counters::default()).unwrap().root;
    let one = child(&tree, "one");
    assert_eq!(one.children.len(), 1);
    assert_eq!(one.children[0].kind_of, EntryType::Rest);
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn a_skipped_mount_is_not_walked() {
    let root = scratch("mounts");
    write(&root.join("mnt/other/big.bin"), 300_000);
    let skip = Settings { floor: 1, keep_depth: 24, skip: HashSet::from([root.join("mnt/other")]) };
    let tree = walk(&root, &skip, &Counters::default()).unwrap().root;
    assert_eq!(tree.files, 0);
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn the_other_mounts_come_from_mountinfo() {
    let mountinfo = "22 1 252:2 / / rw,relatime shared:1 - ext4 /dev/vda2 rw\n\
                     23 22 0:21 / /proc rw - proc proc rw\n\
                     40 22 252:2 /srv /mnt/with\\040space rw - ext4 /dev/vda2 rw\n";
    let mounts = other_mounts(mountinfo, Path::new("/"));
    assert_eq!(mounts, HashSet::from([PathBuf::from("/proc"), PathBuf::from("/mnt/with space")]));
}

#[test]
fn kinds_follow_disktree() {
    let root = sample();
    let mut tree = walk(&root, &settings(100_000), &Counters::default()).unwrap().root;
    classify(&mut tree);
    let projects = child(&tree, "projects");
    assert_eq!(projects.kind, Kind::Code);
    let app = child(projects, "app");
    assert_eq!(child(app, "target").reclaim, Some(Reclaim::BuildOutput), "target beside Cargo.toml");
    assert_eq!(child(child(app, "target"), "debug").reclaim, Some(Reclaim::BuildOutput), "inherited below");
    let web = child(projects, "web");
    assert_eq!(child(web, "node_modules").kind, Kind::Cache);
    assert_eq!(child(web, "node_modules").reclaim, Some(Reclaim::Reinstallable), "node_modules beside package.json");
    assert_eq!(child(web, ".git").kind, Kind::Git);
    assert_eq!(child(&tree, ".cache").reclaim, Some(Reclaim::Regenerable));
    assert_eq!(child(&tree, "incus").kind, Kind::Vms);
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn an_unknown_top_folder_takes_its_biggest_known_kind_and_a_lone_target_is_kept() {
    let root = scratch("dominant");
    write(&root.join("world/.git/objects/x"), 400_000);
    write(&root.join("world/target/out.bin"), 200_000);
    let mut tree = walk(&root, &settings(1), &Counters::default()).unwrap().root;
    classify(&mut tree);
    let world = child(&tree, "world");
    assert_eq!(world.kind, Kind::Git);
    assert_eq!(child(world, "target").reclaim, None, "no Cargo.toml beside it");
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn the_list_is_cut_to_the_limit_without_losing_bytes() {
    let root = scratch("many");
    for index in 0..60 {
        write(&root.join(format!("dir-{}/file-{index}.bin", index % 6)), 4096 * (index + 1));
    }
    let mut tree = walk(&root, &settings(1), &Counters::default()).unwrap().root;
    let total = tree.bytes;
    assert!(tree.count() > 20);
    fit(&mut tree, 20);
    assert!(tree.count() <= 20, "{} entries", tree.count());
    assert_eq!(tree.bytes, total);
    assert_eq!(tree.bytes, tree.children.iter().map(|child| child.bytes).sum::<u64>() + taken(&root));
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn the_flat_list_names_each_folder_by_an_earlier_place() {
    let root = sample();
    let mut tree = walk(&root, &settings(100_000), &Counters::default()).unwrap().root;
    classify(&mut tree);
    let nodes: Vec<Node> = flatten(&tree);
    assert_eq!(nodes.len(), tree.count());
    assert_eq!(nodes[0].parent, -1);
    assert_eq!(nodes[0].kind_of, EntryType::Dir);
    for (place, node) in nodes.iter().enumerate().skip(1) {
        assert!((0..place as i64).contains(&node.parent), "{} points at {}", node.name, node.parent);
        assert_eq!(nodes[node.parent as usize].kind_of, EntryType::Dir);
    }
    // Largest first among siblings.
    let tops: Vec<u64> = nodes.iter().filter(|node| node.parent == 0).map(|node| node.bytes).collect();
    assert!(tops.windows(2).all(|pair| pair[0] >= pair[1]));
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn the_answer_has_exactly_the_contract_keys() {
    let root = sample();
    let storage = Storage::at(root.clone());
    let first: Answer = storage.answer();
    let value = serde_json::to_value(&first).unwrap();
    assert_eq!(value, serde_json::json!({"scanning": false, "progress": null, "error": null, "map": null}));
    let started = serde_json::to_value(storage.scan()).unwrap();
    assert_eq!(started["scanning"], true);
    storage.wait();
    let value = serde_json::to_value(storage.answer()).unwrap();
    let map = value["map"].as_object().expect("a finished map");
    let mut keys: Vec<&str> = map.keys().map(String::as_str).collect();
    keys.sort_unstable();
    assert_eq!(keys, ["disk", "entries", "finished_at", "nodes", "root", "seconds", "unreadable"]);
    let node = map["nodes"][0].as_object().unwrap();
    let mut keys: Vec<&str> = node.keys().map(String::as_str).collect();
    keys.sort_unstable();
    assert_eq!(keys, ["bytes", "files", "items", "kind", "modified", "name", "parent", "reclaim", "type"]);
    assert_eq!(map["entries"], 44);
    // A second ask right after the first ended does not start another walk.
    let again = serde_json::to_value(storage.scan()).unwrap();
    assert_eq!(again["scanning"], false);
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn empty_startup_starts_once_and_coalesces_scan_requests() {
    let root = sample();
    let state = scratch("empty-startup");
    let cache = state.join("storage.json");
    let storage = Storage::at_with_cache(root.clone(), cache.clone());

    let started = serde_json::to_value(storage.start_if_needed()).unwrap();
    assert_eq!(started["scanning"], true);
    let repeated_startup = serde_json::to_value(storage.start_if_needed()).unwrap();
    assert_eq!(repeated_startup["scanning"], true);
    let manual = serde_json::to_value(storage.scan()).unwrap();
    assert_eq!(manual["scanning"], true);
    storage.wait();

    let answer = serde_json::to_value(storage.answer()).unwrap();
    assert_eq!(answer["scanning"], false);
    assert!(answer["map"].is_object());
    let cached: serde_json::Value = serde_json::from_slice(&fs::read(&cache).unwrap()).unwrap();
    assert_eq!(cached, answer["map"]);
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(state).unwrap();
}

#[test]
fn restored_map_skips_startup_and_preserves_finished_at() {
    let root = sample();
    let state = scratch("restored-startup");
    let cache = state.join("storage.json");
    let first = Storage::at_with_cache(root.clone(), cache.clone());
    first.start_if_needed();
    first.wait();
    let finished_at = serde_json::to_value(first.answer()).unwrap()["map"]["finished_at"].clone();
    assert!(finished_at.is_string());

    let restored = Storage::at_with_cache(root.clone(), cache);
    let answer = serde_json::to_value(restored.start_if_needed()).unwrap();
    assert_eq!(answer["scanning"], false);
    assert_eq!(answer["map"]["finished_at"], finished_at);
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(state).unwrap();
}

#[test]
fn a_cache_older_than_a_day_is_scanned_again() {
    let root = sample();
    let state = scratch("stale-cache");
    let cache = state.join("storage.json");
    let first = Storage::at_with_cache(root.clone(), cache.clone());
    first.start_if_needed();
    first.wait();
    std::process::Command::new("touch").args(["-t", "200001010000.00"]).arg(&cache).status().unwrap();

    let restored = Storage::at_with_cache(root.clone(), cache);
    let started = serde_json::to_value(restored.start_if_needed()).unwrap();
    assert_eq!(started["scanning"], true);
    restored.wait();
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(state).unwrap();
}

#[test]
fn corrupt_cache_is_treated_as_empty_and_replaced_after_startup() {
    let root = sample();
    let state = scratch("corrupt-startup");
    let cache = state.join("storage.json");
    fs::write(&cache, b"{not a storage map").unwrap();
    let storage = Storage::at_with_cache(root.clone(), cache.clone());

    let started = serde_json::to_value(storage.start_if_needed()).unwrap();
    assert_eq!(started["scanning"], true);
    storage.wait();
    let answer = serde_json::to_value(storage.answer()).unwrap();
    assert!(answer["map"].is_object());
    let cached: serde_json::Value = serde_json::from_slice(&fs::read(&cache).unwrap()).unwrap();
    assert_eq!(cached, answer["map"]);
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(state).unwrap();
}

#[test]
fn persistence_failure_is_reported_without_losing_the_map() {
    let root = sample();
    let state = scratch("unwritable-cache");
    let storage = Storage::at_with_cache(root.clone(), state.clone());
    storage.start_if_needed();
    storage.wait();

    let answer = serde_json::to_value(storage.answer()).unwrap();
    assert!(answer["map"].is_object());
    assert!(answer["error"].as_str().unwrap().contains("map could not be"));
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(state).unwrap();
}

#[test]
fn a_failed_scan_does_not_replace_the_last_good_cached_map() {
    let root = sample();
    let state = scratch("failed-startup");
    let cache = state.join("storage.json");
    let first = Storage::at_with_cache(root.clone(), cache.clone());
    first.start_if_needed();
    first.wait();
    let good = serde_json::to_value(first.answer()).unwrap()["map"].clone();
    let cached_before = fs::read(&cache).unwrap();
    fs::remove_dir_all(&root).unwrap();

    let restored = Storage::at_with_cache(root, cache.clone());
    restored.scan();
    restored.wait();
    let answer = serde_json::to_value(restored.answer()).unwrap();
    assert!(answer["error"].is_string());
    assert_eq!(answer["map"], good);
    assert_eq!(fs::read(&cache).unwrap(), cached_before);
    fs::remove_dir_all(state).unwrap();
}

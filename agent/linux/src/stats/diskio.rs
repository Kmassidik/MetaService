//! Disk read and write speed from /proc/diskstats, whole disks only (a partition would count its disk twice).
use std::path::Path;

const SECTOR_BYTES: u64 = 512;
const NAME_FIELD: usize = 2;
const SECTORS_READ_FIELD: usize = 5;
const SECTORS_WRITTEN_FIELD: usize = 9;
/// Virtual devices that sit on top of real disks: counting them would count the same bytes twice.
const VIRTUAL_PREFIXES: [&str; 7] = ["loop", "ram", "dm-", "md", "zram", "sr", "fd"];

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Counters {
    pub read_bytes: u64,
    pub written_bytes: u64,
}

/// Totals since boot over every whole, real disk. A whole disk has its own folder in /sys/block; a partition does not.
/// None when no disk was found (a container): the speed is then unknown, not 0.
pub fn parse(diskstats: &str, root: &Path) -> Option<Counters> {
    let mut counters = Counters::default();
    let mut found = false;
    for line in diskstats.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if !fields.get(NAME_FIELD).is_some_and(|name| counts(name, root)) {
            continue;
        }
        let sectors = |index: usize| fields.get(index).and_then(|n| n.parse::<u64>().ok()).unwrap_or(0);
        counters.read_bytes = counters.read_bytes.saturating_add(sectors(SECTORS_READ_FIELD).saturating_mul(SECTOR_BYTES));
        counters.written_bytes = counters.written_bytes.saturating_add(sectors(SECTORS_WRITTEN_FIELD).saturating_mul(SECTOR_BYTES));
        found = true;
    }
    found.then_some(counters)
}

fn counts(name: &str, root: &Path) -> bool {
    let virtual_device = VIRTUAL_PREFIXES.iter().any(|prefix| name.starts_with(prefix));
    !virtual_device && root.join("sys/block").join(name).is_dir()
}

#[cfg(test)]
mod tests {
    use super::*;

    const STATS: &str = "\
   8       0 sda 100 0 2000 50 200 0 4000 60 0 10 20\n\
   8       1 sda1 90 0 1900 40 190 0 3900 50 0 10 20\n\
 259       0 nvme0n1 10 0 100 5 20 0 300 6 0 1 2\n\
 259       1 nvme0n1p1 10 0 100 5 20 0 300 6 0 1 2\n\
   7       0 loop0 5 0 999 1 0 0 0 0 0 0 0\n\
 253       0 dm-0 5 0 999 1 5 0 999 0 0 0 0\n";

    fn root_with_disks() -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("ms-diskio-{}", rand::random::<u64>()));
        for name in ["sda", "nvme0n1", "loop0", "dm-0"] {
            std::fs::create_dir_all(root.join("sys/block").join(name)).unwrap();
        }
        root
    }

    #[test]
    fn only_whole_real_disks_are_added_in_512_byte_sectors() {
        let root = root_with_disks();
        let counters = parse(STATS, &root).unwrap();
        assert_eq!(counters.read_bytes, (2000 + 100) * 512);
        assert_eq!(counters.written_bytes, (4000 + 300) * 512);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn no_sys_block_means_unknown_not_zero() {
        assert_eq!(parse(STATS, Path::new("/nonexistent-ms-root")), None);
    }
}

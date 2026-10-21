//! Disks: the real mounted file systems from /proc/mounts, sizes from statvfs (asked through a function, so tests can fake it).
use super::model::{cut, Disk, MAX_DISKS, MAX_FS_CHARS, MAX_MOUNT_CHARS, MAX_NAME_CHARS};
use std::collections::HashSet;
use std::path::Path;

/// Real file systems that hold a person's files. tmpfs, proc, sysfs, overlay, squashfs and the like are not here.
const REAL_FILE_SYSTEMS: &[&str] = &["ext2", "ext3", "ext4", "xfs", "btrfs", "zfs", "f2fs", "vfat", "exfat", "ntfs", "ntfs3", "fuseblk", "nfs", "nfs4", "cifs", "bcachefs"];

/// Size of one mount in bytes: all of it, and what is free for programs.
#[derive(Debug, Clone, Copy)]
pub struct Sizes {
    pub total: u64,
    pub free: u64,
}

pub type SizeOf = fn(&Path) -> Option<Sizes>;

pub fn read(mounts: &str, size_of: SizeOf) -> Vec<Disk> {
    let mut seen = HashSet::new();
    let mut disks = Vec::new();
    for line in mounts.lines() {
        if disks.len() >= MAX_DISKS {
            break;
        }
        let mut fields = line.split_whitespace();
        let (Some(device), Some(mount), Some(fs)) = (fields.next(), fields.next(), fields.next()) else { continue };
        if !REAL_FILE_SYSTEMS.contains(&fs) || !seen.insert(device.to_string()) {
            continue;
        }
        let mount = unescape(mount);
        disks.extend(disk(device, &mount, fs, size_of));
    }
    disks
}

fn disk(device: &str, mount: &str, fs: &str, size_of: SizeOf) -> Option<Disk> {
    let sizes = size_of(Path::new(mount)).filter(|sizes| sizes.total > 0)?;
    let free = sizes.free.min(sizes.total);
    Some(Disk {
        mount: cut(mount, MAX_MOUNT_CHARS),
        name: cut(device.rsplit('/').next().unwrap_or(device), MAX_NAME_CHARS),
        fs: cut(fs, MAX_FS_CHARS),
        total_bytes: sizes.total,
        used_bytes: sizes.total - free,
        free_bytes: free,
    })
}

/// /proc/mounts writes a space as \040, a tab as \011, a newline as \012 and a backslash as \134.
fn unescape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('\\') {
        out.push_str(&rest[..at]);
        let code = rest.get(at + 1..at + 4).and_then(|digits| u8::from_str_radix(digits, 8).ok());
        match code {
            Some(byte) => { out.push(byte as char); rest = &rest[at + 4..]; }
            None => { out.push('\\'); rest = &rest[at + 1..]; }
        }
    }
    out.push_str(rest);
    out
}

/// The real statvfs call. The field types differ per platform, so they are converted, not cast.
#[allow(clippy::useless_conversion)]
pub fn system_sizes(path: &Path) -> Option<Sizes> {
    use std::os::unix::ffi::OsStrExt;
    let c_path = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut info = std::mem::MaybeUninit::<libc::statvfs>::zeroed();
    // SAFETY: c_path is a valid NUL-terminated string and info is a writable statvfs.
    let status = unsafe { libc::statvfs(c_path.as_ptr(), info.as_mut_ptr()) };
    if status != 0 {
        return None;
    }
    // SAFETY: statvfs returned 0, so it filled the struct.
    let info = unsafe { info.assume_init() };
    let block = u64::from(info.f_frsize);
    Some(Sizes { total: u64::from(info.f_blocks) * block, free: u64::from(info.f_bavail) * block })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake(path: &Path) -> Option<Sizes> {
        match path.to_str()? {
            "/gone" => None,
            "/empty" => Some(Sizes { total: 0, free: 0 }),
            _ => Some(Sizes { total: 1000, free: 400 }),
        }
    }

    #[test]
    fn keeps_real_file_systems_only() {
        let mounts = "proc /proc proc rw 0 0\ntmpfs /run tmpfs rw 0 0\n/dev/sda2 / ext4 rw 0 0\n/dev/sda1 /boot/efi vfat rw 0 0\noverlay /var/lib/x overlay rw 0 0\n";
        let disks = read(mounts, fake);
        assert_eq!(disks.iter().map(|d| (d.mount.as_str(), d.name.as_str(), d.fs.as_str())).collect::<Vec<_>>(), [("/", "sda2", "ext4"), ("/boot/efi", "sda1", "vfat")]);
        assert_eq!((disks[0].total_bytes, disks[0].used_bytes, disks[0].free_bytes), (1000, 600, 400));
    }

    #[test]
    fn same_device_twice_counts_once_and_unreadable_ones_are_skipped() {
        let mounts = "/dev/sda2 / btrfs rw 0 0\n/dev/sda2 /home btrfs rw 0 0\n/dev/sdb1 /gone ext4 rw 0 0\n/dev/sdc1 /empty ext4 rw 0 0\n";
        assert_eq!(read(mounts, fake).len(), 1);
    }

    #[test]
    fn mount_names_are_unescaped_and_cut() {
        let long = format!("/dev/sda1 /{} ext4 rw 0 0\n/dev/sdb1 /my\\040disk ext4 rw 0 0\n", "m".repeat(300));
        let disks = read(&long, fake);
        assert_eq!(disks[0].mount.chars().count(), MAX_MOUNT_CHARS);
        assert_eq!(disks[1].mount, "/my disk");
    }

    #[test]
    fn at_most_sixteen() {
        let mounts: String = (0..30).map(|n| format!("/dev/sd{n} /m{n} ext4 rw 0 0\n")).collect();
        assert_eq!(read(&mounts, fake).len(), MAX_DISKS);
    }

    #[test]
    fn real_statvfs_reads_the_root() {
        let sizes = system_sizes(Path::new("/")).unwrap();
        assert!(sizes.total > 0 && sizes.free <= sizes.total);
        assert!(system_sizes(Path::new("/no/such/place")).is_none());
    }
}

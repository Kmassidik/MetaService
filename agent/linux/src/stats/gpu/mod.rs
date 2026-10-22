//! GPUs of every vendor, read without root. NVIDIA through `nvidia-smi`; AMD and Intel from sysfs (`/sys/class/drm`).
//! One GPU that cannot be read never fails the others; a number that cannot be read is null.
mod amd;
mod intel;
mod nvidia;
mod sysfs;

pub use nvidia::QUERY_TIMEOUT;

use super::model::{GpuStats, MAX_GPUS};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const VENDOR_NVIDIA: &str = "nvidia";
pub const VENDOR_AMD: &str = "amd";
pub const VENDOR_INTEL: &str = "intel";
const PCI_VENDOR_AMD: &str = "0x1002";
const PCI_VENDOR_INTEL: &str = "0x8086";
const DRM_DIR: &str = "sys/class/drm";

/// All GPUs found, NVIDIA first. None when there is none, so the answer leaves the `gpus` key out.
pub fn read(root: &Path, nvidia_smi: Option<&str>, timeout: Duration) -> Option<Vec<GpuStats>> {
    let mut gpus = nvidia_smi.and_then(|program| nvidia::query(program, timeout)).unwrap_or_default();
    for card in cards(root) {
        gpus.extend(read_card(&card));
    }
    gpus.truncate(MAX_GPUS);
    (!gpus.is_empty()).then_some(gpus)
}

/// A display card folder, such as `/sys/class/drm/card0`, with its PCI vendor id.
#[derive(Debug, PartialEq)]
struct Card {
    folder: PathBuf,
    vendor: String,
}

fn read_card(card: &Card) -> Option<GpuStats> {
    match card.vendor.as_str() {
        PCI_VENDOR_AMD => Some(amd::read(&card.folder.join("device"))),
        PCI_VENDOR_INTEL => Some(intel::read(&card.folder)),
        _ => None, // NVIDIA is read through its program; other vendors are not read
    }
}

/// `card<N>` folders (not `card0-HDMI-A-1` outputs, not `renderD128`), one per PCI device, in name order.
fn cards(root: &Path) -> Vec<Card> {
    let Ok(entries) = std::fs::read_dir(root.join(DRM_DIR)) else { return Vec::new() };
    let mut folders: Vec<PathBuf> = entries.flatten().map(|entry| entry.path()).filter(|path| is_card_folder(path)).collect();
    folders.sort_by_key(|path| card_number(path));
    let mut seen = HashSet::new();
    folders.into_iter().filter_map(|folder| to_card(folder, &mut seen)).collect()
}

fn card_name(path: &Path) -> &str {
    path.file_name().and_then(|name| name.to_str()).unwrap_or_default()
}

fn is_card_folder(path: &Path) -> bool {
    card_name(path).strip_prefix("card").is_some_and(|rest| !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()))
}

fn card_number(path: &Path) -> u64 {
    card_name(path)["card".len()..].parse().unwrap_or(u64::MAX)
}

/// None for a card without a readable vendor, or one whose PCI device was already seen.
fn to_card(folder: PathBuf, seen: &mut HashSet<PathBuf>) -> Option<Card> {
    let device = folder.join("device");
    let vendor = sysfs::text_of(&device.join("vendor"))?.to_ascii_lowercase();
    let identity = std::fs::canonicalize(&device).unwrap_or(device);
    seen.insert(identity).then_some(Card { folder, vendor })
}

#[cfg(test)]
mod tests {
    use super::sysfs::{put, temp_tree};
    use super::*;

    const TIMEOUT: Duration = Duration::from_secs(1);

    fn add_card(root: &Path, name: &str, vendor: &str) {
        put(root, &format!("{DRM_DIR}/{name}/device/vendor"), vendor);
    }

    #[test]
    fn finds_amd_and_intel_cards_and_skips_outputs_render_nodes_and_unknown_vendors() {
        let root = temp_tree();
        add_card(&root, "card0", "0x1002\n");
        add_card(&root, "card1", "0x8086\n");
        add_card(&root, "card2", "0x1234\n");
        add_card(&root, "card0-HDMI-A-1", "0x1002\n");
        add_card(&root, "renderD128", "0x1002\n");
        put(&root, &format!("{DRM_DIR}/card0/device/gpu_busy_percent"), "12");
        let gpus = read(&root, None, TIMEOUT).unwrap();
        assert_eq!(gpus.iter().map(|g| g.vendor).collect::<Vec<_>>(), ["amd", "intel"]);
        assert_eq!(gpus[0].utilization_percent, Some(12.0));
    }

    #[test]
    fn two_entries_for_one_pci_device_count_once() {
        let root = temp_tree();
        let pci = root.join("sys/devices/pci0000:00/0000:03:00.0");
        put(&pci, "vendor", "0x1002");
        for name in ["card0", "card1"] {
            std::fs::create_dir_all(root.join(DRM_DIR).join(name)).unwrap();
            std::os::unix::fs::symlink(&pci, root.join(DRM_DIR).join(name).join("device")).unwrap();
        }
        assert_eq!(read(&root, None, TIMEOUT).unwrap().len(), 1);
    }

    #[test]
    fn cards_come_in_number_order_and_at_most_eight_are_kept() {
        let root = temp_tree();
        for number in 0..12 {
            add_card(&root, &format!("card{number}"), "0x8086");
            put(&root, &format!("{DRM_DIR}/card{number}/gt_cur_freq_mhz"), &format!("{}", 100 + number));
        }
        let gpus = read(&root, None, TIMEOUT).unwrap();
        assert_eq!((gpus.len(), gpus[2].clock_mhz), (8, Some(102.0)), "card2 before card10");
    }

    #[test]
    fn no_cards_and_no_program_means_no_gpus() {
        assert!(read(&temp_tree(), None, TIMEOUT).is_none());
        assert!(read(&temp_tree(), Some("/no/such/nvidia-smi"), TIMEOUT).is_none());
    }

    #[test]
    fn a_card_without_a_readable_vendor_does_not_stop_the_others() {
        let root = temp_tree();
        std::fs::create_dir_all(root.join(DRM_DIR).join("card0/device")).unwrap();
        add_card(&root, "card1", "0x1002");
        assert_eq!(read(&root, None, TIMEOUT).unwrap().len(), 1);
    }
}

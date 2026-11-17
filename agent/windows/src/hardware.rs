//! What this machine is made of, for the panel's spec rows (`Facts.hardware`): the computer's make and model, each kind of CPU core, and the drives.
//! Read once at start, like the CPU name. Every part is optional: a machine that does not say one simply leaves it out.
use serde::Serialize;

const DMI_DIR: &str = "/sys/class/dmi/id";
/// Arm boards without DMI (a Raspberry Pi, a Jetson) name themselves here.
const DEVICE_TREE_MODEL: &str = "/proc/device-tree/model";
const BLOCK_DIR: &str = "/sys/block";
const MAX_CHARS: usize = 120;
const MAX_CORE_TYPES: usize = 8;
const MAX_DISKS: usize = 8;
const MAX_MHZ: u32 = 20_000;
const MAX_CORES: f64 = 100_000.0;
const SECTOR_BYTES: u64 = 512;
const BYTES_PER_GB: u64 = 1_000_000_000;

/// What makers write in a DMI field they did not fill in. Compared without case.
const PLACEHOLDERS: [&str; 14] = [
    "system product name", "system manufacturer", "system name", "system version", "to be filled by o.e.m.", "default string", "not specified",
    "not applicable", "none", "n/a", "oem", "o.e.m.", "unknown", "type1productconfigid",
];
/// Words at the end of a maker's legal name that say nothing on screen ("Dell Inc." is Dell).
const VENDOR_ENDINGS: [&str; 6] = [", inc.", " inc.", " inc", " corporation", " corp.", " co., ltd."];
/// Block devices that are not drives: loop files, RAM disks, device-mapper and RAID volumes, optical and floppy drives, network block devices.
const NOT_DRIVES: [&str; 8] = ["loop", "ram", "zram", "dm-", "md", "sr", "fd", "nbd"];

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Hardware {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub core_types: Vec<CoreType>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub disks: Vec<Disk>,
}

/// One kind of CPU core: a chip with big and small cores has two.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CoreType {
    pub name: String,
    /// Physical cores of this kind over all sockets, threads not counted.
    pub cores: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_mhz: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Disk {
    pub model: String,
    /// Decimal GB, as drives are sold.
    pub size_gb: u64,
    pub kind: DiskKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DiskKind {
    Nvme,
    Ssd,
    Hdd,
}

/// This machine's hardware, from DMI (or the device tree), the `lscpu` text the caller already has, and /sys/block. None when none of it says anything.
pub fn read(lscpu: Option<&str>) -> Option<Hardware> {
    let dmi = |field: &str| std::fs::read_to_string(format!("{DMI_DIR}/{field}")).ok();
    let system = system_name(&Dmi {
        sys_vendor: dmi("sys_vendor"),
        product_name: dmi("product_name"),
        board_vendor: dmi("board_vendor"),
        board_name: dmi("board_name"),
    })
    .or_else(|| std::fs::read(DEVICE_TREE_MODEL).ok().and_then(|raw| device_tree_model(&raw)));
    let core_types = lscpu.map(parse_core_types).unwrap_or_default();
    let hardware = Hardware { system, core_types, disks: read_disks() };
    (hardware.system.is_some() || !hardware.core_types.is_empty() || !hardware.disks.is_empty()).then_some(hardware)
}

/// The DMI fields the computer's name is made from, as read from /sys/class/dmi/id (None when a file is missing or unreadable).
#[derive(Default)]
pub struct Dmi {
    pub sys_vendor: Option<String>,
    pub product_name: Option<String>,
    pub board_vendor: Option<String>,
    pub board_name: Option<String>,
}

/// "NVIDIA DGX Spark", "ASUS ROG CROSSHAIR VIII IMPACT": the product name, else the board name when the product name is a placeholder,
/// with the maker in front unless the name already says it. None when neither is filled in.
pub fn system_name(dmi: &Dmi) -> Option<String> {
    let filled = |value: &Option<String>| value.as_deref().and_then(tidy).filter(|text| !is_placeholder(text));
    let product = filled(&dmi.product_name).map(|name| name.replace('_', " ")).or_else(|| filled(&dmi.board_name))?;
    let vendor = filled(&dmi.sys_vendor).or_else(|| filled(&dmi.board_vendor)).map(|name| short_vendor(&name));
    let named = match vendor {
        Some(vendor) if !product.to_lowercase().contains(&vendor.to_lowercase()) => format!("{vendor} {product}"),
        _ => product,
    };
    tidy(&named)
}

/// The board's name in the device tree, which ends in a NUL byte: "Raspberry Pi 4 Model B Rev 1.2".
pub fn device_tree_model(raw: &[u8]) -> Option<String> {
    tidy(&String::from_utf8_lossy(raw).replace('\0', " "))
}

fn is_placeholder(text: &str) -> bool {
    let lower = text.to_lowercase();
    PLACEHOLDERS.contains(&lower.as_str()) || lower.contains("o.e.m")
}

fn short_vendor(name: &str) -> String {
    let lower = name.to_lowercase();
    VENDOR_ENDINGS.iter().find(|ending| lower.ends_with(*ending)).map(|ending| name[..name.len() - ending.len()].trim_end().to_string()).unwrap_or_else(|| name.to_string())
}

/// Each `Model name` block of `lscpu` text is one kind of core: its cores are `Core(s) per socket` (or `per cluster`, as some Arm kernels say)
/// times `Socket(s)` (or `Cluster(s)`), and its top clock is `CPU max MHz`. A block that does not give a core count is left out.
pub fn parse_core_types(text: &str) -> Vec<CoreType> {
    let mut blocks: Vec<Block> = Vec::new();
    for (key, value) in text.lines().filter_map(|line| line.split_once(':')).map(|(key, value)| (key.trim().to_lowercase(), value.trim())) {
        if key == "model name" {
            blocks.push(Block { name: tidy(value), ..Block::default() });
            continue;
        }
        let Some(block) = blocks.last_mut() else { continue };
        let number = || value.parse::<f64>().ok().filter(|n| n.is_finite() && *n >= 1.0);
        match key.as_str() {
            "core(s) per socket" | "core(s) per cluster" => block.per_group = number(),
            "socket(s)" | "cluster(s)" => block.groups = number(),
            "cpu max mhz" => block.max_mhz = number(),
            _ => {}
        }
    }
    blocks.into_iter().filter_map(Block::core_type).take(MAX_CORE_TYPES).collect()
}

#[derive(Default)]
struct Block {
    name: Option<String>,
    per_group: Option<f64>,
    groups: Option<f64>,
    max_mhz: Option<f64>,
}

impl Block {
    fn core_type(self) -> Option<CoreType> {
        let cores = (self.per_group? * self.groups.unwrap_or(1.0)).round();
        let max_mhz = self.max_mhz.map(|mhz| mhz.round() as u32).filter(|mhz| *mhz <= MAX_MHZ);
        let name = self.name?;
        (cores <= MAX_CORES).then_some(CoreType { name, cores: cores as u32, max_mhz })
    }
}

/// "Cortex-X925 + Cortex-A725" for a chip with more than one kind of core, the one name for a chip with one kind; None for none. The counts and clocks
/// stay in `core_types`, so the name still fits where the panel shows it in one line (the CPU type list of Create VM).
pub fn cores_name(core_types: &[CoreType]) -> Option<String> {
    tidy(&core_types.iter().map(|kind| kind.name.as_str()).collect::<Vec<_>>().join(" + "))
}

/// The physical drives under /sys/block, biggest first.
fn read_disks() -> Vec<Disk> {
    let Ok(entries) = std::fs::read_dir(BLOCK_DIR) else { return Vec::new() };
    let read = |path: std::path::PathBuf| std::fs::read_to_string(path).ok();
    let found = entries.flatten().filter_map(|entry| {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        disk(&name, read(path.join("size"))?.trim().parse().ok()?, read(path.join("queue/rotational")).as_deref().map(str::trim) == Some("1"), read(path.join("device/model")).as_deref())
    });
    biggest_first(found.collect())
}

/// One drive from what /sys/block says about it: its name, its size in 512-byte sectors, whether it spins, and its model. None for a device that is
/// not a drive, has no model, or is empty.
pub fn disk(name: &str, sectors: u64, rotational: bool, model: Option<&str>) -> Option<Disk> {
    if NOT_DRIVES.iter().any(|prefix| name.starts_with(prefix)) {
        return None;
    }
    let size_gb = (sectors.saturating_mul(SECTOR_BYTES) as f64 / BYTES_PER_GB as f64).round() as u64;
    let kind = if name.starts_with("nvme") { DiskKind::Nvme } else if rotational { DiskKind::Hdd } else { DiskKind::Ssd };
    let model = tidy(model?)?;
    (size_gb >= 1).then_some(Disk { model, size_gb, kind })
}

pub fn biggest_first(mut disks: Vec<Disk>) -> Vec<Disk> {
    disks.sort_by(|a, b| b.size_gb.cmp(&a.size_gb).then_with(|| a.model.cmp(&b.model)));
    disks.truncate(MAX_DISKS);
    disks
}

/// No control characters, single spaces, at most 120 characters. None when nothing is left.
fn tidy(text: &str) -> Option<String> {
    let single = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let printable: String = single.chars().filter(|c| !c.is_control()).take(MAX_CHARS).collect();
    let cut = printable.trim().to_string();
    (!cut.is_empty()).then_some(cut)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `lscpu` on a DGX Spark (util-linux 2.39): one block per kind of core.
    const LSCPU_SPARK: &str = "Architecture:                            aarch64\nCPU(s):                                  20\nVendor ID:                               ARM\nModel name:                              Cortex-X925\nModel:                                   1\nThread(s) per core:                      1\nCore(s) per socket:                      10\nSocket(s):                               1\nCPU max MHz:                             3900.0000\nCPU min MHz:                             1378.0000\nModel name:                              Cortex-A725\nModel:                                   1\nThread(s) per core:                      1\nCore(s) per socket:                      10\nSocket(s):                               1\nCPU max MHz:                             2808.0000\nL1d cache:                               1.3 MiB (20 instances)\n";
    const LSCPU_RYZEN: &str = "Architecture:             x86_64\nCPU(s):                   32\nVendor ID:                AuthenticAMD\n  Model name:             AMD Ryzen 9 5950X 16-Core Processor\n    Thread(s) per core:   2\n    Core(s) per socket:   16\n    Socket(s):            1\n    CPU max MHz:          5086.1812\n";
    const LSCPU_TWO_SOCKETS: &str = "Model name: Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz\nThread(s) per core: 2\nCore(s) per socket: 32\nSocket(s): 2\n";
    const LSCPU_CLUSTERS: &str = "Model name: Neoverse-N1\nCore(s) per cluster: 80\nSocket(s): -\nCluster(s): 1\n";

    fn core(name: &str, cores: u32, max_mhz: Option<u32>) -> CoreType {
        CoreType { name: name.into(), cores, max_mhz }
    }

    #[test]
    fn a_dgx_spark_has_two_kinds_of_core() {
        assert_eq!(parse_core_types(LSCPU_SPARK), [core("Cortex-X925", 10, Some(3900)), core("Cortex-A725", 10, Some(2808))]);
        assert_eq!(cores_name(&parse_core_types(LSCPU_SPARK)).as_deref(), Some("Cortex-X925 + Cortex-A725"));
    }

    #[test]
    fn an_x86_cpu_is_one_kind_counted_in_cores_not_threads() {
        assert_eq!(parse_core_types(LSCPU_RYZEN), [core("AMD Ryzen 9 5950X 16-Core Processor", 16, Some(5086))]);
        assert_eq!(cores_name(&parse_core_types(LSCPU_RYZEN)).as_deref(), Some("AMD Ryzen 9 5950X 16-Core Processor"));
    }

    #[test]
    fn sockets_and_arm_clusters_multiply_the_cores() {
        assert_eq!(parse_core_types(LSCPU_TWO_SOCKETS), [core("Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz", 64, None)]);
        assert_eq!(parse_core_types(LSCPU_CLUSTERS), [core("Neoverse-N1", 80, None)]);
    }

    #[test]
    fn a_block_without_a_core_count_or_a_name_is_left_out() {
        assert!(parse_core_types("").is_empty());
        assert!(parse_core_types("Core(s) per socket: 8\n").is_empty());
        assert!(parse_core_types("Model name: Thing\nSocket(s): 1\n").is_empty());
        assert!(parse_core_types("Model name:   \nCore(s) per socket: 4\n").is_empty());
        assert_eq!(parse_core_types("Model name: Hot\nCore(s) per socket: 4\nCPU max MHz: 99999\n"), [core("Hot", 4, None)]);
        assert_eq!(cores_name(&[]), None);
    }

    fn dmi(sys_vendor: &str, product_name: &str, board_vendor: &str, board_name: &str) -> Dmi {
        let some = |text: &str| Some(format!("{text}\n"));
        Dmi { sys_vendor: some(sys_vendor), product_name: some(product_name), board_vendor: some(board_vendor), board_name: some(board_name) }
    }

    #[test]
    fn the_system_is_the_product_with_its_maker() {
        assert_eq!(system_name(&dmi("NVIDIA", "NVIDIA_DGX_Spark", "NVIDIA", "P4242")).as_deref(), Some("NVIDIA DGX Spark"));
        assert_eq!(system_name(&dmi("Dell Inc.", "PowerEdge R7525", "Dell Inc.", "0PYVT1")).as_deref(), Some("Dell PowerEdge R7525"));
        assert_eq!(system_name(&dmi("QEMU", "Standard PC (Q35 + ICH9, 2009)", "", "")).as_deref(), Some("QEMU Standard PC (Q35 + ICH9, 2009)"));
    }

    #[test]
    fn a_placeholder_product_gives_way_to_the_board() {
        assert_eq!(system_name(&dmi("ASUS", "System Product Name", "ASUSTeK COMPUTER INC.", "ROG CROSSHAIR VIII IMPACT")).as_deref(), Some("ASUS ROG CROSSHAIR VIII IMPACT"));
        assert_eq!(system_name(&dmi("To Be Filled By O.E.M.", "To Be Filled By O.E.M.", "ASRock", "X570 Taichi")).as_deref(), Some("ASRock X570 Taichi"));
        assert_eq!(system_name(&dmi("Default string", "Default string", "Default string", "Default string")), None);
        assert_eq!(system_name(&Dmi::default()), None);
    }

    #[test]
    fn a_board_without_dmi_names_itself_in_the_device_tree() {
        assert_eq!(device_tree_model(b"Raspberry Pi 4 Model B Rev 1.2\0").as_deref(), Some("Raspberry Pi 4 Model B Rev 1.2"));
        assert_eq!(device_tree_model(b"\0"), None);
    }

    #[test]
    fn drives_are_named_sized_and_kinded_and_the_rest_left_out() {
        let nvme = disk("nvme0n1", 8_001_573_552, false, Some("SAMSUNG MZALC4T0HBL1-00B07              \n"));
        assert_eq!(nvme, Some(Disk { model: "SAMSUNG MZALC4T0HBL1-00B07".into(), size_gb: 4097, kind: DiskKind::Nvme }));
        assert_eq!(disk("sda", 19_532_873_728, true, Some("ST10000NE0004-2G")).map(|d| (d.size_gb, d.kind)), Some((10_001, DiskKind::Hdd)));
        assert_eq!(disk("sdb", 1_000_215_216, false, Some("Samsung SSD 870")).map(|d| d.kind), Some(DiskKind::Ssd));
        for not_a_drive in ["loop17", "ram0", "zram0", "dm-0", "md127", "sr0", "nbd0"] {
            assert_eq!(disk(not_a_drive, 2_000_000_000, false, Some("Virtual")), None, "{not_a_drive}");
        }
        assert_eq!(disk("vda", 2_000_000_000, false, None), None);
        assert_eq!(disk("sdc", 0, false, Some("Card reader")), None);
    }

    #[test]
    fn drives_come_biggest_first_and_at_most_eight() {
        let drive = |model: &str, size_gb: u64| Disk { model: model.into(), size_gb, kind: DiskKind::Ssd };
        let sorted = biggest_first(vec![drive("small", 500), drive("big", 4000), drive("mid", 1000)]);
        assert_eq!(sorted.iter().map(|d| d.model.as_str()).collect::<Vec<_>>(), ["big", "mid", "small"]);
        assert_eq!(biggest_first((0..12).map(|n| drive("d", n + 1)).collect()).len(), MAX_DISKS);
    }

    #[test]
    fn the_hardware_reads_as_the_contract_spells_it() {
        let hardware = Hardware { system: Some("NVIDIA DGX Spark".into()), core_types: vec![core("Cortex-X925", 10, Some(3900))], disks: vec![Disk { model: "SAMSUNG".into(), size_gb: 4097, kind: DiskKind::Nvme }] };
        let json = serde_json::to_value(&hardware).unwrap();
        assert_eq!(json, serde_json::json!({"system": "NVIDIA DGX Spark", "core_types": [{"name": "Cortex-X925", "cores": 10, "max_mhz": 3900}], "disks": [{"model": "SAMSUNG", "size_gb": 4097, "kind": "nvme"}]}));
        let bare = Hardware { system: None, core_types: vec![core("X", 1, None)], disks: Vec::new() };
        assert_eq!(serde_json::to_value(&bare).unwrap(), serde_json::json!({"core_types": [{"name": "X", "cores": 1}]}));
    }
}

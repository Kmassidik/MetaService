//! The whole machine's power draw: a RAPL energy counter (delta between samples gives watts) or, failing that, an instant hwmon reading. Anything unreadable is None, never 0.
use super::model::one_decimal;
use std::path::Path;
use std::process::Command;

/// Package 0's energy counter, in microjoules since boot (subdomains live next to it as `intel-rapl:0:0` and so on).
const RAPL_ENERGY: &str = "sys/class/powercap/intel-rapl:0/energy_uj";
const HWMON_DIR: &str = "sys/class/hwmon";
/// More than this a sensor never reports; a bigger number is a broken reading, not a supercomputer.
const MAX_WATTS: f64 = 2000.0;
/// RAPL reports in microjoules, hwmon power inputs in microwatts.
const MICRO: f64 = 1_000_000.0;
/// A counter file holds one small number; anything longer is not a reading.
const MAX_TEXT_CHARS: usize = 64;
const SUDO: &str = "sudo";

/// One power reading: a counter that needs a delta against the sample before it, or watts ready to show.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Reading {
    /// Microjoules counted so far (RAPL).
    Counter(u128),
    /// An instant draw in watts (hwmon), no delta needed.
    Watts(f64),
}

/// The best available reading: a RAPL counter first, then an instant hwmon value.
pub fn read(root: &Path) -> Option<Reading> {
    rapl_counter(root)
        .map(Reading::Counter)
        .or_else(|| hwmon_watts(root).map(Reading::Watts))
}

/// Watts over the gap between two energy counters. The counter went back (a reboot or an overflow) or the gap is unusable: None.
pub fn watts_between(before_uj: u128, now_uj: u128, seconds: f64) -> Option<f64> {
    let micro_joules = now_uj.checked_sub(before_uj)?;
    if !(seconds.is_finite() && seconds > 0.0) {
        return None;
    }
    let watts = micro_joules as f64 / seconds / MICRO;
    ((0.0..=MAX_WATTS).contains(&watts)).then(|| one_decimal(watts))
}

/// Package 0's energy counter. Most kernels let a normal user read it; a root-only one (it still shows in the folder listing) is read through `sudo -n cat`.
fn rapl_counter(root: &Path) -> Option<u128> {
    let path = root.join(RAPL_ENERGY);
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|text| counter(&text))
        .or_else(|| {
            path.parent()?
                .is_dir()
                .then(|| sudo_counter(&path))
                .flatten()
        })
}

/// Parses one counter in microjoules. Garbage or an overlong file: None.
fn counter(text: &str) -> Option<u128> {
    let text = text.trim();
    (text.chars().count() <= MAX_TEXT_CHARS).then(|| text.parse::<u128>().ok())?
}

/// `sudo -n cat <path>` for a root-only counter. `-n` never prompts: without a passwordless sudo this fails at once. Never panics.
fn sudo_counter(path: &Path) -> Option<u128> {
    let output = Command::new(SUDO)
        .arg("-n")
        .arg("cat")
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() || output.stdout.len() > MAX_TEXT_CHARS {
        return None;
    }
    counter(&String::from_utf8_lossy(&output.stdout))
}

/// The largest instant power draw any hwmon chip reports (`power*_input`, microwatts). None when no chip reports one.
fn hwmon_watts(root: &Path) -> Option<f64> {
    let mut folders: Vec<_> = std::fs::read_dir(root.join(HWMON_DIR))
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .collect();
    folders.sort();
    folders
        .iter()
        .filter_map(|folder| power_of(folder))
        .max_by(|a, b| a.total_cmp(b))
}

/// The strongest power input of one hwmon chip, in watts.
fn power_of(folder: &Path) -> Option<f64> {
    let mut inputs: Vec<_> = std::fs::read_dir(folder)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(is_power_input)
        })
        .collect();
    inputs.sort();
    inputs
        .iter()
        .filter_map(|path| watts_of(path))
        .max_by(|a, b| a.total_cmp(b))
}

fn is_power_input(name: &str) -> bool {
    name.starts_with("power") && name.ends_with("_input")
}

fn watts_of(path: &Path) -> Option<f64> {
    let micro = std::fs::read_to_string(path)
        .ok()?
        .trim()
        .parse::<f64>()
        .ok()
        .filter(|v| v.is_finite())?;
    let watts = micro / MICRO;
    ((0.0..=MAX_WATTS).contains(&watts)).then(|| one_decimal(watts))
}

/// Sum of every GPU draw that could be read. None when not one GPU reports a draw.
pub fn gpu_watts(gpus: &[super::model::GpuStats]) -> Option<f64> {
    let total: f64 = gpus.iter().filter_map(|gpu| gpu.power_watts).sum();
    (total > 0.0).then(|| one_decimal(total))
}

/// One electrical rail of the CPU, as hwmon reports it: a voltage in volts or a current in amperes.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Rail {
    Voltage(f64),
    Current(f64),
}

/// hwmon scales: `in*_input` is millivolts, `curr*_input` is milliamperes.
const MILLI: f64 = 1_000.0;
/// A sensor label longer than this is not a real label.
const MAX_LABEL_CHARS: usize = 64;

/// The CPU rail of the machine: the hwmon sensor whose label (e.g. `in0_label` = "CPU Core") contains "cpu".
/// `kind` picks voltage (`in`) or current (`curr`). Boards without such a label: None.
pub fn rail(root: &Path, kind: &str) -> Option<Rail> {
    let mut folders: Vec<_> = std::fs::read_dir(root.join(HWMON_DIR))
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .collect();
    folders.sort();
    folders.iter().find_map(|folder| rail_of(folder, kind))
}

/// The first CPU-labelled input of one hwmon chip, in volts or amperes.
fn rail_of(folder: &Path, kind: &str) -> Option<Rail> {
    let mut inputs: Vec<_> = std::fs::read_dir(folder)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with(kind) && name.ends_with("_input"))
        })
        .collect();
    inputs.sort();
    inputs
        .iter()
        .filter_map(|path| {
            cpu_labelled(folder, path)
                .unwrap_or(false)
                .then(|| reading_of(path))
        })
        .find_map(|rail| rail)
}

/// Whether the label file next to `input` (`in0_input` -> `in0_label`) exists and mentions "cpu" (case-insensitive).
fn cpu_labelled(folder: &Path, input: &Path) -> Option<bool> {
    let stem = input
        .file_name()?
        .to_str()?
        .trim_end_matches("_input")
        .to_string();
    let label = std::fs::read_to_string(folder.join(format!("{stem}_label"))).ok()?;
    Some((label.chars().count() <= MAX_LABEL_CHARS) && label.trim().to_lowercase().contains("cpu"))
}

/// The value at `path`, scaled from millivolts or milliamperes to volts or amperes. Unreadable, garbage or absurd: None.
fn reading_of(path: &Path) -> Option<Rail> {
    let milli = std::fs::read_to_string(path)
        .ok()?
        .trim()
        .parse::<f64>()
        .ok()
        .filter(|v| v.is_finite() && *v >= 0.0)?;
    let value = milli / MILLI;
    if !(0.0..=MAX_WATTS).contains(&value) {
        return None;
    }
    let is_voltage = path.file_name()?.to_str()?.starts_with("in");
    Some(if is_voltage {
        Rail::Voltage(value)
    } else {
        Rail::Current(one_decimal(value))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put(root: &Path, relative: &str, text: &str) {
        let path = root.join(relative);
        std::fs::create_dir_all(path.parent().expect("a parent folder")).expect("make the folder");
        std::fs::write(path, text).expect("write the file");
    }

    #[test]
    fn energy_delta_over_seconds_is_watts() {
        // 6 000 000 µJ in 3 s is 2 W.
        assert_eq!(watts_between(1_000_000, 7_000_000, 3.0), Some(2.0));
        assert_eq!(watts_between(0, 100_000_000, 10.0), Some(10.0));
    }

    #[test]
    fn a_counter_that_went_back_gives_nothing() {
        assert_eq!(watts_between(5_000_000, 4_999_999, 1.0), None);
    }

    #[test]
    fn a_useless_gap_gives_nothing() {
        assert_eq!(watts_between(0, 1_000_000, 0.0), None);
        assert_eq!(watts_between(0, 1_000_000, f64::NAN), None);
    }

    #[test]
    fn an_impossible_draw_is_clamped_away() {
        // 5 000 000 000 µJ in one second is 5000 W: a broken counter, not a machine.
        assert_eq!(watts_between(0, 5_000_000_000, 1.0), None);
    }

    use super::Rail;
    use crate::stats::model::GpuStats;

    fn gpu(watts: Option<f64>) -> GpuStats {
        let mut gpu = GpuStats::named("Fake GPU".into(), "nvidia");
        gpu.power_watts = watts;
        gpu
    }

    #[test]
    fn gpu_watts_sum_the_readable_draws() {
        assert_eq!(gpu_watts(&[gpu(Some(50.0)), gpu(Some(20.0))]), Some(70.0));
        assert_eq!(
            gpu_watts(&[gpu(Some(50.0)), gpu(None)]),
            Some(50.0),
            "a GPU without a draw does not stop the sum"
        );
        assert_eq!(gpu_watts(&[gpu(None), gpu(None)]), None);
        assert_eq!(gpu_watts(&[]), None);
    }

    #[test]
    fn cpu_rail_voltages_and_currents_come_from_labelled_sensors() {
        let root = std::env::temp_dir().join(format!("ms-rail-{}", rand::random::<u64>()));
        std::fs::create_dir_all(root.join("sys/class/hwmon/hwmon0")).unwrap();
        let put = |name: &str, text: &str| {
            std::fs::write(root.join("sys/class/hwmon/hwmon0").join(name), text).unwrap()
        };
        put("in0_input", "1455\n"); // millivolts: 1.455 V
        put("in0_label", "CPU Core\n");
        put("curr1_input", "18000\n"); // milliamperes: 18.0 A
        put("curr1_label", "CPU Package\n");
        put("in1_input", "12000\n");
        put("in1_label", "GPU Core\n"); // no "cpu" in the label: not accepted
        put("in2_input", "900\n"); // no label at all: not accepted
        assert_eq!(rail(&root, "in"), Some(Rail::Voltage(1.455)));
        assert_eq!(rail(&root, "curr"), Some(Rail::Current(18.0)));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_board_without_cpu_rails_gives_nothing() {
        let root = std::env::temp_dir().join(format!("ms-rail-{}", rand::random::<u64>()));
        std::fs::create_dir_all(root.join("sys/class/hwmon/hwmon0")).unwrap();
        std::fs::write(root.join("sys/class/hwmon/hwmon0/in0_input"), "1455\n").unwrap(); // no label file
        assert_eq!(rail(&root, "in"), None);
        let empty = std::env::temp_dir().join(format!("ms-rail-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&empty).unwrap();
        assert_eq!(rail(&empty, "curr"), None, "no hwmon at all");
        let _ = std::fs::remove_dir_all(&root);
        let _ = std::fs::remove_dir_all(&empty);
    }

    #[test]
    fn garbage_is_no_counter() {
        assert_eq!(counter("nope\n"), None);
        assert_eq!(counter(""), None);
        assert_eq!(counter("-5\n"), None);
        assert_eq!(
            counter(&"1".repeat(200)),
            None,
            "an overlong file is not a reading"
        );
        assert_eq!(counter("  123456  \n"), Some(123_456));
    }

    #[test]
    fn hwmon_microwatts_become_watts() {
        let root = std::env::temp_dir().join(format!("ms-power-{}", std::process::id()));
        put(&root, "sys/class/hwmon/hwmon0/power1_input", "42500000\n");
        put(&root, "sys/class/hwmon/hwmon1/power2_input", "3100000\n"); // 3.1 W, well below hwmon0's 42.5 W
        put(&root, "sys/class/hwmon/hwmon2/temp1_input", "45000\n"); // a temperature is not power
        put(&root, "sys/class/hwmon/hwmon3/power1_input", "junk\n"); // broken chip: skipped
        assert_eq!(hwmon_watts(&root), Some(42.5));
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn no_sensor_answers_with_nothing() {
        let empty = std::env::temp_dir().join(format!("ms-power-empty-{}", std::process::id()));
        std::fs::create_dir_all(&empty).unwrap();
        assert_eq!(read(&empty), None);
        std::fs::remove_dir_all(&empty).unwrap();
    }

    #[test]
    fn a_readable_rapl_counter_wins_over_hwmon() {
        let root = std::env::temp_dir().join(format!("ms-power-rapl-{}", std::process::id()));
        put(&root, RAPL_ENERGY, "123456789\n");
        put(&root, "sys/class/hwmon/hwmon0/power1_input", "42500000\n");
        assert_eq!(read(&root), Some(Reading::Counter(123_456_789)));
        std::fs::remove_dir_all(&root).unwrap();
    }
}

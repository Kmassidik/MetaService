//! CPU frequency (cpufreq) and temperature (hwmon, thermal zones), read without root. Anything unreadable is None, never 0.
use super::model::{one_decimal, Frequency};
use std::path::Path;

const CPU_DIR: &str = "sys/devices/system/cpu";
const HWMON_DIR: &str = "sys/class/hwmon";
const ZONE_DIR: &str = "sys/class/thermal";
const KHZ_PER_MHZ: f64 = 1000.0;
const MILLIDEGREES: f64 = 1000.0;
/// Chip names that report the processor's temperature.
const CPU_CHIPS: [&str; 4] = ["k10temp", "coretemp", "cpu_thermal", "zenpower"];
/// A thermal zone type that holds one of these words belongs to the processor.
const ZONE_WORDS: [&str; 3] = ["cpu", "soc", "x86_pkg"];
/// Outside this range the reading is a broken sensor (0 means "no value").
const MIN_CELSIUS: f64 = 1.0;
const MAX_CELSIUS: f64 = 150.0;

fn text_of(path: &Path) -> Option<String> {
    Some(std::fs::read_to_string(path).ok()?.trim().to_string())
}

fn number_of(path: &Path) -> Option<f64> {
    text_of(path)?.parse::<f64>().ok().filter(|v| v.is_finite())
}

/// Average and highest current speed over the given CPUs, in MHz. None when no CPU reports one.
pub fn frequency(root: &Path, ids: &[usize]) -> Option<Frequency> {
    let speeds: Vec<f64> = ids
        .iter()
        .filter_map(|id| number_of(&root.join(CPU_DIR).join(format!("cpu{id}/cpufreq/scaling_cur_freq"))))
        .filter(|khz| *khz > 0.0)
        .map(|khz| khz / KHZ_PER_MHZ)
        .collect();
    if speeds.is_empty() {
        return None;
    }
    let average = speeds.iter().sum::<f64>() / speeds.len() as f64;
    let max = speeds.iter().copied().fold(0.0, f64::max);
    Some(Frequency { average: one_decimal(average), max: one_decimal(max) })
}

/// The hottest processor sensor in degrees C: a known chip in hwmon first, then thermal zones named for the CPU.
pub fn temperature(root: &Path) -> Option<f64> {
    let hottest = hwmon_temperature(root).or_else(|| zone_temperature(root))?;
    Some(one_decimal(hottest))
}

fn folders(parent: &Path) -> Vec<std::path::PathBuf> {
    let Ok(entries) = std::fs::read_dir(parent) else { return Vec::new() };
    let mut paths: Vec<_> = entries.flatten().map(|entry| entry.path()).collect();
    paths.sort();
    paths
}

fn in_range(celsius: f64) -> Option<f64> {
    (MIN_CELSIUS..=MAX_CELSIUS).contains(&celsius).then_some(celsius)
}

fn max_of(values: impl Iterator<Item = f64>) -> Option<f64> {
    values.fold(None, |best, value| Some(best.map_or(value, |b: f64| b.max(value))))
}

fn hwmon_temperature(root: &Path) -> Option<f64> {
    let readings = folders(&root.join(HWMON_DIR)).into_iter()
        .filter(|chip| text_of(&chip.join("name")).is_some_and(|name| CPU_CHIPS.contains(&name.as_str())))
        .flat_map(|chip| folders(&chip))
        .filter(|file| file.file_name().and_then(|n| n.to_str()).is_some_and(is_temperature_input))
        .filter_map(|file| number_of(&file))
        .filter_map(|milli| in_range(milli / MILLIDEGREES));
    max_of(readings)
}

fn is_temperature_input(name: &str) -> bool {
    name.starts_with("temp") && name.ends_with("_input")
}

fn zone_temperature(root: &Path) -> Option<f64> {
    let readings = folders(&root.join(ZONE_DIR)).into_iter()
        .filter(|zone| zone.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("thermal_zone")))
        .filter(|zone| text_of(&zone.join("type")).is_some_and(|kind| names_the_cpu(&kind)))
        .filter_map(|zone| number_of(&zone.join("temp")))
        .filter_map(|milli| in_range(milli / MILLIDEGREES));
    max_of(readings)
}

fn names_the_cpu(kind: &str) -> bool {
    let lower = kind.to_lowercase();
    ZONE_WORDS.iter().any(|word| lower.contains(word))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put(root: &Path, relative: &str, text: &str) {
        let path = root.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn empty() -> std::path::PathBuf {
        std::env::temp_dir().join(format!("ms-thermal-{}", rand::random::<u64>()))
    }

    #[test]
    fn frequency_is_average_and_highest_in_megahertz() {
        let root = empty();
        put(&root, "sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", "2000000\n");
        put(&root, "sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq", "3000000\n");
        assert_eq!(frequency(&root, &[0, 1]), Some(Frequency { average: 2500.0, max: 3000.0 }));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn no_frequency_files_give_nothing_not_zero() {
        assert_eq!(frequency(&empty(), &[0, 1]), None);
    }

    #[test]
    fn a_known_chip_gives_its_hottest_sensor() {
        let root = empty();
        put(&root, "sys/class/hwmon/hwmon2/name", "k10temp\n");
        put(&root, "sys/class/hwmon/hwmon2/temp1_input", "61500\n");
        put(&root, "sys/class/hwmon/hwmon2/temp3_input", "58000\n");
        put(&root, "sys/class/hwmon/hwmon1/name", "nvme\n");
        put(&root, "sys/class/hwmon/hwmon1/temp1_input", "90000\n");
        assert_eq!(temperature(&root), Some(61.5));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn thermal_zones_named_for_the_cpu_are_the_fallback() {
        let root = empty();
        put(&root, "sys/class/thermal/thermal_zone0/type", "acpitz\n");
        put(&root, "sys/class/thermal/thermal_zone0/temp", "90000\n");
        put(&root, "sys/class/thermal/thermal_zone1/type", "soc-thermal\n");
        put(&root, "sys/class/thermal/thermal_zone1/temp", "44000\n");
        assert_eq!(temperature(&root), Some(44.0));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_zero_or_absurd_reading_is_no_reading() {
        let root = empty();
        put(&root, "sys/class/hwmon/hwmon0/name", "coretemp\n");
        put(&root, "sys/class/hwmon/hwmon0/temp1_input", "0\n");
        put(&root, "sys/class/hwmon/hwmon0/temp2_input", "999000\n");
        assert_eq!(temperature(&root), None);
        std::fs::remove_dir_all(root).unwrap();
    }
}

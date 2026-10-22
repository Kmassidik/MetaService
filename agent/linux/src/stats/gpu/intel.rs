//! Intel GPUs from what sysfs shows without privilege: the driver name and the current speed.
//! Use and memory need root tools (`intel_gpu_top`), which are never called, so they stay null.
use super::sysfs::{hwmon, number_of, text_of};
use super::VENDOR_INTEL;
use crate::stats::model::{one_decimal, GpuStats};
use std::path::Path;

/// Where the current speed lives, relative to the card folder (`i915` first, then the newer layouts).
const CLOCK_FILES: [&str; 3] = ["gt_cur_freq_mhz", "gt/gt0/rps_cur_freq_mhz", "device/tile0/gt0/freq0/cur_freq"];
const DRIVER_KEY: &str = "DRIVER=";

pub fn read(card: &Path) -> GpuStats {
    let device = card.join("device");
    let monitor = hwmon(&device);
    GpuStats {
        temperature_celsius: monitor.temperature_celsius.map(one_decimal),
        power_watts: monitor.power_watts.map(one_decimal),
        power_limit_watts: monitor.power_limit_watts.map(one_decimal),
        fan_percent: monitor.fan_percent.map(one_decimal),
        clock_mhz: CLOCK_FILES.iter().find_map(|file| number_of(&card.join(file))).filter(|mhz| *mhz > 0.0).map(one_decimal),
        ..GpuStats::named(name_of(&device), VENDOR_INTEL)
    }
}

/// "Intel graphics (i915)" from the driver in the device's uevent; "Intel graphics" when it does not say.
fn name_of(device: &Path) -> String {
    let uevent = text_of(&device.join("uevent")).unwrap_or_default();
    match uevent.lines().find_map(|line| line.strip_prefix(DRIVER_KEY)) {
        Some(driver) => format!("Intel graphics ({})", driver.trim()),
        None => "Intel graphics".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::super::sysfs::{put, temp_tree};
    use super::*;

    #[test]
    fn reads_the_driver_and_the_current_speed_and_leaves_use_and_memory_null() {
        let card = temp_tree();
        put(&card, "device/uevent", "DRIVER=i915\nPCI_ID=8086:46A6\n");
        put(&card, "gt_cur_freq_mhz", "650\n");
        let gpu = read(&card);
        assert_eq!((gpu.name.as_str(), gpu.vendor, gpu.clock_mhz), ("Intel graphics (i915)", "intel", Some(650.0)));
        assert_eq!((gpu.utilization_percent, gpu.memory_used_bytes, gpu.memory_total_bytes, gpu.temperature_celsius), (None, None, None, None));
    }

    #[test]
    fn the_newer_speed_files_and_a_discrete_cards_monitor_are_used_when_present() {
        let card = temp_tree();
        put(&card, "gt/gt0/rps_cur_freq_mhz", "1200");
        put(&card, "device/hwmon/hwmon5/temp1_input", "48000");
        let gpu = read(&card);
        assert_eq!((gpu.name.as_str(), gpu.clock_mhz, gpu.temperature_celsius), ("Intel graphics", Some(1200.0), Some(48.0)));
    }

    #[test]
    fn a_zero_speed_is_unknown() {
        let card = temp_tree();
        put(&card, "gt_cur_freq_mhz", "0");
        assert_eq!(read(&card).clock_mhz, None);
    }
}

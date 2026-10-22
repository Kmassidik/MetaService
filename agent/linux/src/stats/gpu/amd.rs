//! AMD GPUs (`amdgpu`) from the files the driver shows to every user. No external program.
use super::sysfs::{count_of, hwmon, number_of, text_of};
use super::VENDOR_AMD;
use crate::stats::model::{cut, one_decimal, GpuStats, MAX_NAME_CHARS};
use std::path::Path;

const FALLBACK_NAME: &str = "AMD GPU";
/// `pp_dpm_sclk` lines look like `1: 1800Mhz *`; the star marks the speed in use.
const CURRENT_MARK: char = '*';
const MHZ_SUFFIX: &str = "mhz";

pub fn read(device: &Path) -> GpuStats {
    let monitor = hwmon(device);
    let name = text_of(&device.join("product_name")).map(|name| cut(&name, MAX_NAME_CHARS)).unwrap_or_else(|| FALLBACK_NAME.to_string());
    GpuStats {
        utilization_percent: number_of(&device.join("gpu_busy_percent")).filter(|v| (0.0..=100.0).contains(v)).map(one_decimal),
        memory_used_bytes: count_of(&device.join("mem_info_vram_used")),
        memory_total_bytes: count_of(&device.join("mem_info_vram_total")).filter(|total| *total > 0),
        temperature_celsius: monitor.temperature_celsius.map(one_decimal),
        power_watts: monitor.power_watts.map(one_decimal),
        power_limit_watts: monitor.power_limit_watts.map(one_decimal),
        fan_percent: monitor.fan_percent.map(one_decimal),
        clock_mhz: text_of(&device.join("pp_dpm_sclk")).and_then(|text| current_clock(&text)),
        ..GpuStats::named(name, VENDOR_AMD)
    }
}

/// The megahertz on the starred line. None when no line is starred or the number does not parse.
pub fn current_clock(text: &str) -> Option<f64> {
    let line = text.lines().find(|line| line.trim_end().ends_with(CURRENT_MARK))?;
    let speed = line.split_whitespace().find(|word| word.to_ascii_lowercase().ends_with(MHZ_SUFFIX))?;
    let megahertz = speed[..speed.len() - MHZ_SUFFIX.len()].parse::<f64>().ok()?;
    (megahertz > 0.0).then_some(megahertz)
}

#[cfg(test)]
mod tests {
    use super::super::sysfs::{put, temp_tree};
    use super::*;

    #[test]
    fn reads_every_file_the_driver_shows() {
        let device = temp_tree();
        put(&device, "product_name", "AMD Radeon RX 7900 XTX");
        put(&device, "gpu_busy_percent", "37\n");
        put(&device, "mem_info_vram_used", "1073741824\n");
        put(&device, "mem_info_vram_total", "25753026560\n");
        put(&device, "pp_dpm_sclk", "0: 500Mhz\n1: 1800Mhz *\n2: 2400Mhz\n");
        put(&device, "hwmon/hwmon3/temp1_input", "61000\n");
        put(&device, "hwmon/hwmon3/power1_average", "215000000\n");
        put(&device, "hwmon/hwmon3/power1_cap", "327000000\n");
        put(&device, "hwmon/hwmon3/pwm1", "128\n");
        let gpu = read(&device);
        assert_eq!((gpu.name.as_str(), gpu.vendor), ("AMD Radeon RX 7900 XTX", "amd"));
        assert_eq!((gpu.utilization_percent, gpu.memory_used_bytes, gpu.memory_total_bytes), (Some(37.0), Some(1_073_741_824), Some(25_753_026_560)));
        assert_eq!((gpu.temperature_celsius, gpu.power_watts, gpu.power_limit_watts), (Some(61.0), Some(215.0), Some(327.0)));
        assert_eq!((gpu.fan_percent, gpu.clock_mhz), (Some(50.2), Some(1800.0)));
    }

    #[test]
    fn unreadable_files_are_absent_never_zero() {
        let device = temp_tree();
        put(&device, "gpu_busy_percent", "garbage");
        put(&device, "mem_info_vram_total", "0");
        put(&device, "pp_dpm_sclk", "0: 500Mhz\n1: 1800Mhz\n");
        put(&device, "hwmon/hwmon0/temp1_input", "0");
        let gpu = read(&device);
        assert_eq!(gpu.name, FALLBACK_NAME);
        assert_eq!((gpu.utilization_percent, gpu.memory_used_bytes, gpu.memory_total_bytes), (None, None, None));
        assert_eq!((gpu.temperature_celsius, gpu.power_watts, gpu.fan_percent, gpu.clock_mhz), (None, None, None, None));
    }

    #[test]
    fn power_input_stands_in_for_the_average_and_the_fan_speed_for_the_duty() {
        let device = temp_tree();
        put(&device, "hwmon/hwmon1/power1_input", "90500000");
        put(&device, "hwmon/hwmon1/fan1_input", "1500");
        put(&device, "hwmon/hwmon1/fan1_max", "3000");
        let gpu = read(&device);
        assert_eq!((gpu.power_watts, gpu.fan_percent), (Some(90.5), Some(50.0)));
    }

    #[test]
    fn a_fan_speed_without_a_maximum_is_not_guessed() {
        let device = temp_tree();
        put(&device, "hwmon/hwmon1/fan1_input", "1500");
        assert_eq!(read(&device).fan_percent, None);
    }
}

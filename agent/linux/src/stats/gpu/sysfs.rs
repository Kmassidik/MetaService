//! Small sysfs readers shared by the GPU readers. Anything unreadable is None, never 0.
use std::path::{Path, PathBuf};

const MICRO: f64 = 1_000_000.0;
const MILLI: f64 = 1000.0;
const PWM_MAX_DEFAULT: f64 = 255.0;
const PERCENT: f64 = 100.0;

pub fn text_of(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?.trim().to_string();
    (!text.is_empty()).then_some(text)
}

pub fn number_of(path: &Path) -> Option<f64> {
    text_of(path)?.parse::<f64>().ok().filter(|v| v.is_finite())
}

pub fn count_of(path: &Path) -> Option<u64> {
    text_of(path)?.parse::<u64>().ok()
}

/// The first `hwmon<N>` folder under the device, in name order.
fn hwmon_folder(device: &Path) -> Option<PathBuf> {
    let mut folders: Vec<PathBuf> = std::fs::read_dir(device.join("hwmon")).ok()?.flatten().map(|entry| entry.path()).collect();
    folders.sort();
    folders.into_iter().next()
}

/// What the card's hardware monitor shows to a normal user.
#[derive(Debug, Default, PartialEq)]
pub struct Hwmon {
    pub temperature_celsius: Option<f64>,
    pub power_watts: Option<f64>,
    pub power_limit_watts: Option<f64>,
    pub fan_percent: Option<f64>,
}

pub fn hwmon(device: &Path) -> Hwmon {
    let Some(folder) = hwmon_folder(device) else { return Hwmon::default() };
    Hwmon {
        temperature_celsius: number_of(&folder.join("temp1_input")).map(|milli| milli / MILLI).filter(|c| *c > 0.0),
        power_watts: number_of(&folder.join("power1_average")).or_else(|| number_of(&folder.join("power1_input"))).map(|micro| micro / MICRO).filter(|w| *w > 0.0),
        power_limit_watts: number_of(&folder.join("power1_cap")).map(|micro| micro / MICRO).filter(|w| *w > 0.0),
        fan_percent: fan_percent(&folder),
    }
}

/// The fan duty (`pwm1` out of `pwm1_max`), or the speed against `fan1_max` when the card only tells revolutions.
fn fan_percent(folder: &Path) -> Option<f64> {
    let duty = number_of(&folder.join("pwm1")).map(|pwm| pwm / number_of(&folder.join("pwm1_max")).unwrap_or(PWM_MAX_DEFAULT));
    let speed = || Some(number_of(&folder.join("fan1_input"))? / number_of(&folder.join("fan1_max")).filter(|max| *max > 0.0)?);
    let share = duty.or_else(speed)? * PERCENT;
    (0.0..=PERCENT).contains(&share).then_some(share)
}

#[cfg(test)]
pub fn put(root: &Path, relative: &str, text: &str) {
    let path = root.join(relative);
    std::fs::create_dir_all(path.parent().expect("a parent folder")).expect("make the folder");
    std::fs::write(path, text).expect("write the file");
}

#[cfg(test)]
pub fn temp_tree() -> PathBuf {
    let path = std::env::temp_dir().join(format!("ms-gpu-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&path).expect("make the tree");
    path
}

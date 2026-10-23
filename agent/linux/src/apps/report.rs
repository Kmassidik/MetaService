//! Reading what an installer script printed: the result lines after the last marker, and the last lines of the installer's own output for the error body.
use super::script::RESULT_MARKER;
use super::App;

/// The most lines of installer output an error answer carries, and the most characters in each.
pub const LOG_TAIL_LINES: usize = 12;
pub const LOG_TAIL_LINE_CHARS: usize = 200;
/// The longest version text accepted, and the exact length of a SHA-256 in hex.
const MAX_VERSION_CHARS: usize = 100;
const SHA256_HEX_CHARS: usize = 64;

const APP_PREFIX: &str = "app=";
const INSTALLED_PREFIX: &str = "installed=";
const VERSION_PREFIX: &str = "version=";
const SHA256_PREFIX: &str = "sha256=";
const FAILURE_PREFIX: &str = "failure=";

/// Why the script stopped. The code is what it prints; the message is what the person reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppFailure {
    NoPackageManager,
    PrerequisitesFailed,
    DownloadFailed,
    InstallFailed,
}

impl AppFailure {
    pub fn from_code(code: &str) -> Option<AppFailure> {
        match code {
            "no_package_manager" => Some(AppFailure::NoPackageManager),
            "prerequisites_failed" => Some(AppFailure::PrerequisitesFailed),
            "download_failed" => Some(AppFailure::DownloadFailed),
            "install_failed" => Some(AppFailure::InstallFailed),
            _ => None,
        }
    }

    pub fn code(self) -> &'static str {
        match self {
            AppFailure::NoPackageManager => "no_package_manager",
            AppFailure::PrerequisitesFailed => "prerequisites_failed",
            AppFailure::DownloadFailed => "download_failed",
            AppFailure::InstallFailed => "install_failed",
        }
    }

    pub fn message(self) -> &'static str {
        match self {
            AppFailure::NoPackageManager => "The VM has no package manager the helper knows (apt-get), so it cannot install the packages the installer needs.",
            AppFailure::PrerequisitesFailed => "The VM could not install the packages the installer needs. Check that the VM has internet access.",
            AppFailure::DownloadFailed => "The VM could not download the installer. Check that the VM has internet access.",
            AppFailure::InstallFailed => "The installer ran but the app is not in the VM afterwards.",
        }
    }
}

/// What the script printed when it finished its work.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Report {
    Done(Installed),
    Failed(AppFailure),
}

/// The answer of `PUT /v1/workloads/{id}/app` when it worked.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct Installed {
    pub app: String,
    /// False: the app was already there and nothing was changed.
    pub installed: bool,
    pub version: Option<String>,
    pub installer_sha256: Option<String>,
}

fn result_lines(output: &str) -> Option<Vec<&str>> {
    let lines: Vec<&str> = output.lines().map(str::trim_end).collect();
    let marker = lines.iter().rposition(|line| *line == RESULT_MARKER)?;
    Some(lines[marker + 1..].to_vec())
}

fn value<'a>(lines: &[&'a str], prefix: &str) -> Option<&'a str> {
    lines.iter().filter_map(|line| line.strip_prefix(prefix)).next_back()
}

fn is_plain_version(text: &str) -> bool {
    !text.is_empty() && text.chars().count() <= MAX_VERSION_CHARS && !text.chars().any(char::is_control)
}

fn is_sha256(text: &str) -> bool {
    text.len() == SHA256_HEX_CHARS && text.chars().all(|c| c.is_ascii_hexdigit())
}

/// Reads the result lines after the last marker. None when there is no marker, the app is not the one asked for, a line is missing, or a value is not one we know.
pub fn parse(output: &str, app: App) -> Option<Report> {
    let lines = result_lines(output)?;
    (value(&lines, APP_PREFIX)? == app.name()).then_some(())?;
    if let Some(code) = value(&lines, FAILURE_PREFIX) {
        return AppFailure::from_code(code).map(Report::Failed);
    }
    let installed = match value(&lines, INSTALLED_PREFIX)? {
        "true" => true,
        "false" => false,
        _ => return None,
    };
    let version = value(&lines, VERSION_PREFIX).filter(|text| is_plain_version(text)).map(str::to_string);
    let installer_sha256 = value(&lines, SHA256_PREFIX).filter(|text| is_sha256(text)).map(str::to_string);
    Some(Report::Done(Installed { app: app.name().to_string(), installed, version, installer_sha256 }))
}

/// The last lines the installer printed (everything before the last marker, or all of it without one): control characters removed, each line cut, empty lines dropped.
pub fn log_tail(output: &str) -> Vec<String> {
    let lines: Vec<&str> = output.lines().collect();
    let end = lines.iter().rposition(|line| line.trim_end() == RESULT_MARKER).unwrap_or(lines.len());
    let clean: Vec<String> = lines[..end]
        .iter()
        .map(|line| line.chars().filter(|c| !c.is_control()).collect::<String>())
        .map(|line| line.trim().chars().take(LOG_TAIL_LINE_CHARS).collect::<String>())
        .filter(|line| !line.is_empty())
        .collect();
    clean[clean.len().saturating_sub(LOG_TAIL_LINES)..].to_vec()
}

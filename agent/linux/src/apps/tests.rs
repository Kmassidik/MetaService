//! The pure parts of the app installs: the two constant scripts, the request body, the result lines and the log tail.
use super::report::{self, AppFailure, Installed, Report};
use super::script::{HERMES_SCRIPT, OPENCLAW_SCRIPT, RESULT_MARKER};
use super::{incus_call, App};
use std::process::Command;

const SHA: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

fn lines_after_marker(lines: &[&str]) -> String {
    format!("noise\n{RESULT_MARKER}\n{}\n", lines.join("\n"))
}

// ---- scripts

#[test]
fn both_scripts_are_valid_bash_text() {
    for script in [OPENCLAW_SCRIPT, HERMES_SCRIPT] {
        let status = Command::new("/bin/bash").args(["-n", "-c", script]).status().unwrap();
        assert!(status.success());
    }
}

#[test]
fn the_urls_are_exactly_the_two_vendor_installers() {
    assert!(OPENCLAW_SCRIPT.contains("\nURL='https://openclaw.ai/install.sh'\n"));
    assert!(HERMES_SCRIPT.contains("\nURL='https://hermes-agent.nousresearch.com/install.sh'\n"));
    assert_eq!(OPENCLAW_SCRIPT.matches("https://").count(), 1);
    assert_eq!(HERMES_SCRIPT.matches("https://").count(), 1);
}

#[test]
fn the_openclaw_environment_and_version_pin_are_exactly_the_ones_maas_uses() {
    let environment = "CI=1 DEBIAN_FRONTEND=noninteractive OPENCLAW_NO_ONBOARD=1 OPENCLAW_NO_PROMPT=1 OPENCLAW_INSTALL_METHOD=npm OPENCLAW_VERSION=2026.9.4 \"OPENCLAW_INSTALL_URL=$URL\" bash \"$1\"";
    assert!(OPENCLAW_SCRIPT.contains(environment));
    assert!(OPENCLAW_SCRIPT.contains("PREREQUISITES='curl ca-certificates'\n"));
}

#[test]
fn the_hermes_environment_and_prerequisites_are_exactly_the_ones_in_the_brief() {
    assert!(HERMES_SCRIPT.contains("CI=1 DEBIAN_FRONTEND=noninteractive bash \"$1\""));
    assert!(HERMES_SCRIPT.contains("PREREQUISITES='curl ca-certificates git libatomic1'\n"));
    assert!(!HERMES_SCRIPT.contains("OPENCLAW"));
}

#[test]
fn the_steps_run_in_order_and_the_installer_is_a_file_never_piped() {
    for script in [OPENCLAW_SCRIPT, HERMES_SCRIPT] {
        let at = |needle: &str| script.find(needle).unwrap_or_else(|| panic!("no {needle:?}"));
        let order = ["BIN=$(find_app) && {", "apt-get update -y", "apt-get install -y $PREREQUISITES", "curl -fsSL --max-time \"$DOWNLOAD_SECONDS\" -o \"$FILE\" \"$URL\"", "sha256sum \"$FILE\"", "run_installer \"$FILE\"", "BIN=$(find_app) || report false install_failed", "read_version \"$BIN\"\nreport true"].map(at);
        assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{order:?}");
        assert!(script.contains("DOWNLOAD_SECONDS=120"));
        assert!(!script.contains("| bash") && !script.contains("|bash"), "never curl | bash");
        assert!(script.contains("/root/.local/bin"));
    }
}

#[test]
fn the_scripts_hold_no_placeholder_for_request_data() {
    for script in [OPENCLAW_SCRIPT, HERMES_SCRIPT] {
        assert!(!script.contains("{}") && !script.contains("%s"));
        assert!(script.contains(&format!("RESULT_MARKER='{RESULT_MARKER}'")));
    }
}

#[test]
fn each_app_has_its_own_script_and_name() {
    assert_eq!((App::Openclaw.name(), App::Hermes.name()), ("openclaw", "hermes"));
    assert_eq!(App::Openclaw.script(), OPENCLAW_SCRIPT);
    assert_eq!(App::Hermes.script(), HERMES_SCRIPT);
}

#[test]
fn the_call_is_a_fixed_exec_of_bash_reading_standard_input() {
    assert_eq!(incus_call("ms-w-1"), ["exec", "ms-w-1", "--", "/bin/bash", "-s"]);
}

// ---- request

#[test]
fn the_two_known_apps_are_accepted() {
    assert_eq!(App::parse(br#"{"app":"openclaw"}"#), Ok(App::Openclaw));
    assert_eq!(App::parse(br#"{"app":"hermes"}"#), Ok(App::Hermes));
}

#[test]
fn every_bad_body_is_refused() {
    let bodies: [&[u8]; 10] = [
        br#"{"app":"nginx"}"#, br#"{"app":"OpenClaw"}"#, br#"{"app":""}"#, br#"{"app":1}"#, br#"{"app":null}"#, br#"{"app":["openclaw"]}"#,
        br#"{}"#, br#"{"app":"hermes","extra":true}"#, br#"["hermes"]"#, b"not json",
    ];
    for body in bodies {
        assert!(App::parse(body).is_err(), "{}", String::from_utf8_lossy(body));
    }
}

#[test]
fn the_refusal_names_the_field_never_the_value() {
    let message = App::parse(br#"{"app":"rm -rf /"}"#).unwrap_err();
    assert!(!message.contains("rm -rf"));
    assert_eq!(App::parse(br#"{"app":"hermes","x":1}"#).unwrap_err(), "unknown field x");
}

// ---- result lines

#[test]
fn a_fresh_install_reads_the_version_and_the_hash() {
    let output = lines_after_marker(&["app=openclaw", "installed=true", "version=OpenClaw 2026.9.4", &format!("sha256={SHA}")]);
    let expected = Installed { app: "openclaw".into(), installed: true, version: Some("OpenClaw 2026.9.4".into()), installer_sha256: Some(SHA.into()) };
    assert_eq!(report::parse(&output, App::Openclaw), Some(Report::Done(expected)));
}

#[test]
fn an_app_that_was_already_there_has_no_hash_and_installed_false() {
    let output = lines_after_marker(&["app=hermes", "installed=false", "version=0.4.1"]);
    let expected = Installed { app: "hermes".into(), installed: false, version: Some("0.4.1".into()), installer_sha256: None };
    assert_eq!(report::parse(&output, App::Hermes), Some(Report::Done(expected)));
}

#[test]
fn a_tool_that_prints_no_version_gives_null() {
    let output = lines_after_marker(&["app=hermes", "installed=true", &format!("sha256={SHA}")]);
    let Some(Report::Done(done)) = report::parse(&output, App::Hermes) else { panic!("should parse") };
    assert_eq!(done.version, None);
}

#[test]
fn each_failure_code_is_read_with_its_plain_words() {
    let codes = [
        ("no_package_manager", AppFailure::NoPackageManager),
        ("prerequisites_failed", AppFailure::PrerequisitesFailed),
        ("download_failed", AppFailure::DownloadFailed),
        ("install_failed", AppFailure::InstallFailed),
    ];
    for (code, failure) in codes {
        let output = lines_after_marker(&["app=hermes", "installed=false", &format!("failure={code}")]);
        assert_eq!(report::parse(&output, App::Hermes), Some(Report::Failed(failure)));
        assert_eq!(failure.code(), code);
        assert!(!failure.message().is_empty());
    }
    assert_eq!(AppFailure::DownloadFailed.message(), "The VM could not download the installer. Check that the VM has internet access.");
}

#[test]
fn garbage_and_half_answers_are_not_guessed_at() {
    let wrong_app = lines_after_marker(&["app=openclaw", "installed=true"]);
    let no_flag = lines_after_marker(&["app=hermes"]);
    let odd_flag = lines_after_marker(&["app=hermes", "installed=maybe"]);
    let unknown_failure = lines_after_marker(&["app=hermes", "installed=false", "failure=meteor"]);
    assert_eq!(report::parse(&wrong_app, App::Hermes), None);
    for output in [no_flag.as_str(), odd_flag.as_str(), unknown_failure.as_str(), "", "installed=true\napp=hermes\n", "\u{0}\u{1}garbage"] {
        assert_eq!(report::parse(output, App::Hermes), None, "{output:?}");
    }
}

#[test]
fn only_the_lines_after_the_last_marker_count() {
    let faked = format!("{RESULT_MARKER}\napp=hermes\ninstalled=true\n{RESULT_MARKER}\napp=hermes\ninstalled=false\nfailure=download_failed\n");
    assert_eq!(report::parse(&faked, App::Hermes), Some(Report::Failed(AppFailure::DownloadFailed)));
    let before_marker = format!("installed=true\nfailure=install_failed\n{RESULT_MARKER}\napp=hermes\ninstalled=false\n");
    assert!(matches!(report::parse(&before_marker, App::Hermes), Some(Report::Done(Installed { installed: false, .. }))));
}

#[test]
fn a_bad_version_or_hash_becomes_null_not_an_error() {
    let long_version = format!("version={}", "9".repeat(101));
    let output = lines_after_marker(&["app=hermes", "installed=true", &long_version, "sha256=nothex"]);
    let Some(Report::Done(done)) = report::parse(&output, App::Hermes) else { panic!("should parse") };
    assert_eq!((done.version, done.installer_sha256), (None, None));
}

// ---- log tail

#[test]
fn the_tail_keeps_the_last_twelve_lines_before_the_marker() {
    let body: Vec<String> = (1..=30).map(|n| format!("line {n}")).collect();
    let output = format!("{}\n{RESULT_MARKER}\napp=hermes\ninstalled=false\n", body.join("\n"));
    let tail = report::log_tail(&output);
    assert_eq!(tail.len(), 12);
    assert_eq!((tail[0].as_str(), tail[11].as_str()), ("line 19", "line 30"));
}

#[test]
fn a_long_line_is_cut_to_two_hundred_characters() {
    let tail = report::log_tail(&format!("{}\n", "é".repeat(500)));
    assert_eq!(tail[0].chars().count(), 200);
}

#[test]
fn control_characters_are_removed_and_empty_lines_dropped() {
    let tail = report::log_tail("\u{1b}[31mred\u{1b}[0m text\r\n\n\u{7}\ttab\u{0}bell\n   \n");
    assert_eq!(tail, ["[31mred[0m text", "tabbell"]);
}

#[test]
fn a_short_log_is_returned_whole_and_no_output_gives_an_empty_tail() {
    assert_eq!(report::log_tail("one\ntwo\n"), ["one", "two"]);
    assert!(report::log_tail("").is_empty());
}

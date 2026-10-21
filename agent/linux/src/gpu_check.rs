//! "Check the GPU inside": a read-only look, from inside a workload, at whether the GPU got there. It never assumes `nvidia-smi` exists in the image:
//! it asks `nvidia-smi` first, then looks for the NVIDIA device files, and says honestly which of the two (or neither) it found.
//! Every command is a fixed list; nothing from a request reaches one. What comes back from inside is untrusted text, so it is cut to short printable lines.
use crate::models::EngineError;
use serde::Serialize;

const SMI: [&str; 3] = ["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"];
const LIST_DEVICES: [&str; 2] = ["ls", "/dev"];
const DRIVER_VERSION: [&str; 2] = ["cat", "/proc/driver/nvidia/version"];
const DEVICE_PREFIX: &str = "nvidia";
const DEVICE_FOLDER: &str = "/dev/";
const LONGEST_LINE: usize = 160;
const MOST_LINES: usize = 8;

pub const HOW_SMI: &str = "nvidia-smi";
pub const HOW_DEVICES: &str = "device nodes";
pub const HOW_NONE: &str = "none";

pub const NOTE_SMI: &str = "The GPU is visible inside, and nvidia-smi can talk to it.";
pub const NOTE_DEVICES: &str = "The GPU device is there but nvidia-smi is not installed in this image.";
pub const NOTE_NONE: &str = "The GPU is not visible inside: there is no nvidia-smi and no NVIDIA device file.";
pub const NOTE_NOT_GIVEN: &str = "No GPU was given to this one.";

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct GpuCheck {
    pub gpu_visible: bool,
    pub how: &'static str,
    pub detail: String,
    pub note: &'static str,
}

/// The answer for a VM, or a container that was not given the GPU: nothing is run inside it.
pub fn not_given() -> GpuCheck {
    GpuCheck { gpu_visible: false, how: HOW_NONE, detail: String::new(), note: NOTE_NOT_GIVEN }
}

/// Looks inside with `exec`, which runs one fixed program with fixed arguments inside the workload and returns what it printed (an error when it failed or is not there).
pub fn look(exec: &dyn Fn(&[&str]) -> Result<String, EngineError>) -> GpuCheck {
    if let Some(card) = exec(&SMI).ok().map(|text| printable_lines(&text)).filter(|text| !text.is_empty()) {
        return GpuCheck { gpu_visible: true, how: HOW_SMI, detail: card, note: NOTE_SMI };
    }
    let devices = exec(&LIST_DEVICES).map(|text| device_nodes(&text)).unwrap_or_default();
    if devices.is_empty() {
        return GpuCheck { gpu_visible: false, how: HOW_NONE, detail: String::new(), note: NOTE_NONE };
    }
    let driver = exec(&DRIVER_VERSION).ok().and_then(|text| printable_lines(&text).lines().next().map(str::to_string));
    let found = devices.join(", ");
    let detail = driver.map_or(found.clone(), |version| format!("{found}. {version}"));
    GpuCheck { gpu_visible: true, how: HOW_DEVICES, detail, note: NOTE_DEVICES }
}

/// The NVIDIA files of a `ls /dev` listing (nvidia0, nvidiactl, nvidia-uvm...), as full paths.
pub fn device_nodes(listing: &str) -> Vec<String> {
    let plain = |name: &&str| name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    listing.lines().map(str::trim).filter(|name| name.starts_with(DEVICE_PREFIX)).filter(plain).take(MOST_LINES).map(|name| format!("{DEVICE_FOLDER}{name}")).collect()
}

/// A few short printable lines of what a program inside printed. Anything else (control characters, long lines, a flood) is cut away.
pub fn printable_lines(text: &str) -> String {
    let lines: Vec<String> = text.lines().map(|line| line.chars().filter(|c| !c.is_control()).take(LONGEST_LINE).collect::<String>().trim().to_string()).filter(|line| !line.is_empty()).take(MOST_LINES).collect();
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    /// Answers by the first word and records every call, so the order and the exact arguments can be checked.
    struct Inside {
        smi: Result<&'static str, ()>,
        devices: Result<&'static str, ()>,
        version: Result<&'static str, ()>,
        calls: RefCell<Vec<String>>,
    }

    impl Inside {
        fn answering(smi: Result<&'static str, ()>, devices: Result<&'static str, ()>, version: Result<&'static str, ()>) -> Self {
            Inside { smi, devices, version, calls: RefCell::new(Vec::new()) }
        }

        fn ask(&self, call: &[&str]) -> Result<String, EngineError> {
            self.calls.borrow_mut().push(call.join(" "));
            let answer = match call[0] { "nvidia-smi" => self.smi, "ls" => self.devices, _ => self.version };
            answer.map(str::to_string).map_err(|_| EngineError::Failed("not there".into()))
        }
    }

    #[test]
    fn nvidia_smi_is_asked_first_and_its_answer_is_the_evidence() {
        let inside = Inside::answering(Ok("NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB\n"), Err(()), Err(()));
        let found = look(&|call| inside.ask(call));
        assert_eq!(found, GpuCheck { gpu_visible: true, how: "nvidia-smi", detail: "NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB".into(), note: NOTE_SMI });
        assert_eq!(inside.calls.borrow().len(), 1, "nothing else is asked once nvidia-smi answered");
    }

    #[test]
    fn without_nvidia_smi_the_device_files_and_the_driver_file_are_the_evidence() {
        let inside = Inside::answering(Err(()), Ok("bus\nnvidia-uvm\nnvidia0\nnvidiactl\nnull\n"), Ok("NVRM version: NVIDIA UNIX x86_64 Kernel Module  580.178.04\nGCC version: gcc 13\n"));
        let found = look(&|call| inside.ask(call));
        assert_eq!((found.gpu_visible, found.how, found.note), (true, "device nodes", NOTE_DEVICES));
        assert_eq!(found.detail, "/dev/nvidia-uvm, /dev/nvidia0, /dev/nvidiactl. NVRM version: NVIDIA UNIX x86_64 Kernel Module  580.178.04");
    }

    #[test]
    fn device_files_without_a_readable_driver_file_are_still_evidence() {
        let inside = Inside::answering(Err(()), Ok("nvidia0\n"), Err(()));
        let found = look(&|call| inside.ask(call));
        assert_eq!((found.gpu_visible, found.detail.as_str()), (true, "/dev/nvidia0"));
    }

    #[test]
    fn with_neither_the_answer_is_no_and_says_so() {
        let inside = Inside::answering(Err(()), Ok("null\nzero\n"), Err(()));
        assert_eq!(look(&|call| inside.ask(call)), GpuCheck { gpu_visible: false, how: "none", detail: String::new(), note: NOTE_NONE });
        let broken = Inside::answering(Err(()), Err(()), Err(()));
        assert!(!look(&|call| broken.ask(call)).gpu_visible);
    }

    #[test]
    fn an_empty_nvidia_smi_answer_does_not_count() {
        let inside = Inside::answering(Ok("  \n"), Ok("nvidia0\n"), Err(()));
        assert_eq!(look(&|call| inside.ask(call)).how, "device nodes");
    }

    #[test]
    fn only_the_three_fixed_commands_are_ever_run() {
        let inside = Inside::answering(Err(()), Ok("nvidia0\n"), Ok("v\n"));
        look(&|call| inside.ask(call));
        assert_eq!(*inside.calls.borrow(), ["nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader", "ls /dev", "cat /proc/driver/nvidia/version"]);
    }

    #[test]
    fn hostile_text_from_inside_is_cut_to_short_printable_lines() {
        let long = "x".repeat(500);
        let text = format!("<script>alert(1)</script>\u{1b}[31mred\u{7}\n{long}\n\n");
        let cleaned = printable_lines(&text);
        assert!(!cleaned.contains('\u{1b}') && !cleaned.contains('\u{7}'));
        assert!(cleaned.lines().all(|line| line.chars().count() <= LONGEST_LINE));
        let flood = "line\n".repeat(100);
        assert_eq!(printable_lines(&flood).lines().count(), MOST_LINES);
        assert_eq!(device_nodes("nvidia0\nnvidia; rm -rf\nnvidia$(x)\nnvidia 1\n"), ["/dev/nvidia0"]);
    }

    #[test]
    fn a_workload_without_the_gpu_is_answered_without_running_anything() {
        let answer = not_given();
        assert_eq!((answer.gpu_visible, answer.how, answer.note), (false, "none", NOTE_NOT_GIVEN));
    }
}

//! The name of this machine's CPU, read once at start from `/proc/cpuinfo` (for example `AMD EPYC 7763 64-Core Processor`).
//! x86 says `model name`. Many ARM kernels do not: they say `Model` (a board), only `CPU part` (a code), or nothing at all, so when `/proc/cpuinfo`
//! has no `model name` the helper names the cores `lscpu` lists, since it resolves the part codes itself. A DGX Spark has two kinds of core and says
//! `Cortex-X925 + Cortex-A725`; only without `lscpu` does the board or the bare part code stand in.

const CPUINFO_PATH: &str = "/proc/cpuinfo";
const LSCPU_PROGRAM: &str = "lscpu";
const MAX_CHARS: usize = 120;

/// The CPU name of this machine, or None when the system does not say. `lscpu` is the text of `lscpu`, read once by the caller (see `read_lscpu`).
pub fn read(lscpu: Option<&str>) -> Option<String> {
    name_from(&std::fs::read_to_string(CPUINFO_PATH).unwrap_or_default(), lscpu)
}

/// The first `model name` of `/proc/cpuinfo` (x86); else the cores `lscpu` names; else what `/proc/cpuinfo` says without a name (`Model`, then `CPU part`).
pub fn name_from(cpuinfo: &str, lscpu: Option<&str>) -> Option<String> {
    first_value(cpuinfo, "model name").and_then(|name| tidy(&name))
        .or_else(|| lscpu.and_then(|text| crate::hardware::cores_name(&crate::hardware::parse_core_types(text))))
        .or_else(|| lscpu.and_then(parse_lscpu))
        .or_else(|| parse_cpuinfo(cpuinfo))
}

/// The text `lscpu` prints, read once at start for the CPU name and the core types. A missing or failing `lscpu` is not an error:
/// both are optional, so the machine simply does not report them.
pub fn read_lscpu() -> Option<String> {
    let output = std::process::Command::new(LSCPU_PROGRAM).stdin(std::process::Stdio::null()).output().ok()?;
    output.status.success().then(|| String::from_utf8_lossy(&output.stdout).into_owned())
}

/// The first `Model name` value in `lscpu` text, cleaned and cut like every other name.
pub fn parse_lscpu(text: &str) -> Option<String> {
    first_value(text, "model name").and_then(|name| tidy(&name))
}

/// The first `model name`; else the first `Model`; else the first `CPU part` code as `ARM CPU part 0x...`. Cleaned and cut to 120 characters.
pub fn parse_cpuinfo(text: &str) -> Option<String> {
    let found = |key: &str| first_value(text, key);
    found("model name")
        .or_else(|| found("model"))
        .or_else(|| found("cpu part").map(|part| format!("ARM CPU part {part}")))
        .and_then(|name| tidy(&name))
}

/// The value of the first line `key : value` (the key compared without case; x86 and ARM kernels differ in how they write it).
fn first_value(text: &str, key: &str) -> Option<String> {
    text.lines()
        .filter_map(|line| line.split_once(':'))
        .find(|(name, value)| name.trim().eq_ignore_ascii_case(key) && !value.trim().is_empty())
        .map(|(_, value)| value.trim().to_string())
}

/// No control characters, single spaces, at most 120 characters. None when nothing is left.
fn tidy(name: &str) -> Option<String> {
    let printable: String = name.chars().map(|c| if c.is_whitespace() { ' ' } else { c }).filter(|c| !c.is_control()).collect();
    let single: String = printable.split_whitespace().collect::<Vec<_>>().join(" ");
    let cut: String = single.chars().take(MAX_CHARS).collect();
    let cut = cut.trim_end().to_string();
    (!cut.is_empty()).then_some(cut)
}

#[cfg(test)]
mod tests {
    use super::*;

    const INTEL: &str = "processor\t: 0\nvendor_id\t: GenuineIntel\ncpu family\t: 6\nmodel\t\t: 79\nmodel name\t: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz\nstepping\t: 1\n\nprocessor\t: 1\nmodel name\t: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz\n";
    const AMD: &str = "processor\t: 0\nvendor_id\t: AuthenticAMD\nmodel\t\t: 1\nmodel name\t: AMD Ryzen 9 5950X 16-Core Processor\n";
    const ARM_NO_NAME: &str = "processor\t: 0\nBogoMIPS\t: 50.00\nFeatures\t: fp asimd evtstrm\nCPU implementer\t: 0x41\nCPU architecture: 8\nCPU variant\t: 0x3\nCPU part\t: 0xd0c\nCPU revision\t: 1\n";
    const ARM_BOARD: &str = "processor\t: 0\nCPU part\t: 0xd08\n\nHardware\t: BCM2711\nModel\t\t: Raspberry Pi 4 Model B Rev 1.2\n";

    #[test]
    fn intel_gives_the_first_model_name_not_the_numeric_model_line() {
        assert_eq!(parse_cpuinfo(INTEL).as_deref(), Some("Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz"));
    }

    #[test]
    fn amd_gives_its_model_name() {
        assert_eq!(parse_cpuinfo(AMD).as_deref(), Some("AMD Ryzen 9 5950X 16-Core Processor"));
    }

    #[test]
    fn arm_without_a_model_name_falls_back_to_the_cpu_part_code() {
        assert_eq!(parse_cpuinfo(ARM_NO_NAME).as_deref(), Some("ARM CPU part 0xd0c"));
    }

    #[test]
    fn arm_with_a_board_model_uses_it_before_the_cpu_part() {
        assert_eq!(parse_cpuinfo(ARM_BOARD).as_deref(), Some("Raspberry Pi 4 Model B Rev 1.2"));
    }

    #[test]
    fn nothing_useful_gives_none() {
        assert_eq!(parse_cpuinfo(""), None);
        assert_eq!(parse_cpuinfo("processor\t: 0\nmodel name\t:   \n"), None);
        assert_eq!(parse_cpuinfo("no colons here\n"), None);
    }

    const LSCPU_ARM: &str = "Architecture:            aarch64\n  Byte Order:            Little Endian\nCPU(s):                  20\n  Model name:            Cortex-X925\n    Thread(s) per core:  1\n";

    #[test]
    fn lscpu_names_an_arm_cpu_the_kernel_does_not_name() {
        assert_eq!(parse_lscpu(LSCPU_ARM).as_deref(), Some("Cortex-X925"));
    }

    /// `/proc/cpuinfo` of a DGX Spark: no `model name`, only part codes (0xd87 Cortex-A725 comes first, 0xd85 Cortex-X925 after).
    const SPARK_CPUINFO: &str = "processor\t: 0\nBogoMIPS\t: 2000.00\nCPU implementer\t: 0x41\nCPU part\t: 0xd87\n\nprocessor\t: 10\nCPU implementer\t: 0x41\nCPU part\t: 0xd85\n";
    const SPARK_LSCPU: &str = "Architecture: aarch64\nModel name: Cortex-X925\nCore(s) per socket: 10\nSocket(s): 1\nCPU max MHz: 3900.0000\nModel name: Cortex-A725\nCore(s) per socket: 10\nSocket(s): 1\nCPU max MHz: 2808.0000\n";

    #[test]
    fn a_dgx_spark_is_named_by_its_two_kinds_of_core_not_a_part_code() {
        assert_eq!(name_from(SPARK_CPUINFO, Some(SPARK_LSCPU)).as_deref(), Some("Cortex-X925 + Cortex-A725"));
        assert_eq!(name_from(SPARK_CPUINFO, None).as_deref(), Some("ARM CPU part 0xd87"));
    }

    #[test]
    fn x86_keeps_its_model_name_and_lscpu_names_the_cpu_before_the_board() {
        assert_eq!(name_from(INTEL, Some(LSCPU_ARM)).as_deref(), Some("Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz"));
        assert_eq!(name_from(ARM_BOARD, Some("Model name: Cortex-A72\nCore(s) per cluster: 4\nCluster(s): 1\n")).as_deref(), Some("Cortex-A72"));
        assert_eq!(name_from(ARM_NO_NAME, Some(LSCPU_ARM)).as_deref(), Some("Cortex-X925"));
        assert_eq!(name_from(ARM_BOARD, Some("")).as_deref(), Some("Raspberry Pi 4 Model B Rev 1.2"));
        assert_eq!(name_from("", None), None);
    }

    #[test]
    fn lscpu_text_without_a_model_name_gives_none() {
        assert_eq!(parse_lscpu(""), None);
        assert_eq!(parse_lscpu("Architecture: aarch64\nCPU(s): 20\n"), None);
        assert_eq!(parse_lscpu("  Model name:   \n"), None);
    }

    #[test]
    fn the_name_is_cleaned_and_cut() {
        assert_eq!(parse_cpuinfo("model name\t:  Fancy \u{1}  CPU \u{7f}  9000 \n").as_deref(), Some("Fancy CPU 9000"));
        let long = format!("model name : {}", "x".repeat(300));
        assert_eq!(parse_cpuinfo(&long).map(|name| name.chars().count()), Some(MAX_CHARS));
    }
}

//! The one fixed command that gives a console its shell: `incus exec <name> ... -- /bin/sh -c '...'`. The instance name and the workload's own
//! address are the only variable parts, and both are built here: the name from the helper's own checked workload id (`name_of`), the address only
//! after it parses as a plain IPv4 address. Nothing the browser sends reaches either.
use super::args;

/// Shown in the panel when a VM cannot be entered.
pub const NO_AGENT_MESSAGE: &str = "this VM has no incus agent, so the console cannot open";
const TERMINAL_TYPE: &str = "TERM=xterm-256color";
const LANGUAGE: &str = "LANG=C.UTF-8";
/// A login bash if the image has one, else a login sh.
const SHELL_SCRIPT: &str = "exec bash -l 2>/dev/null || exec sh -l";
/// The shell that shows the prompt: no profile and no rc files, so nothing there can reset PS1. Else an interactive sh.
/// The check for bash goes to /dev/null, never the shell itself: bash draws its prompt on standard error, so hiding that would hide the prompt.
const PROMPT_SHELL: &str = "command -v bash >/dev/null 2>&1 && exec bash --noprofile --norc -i; exec sh -i";
/// Used only when the image itself leaves PATH empty; an image that sets PATH keeps it.
const DEFAULT_PATH: &str = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
/// The end of the root prompt: the working directory, then the usual root `# `.
const PROMPT_END: &str = ":\\w# ";

/// The arguments after the `incus` program. An address that is a plain IPv4 address gives a root prompt that names it; a missing or odd one
/// keeps the login shell exactly as before.
pub fn arguments(instance: &str, address: Option<&str>) -> Vec<String> {
    let script = prompt_address(address).map_or_else(|| SHELL_SCRIPT.to_string(), |checked| prompt_script(&checked));
    args(&["exec", instance, "--env", TERMINAL_TYPE, "--env", LANGUAGE, "--", "/bin/sh", "-c", &script])
}

/// The address as canonical dotted text, or None when it is missing or is not a plain IPv4 address. Parsing refuses everything else
/// (`1.2.3.4; rm -rf /`, `$(id)`, `a b`, `--help`, `01.2.3.4`), so no other text can reach the shell script.
fn prompt_address(address: Option<&str>) -> Option<String> {
    address?.parse::<std::net::Ipv4Addr>().ok().map(|ip| ip.to_string())
}

/// The fixed prompt script for one checked address: a root prompt, a usable PATH, then an interactive shell that reads no rc files.
/// The address is dotted digits only, so it cannot end the single-quoted prompt.
fn prompt_script(address: &str) -> String {
    format!("PS1='root@{address}{PROMPT_END}'; export PS1; [ -n \"$PATH\" ] || PATH={DEFAULT_PATH}; export PATH; {PROMPT_SHELL}")
}

/// A command that does nothing inside the workload: it only succeeds when the guest agent answers.
pub fn agent_probe() -> Vec<String> {
    args(&["true"])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::incus::name_of;

    const TODAY: &str = "exec bash -l 2>/dev/null || exec sh -l";

    #[test]
    fn the_argument_list_is_exactly_the_fixed_one() {
        assert_eq!(
            arguments("ms-abc123", None),
            ["exec", "ms-abc123", "--env", "TERM=xterm-256color", "--env", "LANG=C.UTF-8", "--", "/bin/sh", "-c", TODAY]
        );
    }

    #[test]
    fn an_address_gives_a_root_prompt_that_names_it_without_a_login_shell() {
        let list = arguments("ms-abc123", Some("10.0.0.5"));
        assert_eq!(list.len(), 10, "the same shape, only the script differs");
        assert_eq!(&list[..9], &arguments("ms-abc123", None)[..9]);
        let shown = list.last().cloned().unwrap();
        assert!(shown.contains("PS1='root@10.0.0.5:\\w# '"), "{shown}");
        assert!(shown.contains("--noprofile --norc -i"), "{shown}");
        assert!(!shown.contains(" -l"), "no login shell, which would reset the prompt: {shown}");
        assert!(!shown.contains("--login"), "{shown}");
        assert!(shown.contains("export PS1"), "the prompt must survive the handover: {shown}");
        assert!(shown.contains(DEFAULT_PATH), "a usable PATH when the image has none: {shown}");
    }

    #[test]
    fn a_missing_or_hostile_address_keeps_todays_command() {
        let hostile = [
            "1.2.3.4; rm -rf /",
            "$(id)",
            "`id`",
            "a b",
            "--help",
            "-c",
            "1.2.3.4\n",
            " 1.2.3.4",
            "1.2.3",
            "1.2.3.4.5",
            "01.2.3.4",
            "256.1.1.1",
            "1.2.3.4/24",
            "",
        ];
        for address in hostile {
            assert_eq!(arguments("ms-abc123", Some(address)), arguments("ms-abc123", None), "{address}");
        }
    }

    #[test]
    fn a_hostile_id_never_changes_anything_but_the_instance_slot() {
        for hostile in ["a b", "../x", "--help", "x; rm -rf /", "$(id)", "-c"] {
            let list = arguments(&name_of(hostile), Some("10.0.0.5"));
            assert_eq!(list.len(), 10, "{hostile}");
            assert_eq!(list[1], format!("ms-{hostile}"), "the id sits in one argument, prefixed so it can never be a flag");
            assert_eq!(&list[2..], &arguments("ms-x", Some("10.0.0.5"))[2..], "{hostile}");
        }
    }
}

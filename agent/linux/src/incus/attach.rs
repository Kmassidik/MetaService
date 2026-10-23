//! The one fixed command that gives a console its shell: `incus exec <name> ... -- /bin/sh -c '...'`. The instance name is the only variable part,
//! and it is built from the helper's own checked workload id (`name_of`), never from anything the browser sends.
use super::args;

/// Shown in the panel when a VM cannot be entered.
pub const NO_AGENT_MESSAGE: &str = "this VM has no incus agent, so the console cannot open";
const TERMINAL_TYPE: &str = "TERM=xterm-256color";
const LANGUAGE: &str = "LANG=C.UTF-8";
/// A login bash if the image has one, else a login sh.
const SHELL_SCRIPT: &str = "exec bash -l 2>/dev/null || exec sh -l";

/// The arguments after the `incus` program.
pub fn arguments(instance: &str) -> Vec<String> {
    args(&["exec", instance, "--env", TERMINAL_TYPE, "--env", LANGUAGE, "--", "/bin/sh", "-c", SHELL_SCRIPT])
}

/// A command that does nothing inside the workload: it only succeeds when the guest agent answers.
pub fn agent_probe() -> Vec<String> {
    args(&["true"])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::incus::name_of;

    #[test]
    fn the_argument_list_is_exactly_the_fixed_one() {
        assert_eq!(
            arguments("ms-abc123"),
            ["exec", "ms-abc123", "--env", "TERM=xterm-256color", "--env", "LANG=C.UTF-8", "--", "/bin/sh", "-c", "exec bash -l 2>/dev/null || exec sh -l"]
        );
    }

    #[test]
    fn a_hostile_id_never_changes_anything_but_the_instance_slot() {
        for hostile in ["a b", "../x", "--help", "x; rm -rf /", "$(id)", "-c"] {
            let list = arguments(&name_of(hostile));
            assert_eq!(list.len(), 10, "{hostile}");
            assert_eq!(list[1], format!("ms-{hostile}"), "the id sits in one argument, prefixed so it can never be a flag");
            assert_eq!(&list[2..], &arguments("ms-x")[2..], "{hostile}");
        }
    }
}

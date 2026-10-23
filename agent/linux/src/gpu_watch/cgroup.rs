//! Which Incus instance a process belongs to, read from the lines of `/proc/<pid>/cgroup`.
//! Incus (LXC) puts the programs of an instance under a cgroup path with `lxc.payload.<name>` (older: `incus.payload.<name>`, or `/lxc/<name>/`).

const LXC_PAYLOAD: &str = "lxc.payload.";
const INCUS_PAYLOAD: &str = "incus.payload.";
const LXC_PARENT: &str = "lxc";

/// The instance name found in the text of a cgroup file (v2: one `0::/path` line; v1: one line per controller), or None for a process outside any instance.
pub fn instance_name(cgroup_text: &str) -> Option<String> {
    cgroup_text.lines().find_map(name_in_line)
}

fn name_in_line(line: &str) -> Option<String> {
    let path = line.splitn(3, ':').nth(2)?;
    let parts: Vec<&str> = path.split('/').filter(|part| !part.is_empty()).collect();
    parts.iter().enumerate().find_map(|(index, part)| payload_name(part).or_else(|| lxc_child(&parts, index)))
}

fn payload_name(part: &str) -> Option<String> {
    let name = part.strip_prefix(LXC_PAYLOAD).or_else(|| part.strip_prefix(INCUS_PAYLOAD))?;
    (!name.is_empty()).then(|| name.to_string())
}

/// The part after a `lxc` folder: `/lxc/<name>/...`.
fn lxc_child(parts: &[&str], index: usize) -> Option<String> {
    (parts[index] == LXC_PARENT).then(|| parts.get(index + 1)).flatten().map(|name| name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_two_line() {
        assert_eq!(instance_name("0::/lxc.payload.ms-w-1/system.slice/python.service\n").as_deref(), Some("ms-w-1"));
        assert_eq!(instance_name("0::/incus.payload.ms-w-2/init.scope\n").as_deref(), Some("ms-w-2"));
        assert_eq!(instance_name("0::/system.slice/incus.service/lxc.payload.ms-w-3\n").as_deref(), Some("ms-w-3"));
    }

    #[test]
    fn version_one_lines() {
        let text = "12:memory:/lxc/ms-w-4/system.slice\n11:cpu,cpuacct:/lxc/ms-w-4/system.slice\n1:name=systemd:/lxc/ms-w-4/init.scope\n";
        assert_eq!(instance_name(text).as_deref(), Some("ms-w-4"));
        assert_eq!(instance_name("2:cpu:/\n1:name=systemd:/lxc.payload.ms-w-5/x\n").as_deref(), Some("ms-w-5"));
    }

    #[test]
    fn processes_outside_an_instance_have_no_name() {
        for text in ["", "0::/user.slice/user-1000.slice/session-3.scope\n", "0::/\n", "0::/lxc\n", "0::/lxc.payload.\n", "garbage", "1:name=systemd:/init.scope\n"] {
            assert_eq!(instance_name(text), None, "{text:?}");
        }
    }
}

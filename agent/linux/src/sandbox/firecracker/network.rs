//! The network one sandbox gets: its own namespace, a tap inside it, a veth pair to the machine, and the firewall rules that keep everything the plan
//! calls closed (sandbox/README.md, Safety) closed.
//!
//! Every clone of a template thinks it has the same address, so the guest's own addresses are constants (`172.16.0.0/30`) and each sandbox gets a
//! namespace where that is true; the machine sees a unique `/30` per slot instead. Nothing here runs anything: the builder answers the exact program
//! and argv list, and the runner is what executes it as root.
use super::{sandbox_user, Step, UID_BASE};

const IP: &str = "ip";
const IPTABLES: &str = "iptables";

/// What the guest sees inside the namespace, the same for every sandbox because a clone's kernel already has it.
const TAP: &str = "tap0";
const GUEST_GATEWAY: &str = "172.16.0.1/30";
/// The machine's own end of the veth pair gets `10.<PREFIX + slot>.0.2`, the namespace's `10.<PREFIX + slot>.0.1`.
const PREFIX: u16 = 64;
const PREFIX_MASK: &str = "/30";
const HOST_END: u8 = 2;
const NAMESPACE_END: u8 = 1;

/// The longest device name the kernel takes.
const DEVICE_NAME_MAX: usize = 15;

/// Everything closed from inside a sandbox, whatever else it may reach: the office LAN and every private or special range, the machine itself, other
/// sandboxes, link-local and cloud metadata (`169.254.169.254`), multicast and the reserved blocks.
const CLOSED_RANGES: [&str; 10] = [
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "100.64.0.0/10", "192.0.0.0/24", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4", "0.0.0.0/8",
];
/// The one outgoing port the plan closes on top of the ranges, so no sandbox is a mail relay.
const MAIL_PORT: &str = "25";

/// One sandbox's network, named from its slot. A slot is taken while the sandbox lives, so two live sandboxes never share an address, a tap or a uid.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Network {
    slot: u8,
}

impl Network {
    pub fn of(slot: u8) -> Network {
        Network { slot }
    }

    /// The namespace, and the two ends of the veth pair: short, because a device name may not pass 15 characters.
    pub fn namespace(self) -> String {
        format!("ms{}", self.slot)
    }

    pub fn host_link(self) -> String {
        format!("ms{}h", self.slot)
    }

    pub fn guest_link(self) -> String {
        format!("ms{}n", self.slot)
    }

    /// The machine's `/30` for this sandbox: unique per live slot, and inside `10.0.0.0/8` so every other sandbox's traffic is dropped by the rules below.
    pub fn subnet(self) -> String {
        format!("10.{}.0.0{PREFIX_MASK}", PREFIX + u16::from(self.slot))
    }

    pub fn host_address(self) -> String {
        format!("10.{}.0.{HOST_END}", PREFIX + u16::from(self.slot))
    }

    pub fn guest_address(self) -> String {
        format!("10.{}.0.{NAMESPACE_END}", PREFIX + u16::from(self.slot))
    }

    /// The tap the guest's kernel talks to, handed to the sandbox's own unprivileged user.
    pub fn tap(self) -> &'static str {
        TAP
    }
}

/// The steps that make the namespace: a tap inside it, a veth pair to the machine, and a default route through the pair. Internet on or off is the
/// firewall's business, not the addresses'.
pub fn create_steps(net: Network) -> Vec<Step> {
    let namespace = net.namespace();
    let in_namespace = |arguments: &[&str]| {
        let mut all = vec!["netns".to_string(), "exec".to_string(), namespace.clone()];
        all.extend(arguments.iter().map(|argument| argument.to_string()));
        Step::new(IP, all)
    };
    vec![
        Step::new(IP, vec!["netns".into(), "add".into(), namespace.clone()]),
        in_namespace(&["ip", "link", "set", "dev", "lo", "up"]),
        in_namespace(&["ip", "tuntap", "add", "dev", TAP, "mode", "tap", "user", &sandbox_user(net.slot)]),
        in_namespace(&["ip", "addr", "add", GUEST_GATEWAY, "dev", TAP]),
        in_namespace(&["ip", "link", "set", "dev", TAP, "up"]),
        // The namespace routes between the tap and the veth pair, so forwarding must be on inside it; the machine's own setting is setup's job.
        in_namespace(&["sysctl", "-q", "-w", "net.ipv4.ip_forward=1"]),
        Step::new(IP, vec!["link".into(), "add".into(), net.host_link(), "type".into(), "veth".into(), "peer".into(), "name".into(), net.guest_link()]),
        Step::new(IP, vec!["addr".into(), "add".into(), format!("{}{PREFIX_MASK}", net.host_address()), "dev".into(), net.host_link()]),
        Step::new(IP, vec!["link".into(), "set".into(), "dev".into(), net.host_link(), "up".into()]),
        Step::new(IP, vec!["link".into(), "set".into(), "dev".into(), net.guest_link(), "netns".into(), namespace.clone()]),
        in_namespace(&["ip", "addr", "add", &format!("{}{PREFIX_MASK}", net.guest_address()), "dev", &net.guest_link()]),
        in_namespace(&["ip", "link", "set", "dev", &net.guest_link(), "up"]),
        in_namespace(&["ip", "route", "add", "default", "via", &net.host_address()]),
    ]
}

/// The steps that take the namespace away again. Each one is tried whether or not the last was there, because a delete is repeated freely: a sandbox
/// that is already gone answers the same as one that was just stopped.
pub fn delete_steps(net: Network) -> Vec<Step> {
    vec![
        Step::new(IP, vec!["link".into(), "del".into(), "dev".into(), net.host_link()]),
        Step::new(IP, vec!["netns".into(), "del".into(), net.namespace()]),
    ]
}

/// The rules that keep every closed range closed from inside one sandbox, plus the one rule that opens the internet when this sandbox may have it.
///
/// They sit in the machine's `FORWARD` chain, keyed by the sandbox's own veth end, because that is where the real destination is still visible: inside
/// the namespace every packet's next hop is the tap, so a rule there would see the tap and nothing else.
pub fn network_rules(net: Network, uplink: &str, internet: bool) -> Result<Vec<Step>, String> {
    if !is_device_name(uplink) {
        return Err(format!("{uplink:?} is not a network device name"));
    }
    let link = net.host_link();
    let forward = |rule: &[&str]| {
        let mut arguments = vec!["-w".to_string(), "5".to_string(), "-A".to_string(), "FORWARD".to_string(), "-i".to_string(), link.clone()];
        arguments.extend(rule.iter().map(|argument| argument.to_string()));
        Step::new(IPTABLES, arguments)
    };
    let mut steps: Vec<Step> = CLOSED_RANGES.iter().map(|range| forward(&["-d", range, "-j", "DROP"])).collect();
    steps.push(forward(&["-p", "tcp", "--dport", MAIL_PORT, "-j", "DROP"]));
    if !internet {
        steps.push(forward(&["-j", "DROP"]));
        return Ok(steps);
    }
    // Out to the internet, and only the answers to what the sandbox itself opened coming back. Both come after every range above.
    steps.push(Step::new(IPTABLES, vec!["-w".into(), "5".into(), "-A".into(), "FORWARD".into(), "-i".into(), link.clone(), "-o".into(), uplink.into(), "-j".into(), "ACCEPT".into()]));
    steps.push(Step::new(IPTABLES, vec!["-w".into(), "5".into(), "-A".into(), "FORWARD".into(), "-i".into(), uplink.into(), "-o".into(), link, "-m".into(),
        "conntrack".into(), "--ctstate".into(), "RELATED,ESTABLISHED".into(), "-j".into(), "ACCEPT".into()]));
    steps.push(Step::new(IPTABLES, vec!["-w".into(), "5".into(), "-t".into(), "nat".into(), "-A".into(), "POSTROUTING".into(), "-s".into(), net.subnet(), "-o".into(), uplink.into(), "-j".into(), "MASQUERADE".into()]));
    Ok(steps)
}

/// The same rules as `-D`, so a delete takes them out. A rule that is no longer there is not an error to the runner: it reports it and carries on.
pub fn network_rule_deletions(net: Network, uplink: &str, internet: bool) -> Result<Vec<Step>, String> {
    let added = network_rules(net, uplink, internet)?;
    Ok(added.into_iter().map(undone).collect())
}

/// One rule, turned from `-A <chain>` into `-D <chain>`: the chain is the field after `-A`.
fn undone(step: Step) -> Step {
    let mut arguments = step.arguments;
    if let Some(position) = arguments.iter().position(|argument| argument == "-A") {
        arguments[position] = "-D".into();
    }
    Step::new(IPTABLES, arguments)
}

/// A device name the kernel takes: letters, digits, `-`, `_` and `.`, at most 15 characters, and starting with a letter or a digit so it can never be read
/// as an option.
fn is_device_name(name: &str) -> bool {
    let allowed = |character: char| character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.');
    let Some(first) = name.chars().next() else { return false };
    first.is_ascii_alphanumeric() && name.len() <= DEVICE_NAME_MAX && name.chars().all(allowed)
}

/// The user a sandbox's tap belongs to, and the uid and gid its jailer drops to: `UID_BASE + slot`, so the tap can be handed over before the jailer
/// drops root.
pub fn owner(slot: u8) -> (String, u32, u32) {
    (sandbox_user(slot), UID_BASE + u32::from(slot), UID_BASE + u32::from(slot))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn net() -> Network {
        Network::of(7)
    }

    fn lines(steps: &[Step]) -> Vec<String> {
        steps.iter().map(Step::describe).collect()
    }

    #[test]
    fn a_sandbox_gets_its_own_names_namespace_and_subnet_from_its_slot() {
        assert_eq!((net().namespace(), net().host_link(), net().guest_link()), ("ms7".into(), "ms7h".into(), "ms7n".into()));
        assert_eq!((net().subnet(), net().host_address(), net().guest_address()), ("10.71.0.0/30".into(), "10.71.0.2".into(), "10.71.0.1".into()));
        assert_eq!((net().tap(), Network::of(0).tap()), ("tap0", "tap0"), "the tap is the same name in every namespace, which is the point of the namespace");
        assert_ne!(Network::of(1).subnet(), net().subnet());
        for slot in 0..super::super::SLOTS {
            let names = [Network::of(slot).namespace(), Network::of(slot).host_link(), Network::of(slot).guest_link()];
            for name in names {
                assert!(is_device_name(&name), "{name} must be a device name");
            }
            assert_eq!(Network::of(slot).host_link().len(), Network::of(slot).guest_link().len());
        }
    }

    #[test]
    fn making_the_namespace_is_the_same_fixed_list_every_time() {
        assert_eq!(lines(&create_steps(net())), [
            "ip netns add ms7",
            "ip netns exec ms7 ip link set dev lo up",
            "ip netns exec ms7 ip tuntap add dev tap0 mode tap user mssbx7",
            "ip netns exec ms7 ip addr add 172.16.0.1/30 dev tap0",
            "ip netns exec ms7 ip link set dev tap0 up",
            "ip netns exec ms7 sysctl -q -w net.ipv4.ip_forward=1",
            "ip link add ms7h type veth peer name ms7n",
            "ip addr add 10.71.0.2/30 dev ms7h",
            "ip link set dev ms7h up",
            "ip link set dev ms7n netns ms7",
            "ip netns exec ms7 ip addr add 10.71.0.1/30 dev ms7n",
            "ip netns exec ms7 ip link set dev ms7n up",
            "ip netns exec ms7 ip route add default via 10.71.0.2",
        ].map(String::from));
        assert_eq!(lines(&delete_steps(net())), ["ip link del dev ms7h", "ip netns del ms7"].map(String::from));
        assert_eq!(owner(7), ("mssbx7".into(), 30_007, 30_007));
    }

    #[test]
    fn every_closed_range_is_dropped_from_the_sandbox_and_mail_with_it() {
        let rules = lines(&network_rules(net(), "eth0", false).ok().unwrap());
        assert_eq!(rules, [
            "iptables -w 5 -A FORWARD -i ms7h -d 10.0.0.0/8 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 172.16.0.0/12 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 192.168.0.0/16 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 169.254.0.0/16 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 100.64.0.0/10 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 192.0.0.0/24 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 198.18.0.0/15 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 224.0.0.0/4 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 240.0.0.0/4 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -d 0.0.0.0/8 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -p tcp --dport 25 -j DROP",
            "iptables -w 5 -A FORWARD -i ms7h -j DROP",
        ].map(String::from));
        assert_eq!(rules.iter().filter(|rule| rule.contains("MASQUERADE")).count(), 0, "a sandbox with no internet gets no way out");
    }

    #[test]
    fn a_sandbox_with_internet_gets_one_way_out_and_the_rules_still_come_first() {
        let rules = lines(&network_rules(Network::of(0), "eth0", true).ok().unwrap());
        let last: Vec<&String> = rules.iter().rev().take(3).collect();
        assert_eq!(last, [&"iptables -w 5 -t nat -A POSTROUTING -s 10.64.0.0/30 -o eth0 -j MASQUERADE".to_string(),
                          &"iptables -w 5 -A FORWARD -i eth0 -o ms0h -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT".to_string(),
                          &"iptables -w 5 -A FORWARD -i ms0h -o eth0 -j ACCEPT".to_string()]);
        assert_eq!(rules.len(), CLOSED_RANGES.len() + 4, "every closed range, mail, and the three that open one way out");
        for rule in rules.iter().take(CLOSED_RANGES.len() + 1) {
            assert!(rule.contains("-j DROP"), "{rule} must come before anything is let through");
        }
        assert_eq!(network_rules(net(), "eth0", false).ok().unwrap().len(), CLOSED_RANGES.len() + 2);
    }

    #[test]
    fn the_deletions_are_the_same_rules_taken_away_again() {
        let added = lines(&network_rules(net(), "eth0", true).ok().unwrap());
        let removed = lines(&network_rule_deletions(net(), "eth0", true).ok().unwrap());
        assert_eq!(added.len(), removed.len());
        for (rule, undone) in added.iter().zip(&removed) {
            assert_eq!(rule.replace(" -A ", " -D "), *undone, "a delete names the same rule, with -D");
        }
    }

    #[test]
    fn a_hostile_uplink_is_refused_rather_than_run() {
        for bad in ["", "eth 0", "eth0;reboot", "../x", "--help", "averylongdevicename", "---"] {
            assert!(network_rules(net(), bad, true).is_err(), "{bad:?}");
            assert!(network_rule_deletions(net(), bad, true).is_err(), "{bad:?}");
        }
        assert!(network_rules(net(), "br0.10", true).is_ok());
    }
}

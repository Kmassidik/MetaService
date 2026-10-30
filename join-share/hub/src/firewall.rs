//! pf anchor rules. Pure text, so it is testable anywhere.
use crate::peers::Net;

/// A far PC may only reach the parent listener on the hub address. The `rdr`
/// sends it to the parent on loopback and keeps the far PC's own address
/// (10.77.0.x) as the source, so the parent records the machine at its
/// WireGuard address with no parent code change. Everything else coming in on
/// the interface is dropped (no peer-to-peer); traffic out to peers passes.
/// `parent_port` is the port of JOIN_SHARE_PARENT_URL (9102 by default).
pub fn anchor_rules(iface: &str, net: &Net, parent_port: u16) -> String {
    let hub = net.hub();
    format!(
        "# join-share: generated, do not edit\n\
         rdr pass on {iface} inet proto tcp from any to {hub} port {parent_port} -> 127.0.0.1 port {parent_port}\n\
         block in quick on {iface} all\n\
         pass out quick on {iface} all\n"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rules() -> String {
        anchor_rules("utun7", &Net::parse("10.77.0.0/24").unwrap(), 9102)
    }

    #[test]
    fn redirects_only_the_parent_port_to_loopback() {
        assert!(rules().contains("rdr pass on utun7 inet proto tcp from any to 10.77.0.1 port 9102 -> 127.0.0.1 port 9102"));
        assert_eq!(rules().matches("rdr ").count(), 1);
    }

    #[test]
    fn blocks_everything_else_in_and_passes_out() {
        let text = rules();
        assert!(text.contains("block in quick on utun7 all\n"));
        assert!(text.contains("pass out quick on utun7 all\n"));
        assert_eq!(text.lines().count(), 4);
    }

    #[test]
    fn uses_the_given_hub_address() {
        let text = anchor_rules("utun3", &Net::parse("10.88.0.0/24").unwrap(), 9192);
        assert!(text.contains("to 10.88.0.1 port 9192 -> 127.0.0.1 port 9192"));
    }
}

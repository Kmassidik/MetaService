//! The WireGuard network and the "lowest free address" rule.
use std::collections::HashSet;
use std::net::Ipv4Addr;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Net {
    base: u32,
    prefix: u8,
}

impl Net {
    /// `10.77.0.0/24`; host bits are masked off. Prefix 16..=30 keeps it sane.
    pub fn parse(text: &str) -> Result<Net, String> {
        let (ip, len) = text
            .split_once('/')
            .ok_or("network must look like 10.77.0.0/24")?;
        let ip: Ipv4Addr = ip.trim().parse().map_err(|_| format!("bad network address: {ip}"))?;
        let prefix: u8 = len.trim().parse().map_err(|_| format!("bad network prefix: {len}"))?;
        if !(16..=30).contains(&prefix) {
            return Err("network prefix must be between 16 and 30".into());
        }
        let mask = u32::MAX << (32 - prefix);
        Ok(Net { base: u32::from(ip) & mask, prefix })
    }

    fn broadcast(&self) -> u32 {
        self.base | !(u32::MAX << (32 - self.prefix))
    }

    pub fn hub(&self) -> Ipv4Addr {
        Ipv4Addr::from(self.base + 1)
    }

    pub fn cidr(&self) -> String {
        format!("{}/{}", Ipv4Addr::from(self.base), self.prefix)
    }

    /// The hub's own interface address with the network prefix: `10.77.0.1/24`.
    pub fn hub_cidr(&self) -> String {
        format!("{}/{}", self.hub(), self.prefix)
    }

    /// True for addresses a far PC may hold (not the network, the hub or the broadcast).
    pub fn is_peer_address(&self, addr: Ipv4Addr) -> bool {
        let n = u32::from(addr);
        n > self.base + 1 && n < self.broadcast()
    }

    pub fn lowest_free(&self, used: &[Ipv4Addr]) -> Option<Ipv4Addr> {
        let taken: HashSet<u32> = used.iter().map(|a| u32::from(*a)).collect();
        (self.base + 2..self.broadcast())
            .find(|candidate| !taken.contains(candidate))
            .map(Ipv4Addr::from)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn net() -> Net {
        Net::parse("10.77.0.0/24").unwrap()
    }

    fn ip(s: &str) -> Ipv4Addr {
        s.parse().unwrap()
    }

    #[test]
    fn first_peer_is_dot_two_and_hub_is_dot_one() {
        assert_eq!(net().hub(), ip("10.77.0.1"));
        assert_eq!(net().lowest_free(&[]), Some(ip("10.77.0.2")));
    }

    #[test]
    fn takes_lowest_gap_and_reuses_freed_address() {
        let n = net();
        assert_eq!(n.lowest_free(&[ip("10.77.0.2"), ip("10.77.0.3")]), Some(ip("10.77.0.4")));
        // .2 was removed: the next machine gets it back.
        assert_eq!(n.lowest_free(&[ip("10.77.0.3")]), Some(ip("10.77.0.2")));
    }

    #[test]
    fn full_network_gives_none() {
        let n = Net::parse("10.77.0.0/30").unwrap();
        assert_eq!(n.lowest_free(&[ip("10.77.0.2")]), None);
    }

    #[test]
    fn peer_address_rules() {
        let n = net();
        assert!(n.is_peer_address(ip("10.77.0.2")));
        assert!(n.is_peer_address(ip("10.77.0.254")));
        assert!(!n.is_peer_address(ip("10.77.0.1")));
        assert!(!n.is_peer_address(ip("10.77.0.0")));
        assert!(!n.is_peer_address(ip("10.77.0.255")));
        assert!(!n.is_peer_address(ip("10.78.0.2")));
    }

    #[test]
    fn parse_masks_host_bits_and_rejects_junk() {
        assert_eq!(Net::parse("10.77.0.9/24").unwrap().cidr(), "10.77.0.0/24");
        assert_eq!(net().hub_cidr(), "10.77.0.1/24");
        assert!(Net::parse("10.77.0.0").is_err());
        assert!(Net::parse("10.77.0.0/8").is_err());
        assert!(Net::parse("nope/24").is_err());
    }
}

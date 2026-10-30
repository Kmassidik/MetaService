//! `wg-metaservice.conf` text, and the strict validator the root helper applies to it.
//! wg-quick runs PostUp-style keys as root, so only a short allow-list passes.
use super::alloc::Net;
use crate::crypto::is_wg_key;
use std::net::Ipv4Addr;

pub struct HubPeer {
    pub name: String,
    pub public_key: String,
    pub address: Ipv4Addr,
}

pub fn render(private_key: &str, net: &Net, port: u16, peers: &[HubPeer]) -> String {
    let mut text = format!(
        "[Interface]\nPrivateKey = {private_key}\nAddress = {}\nListenPort = {port}\n",
        net.hub_cidr()
    );
    for peer in peers {
        text.push_str(&format!(
            "\n# {}\n[Peer]\nPublicKey = {}\nAllowedIPs = {}/32\n",
            peer.name, peer.public_key, peer.address
        ));
    }
    text
}

#[derive(PartialEq, Clone, Copy)]
enum Section {
    None,
    Interface,
    Peer,
}

/// Err carries a plain reason. Accepts exactly what `render` produces.
pub fn validate(text: &str) -> Result<(), String> {
    let mut section = Section::None;
    let mut seen_interface = false;
    for (index, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        match line {
            "[Interface]" if !seen_interface => {
                seen_interface = true;
                section = Section::Interface;
            }
            "[Peer]" if seen_interface => section = Section::Peer,
            _ if line.starts_with('[') => return Err(format!("unexpected section at line {}", index + 1)),
            _ => check_pair(section, line).map_err(|why| format!("line {}: {why}", index + 1))?,
        }
    }
    if seen_interface { Ok(()) } else { Err("missing [Interface]".into()) }
}

fn check_pair(section: Section, line: &str) -> Result<(), String> {
    let (key, value) = line.split_once('=').ok_or("not key = value")?;
    let (key, value) = (key.trim(), value.trim());
    match (section, key) {
        (Section::Interface, "PrivateKey") | (Section::Peer, "PublicKey") => ok_if(is_wg_key(value), "key"),
        (Section::Interface, "Address") => ok_if(is_cidr(value), "Address"),
        (Section::Interface, "ListenPort") => ok_if(value.parse::<u16>().is_ok(), "ListenPort"),
        (Section::Peer, "AllowedIPs") => ok_if(value.strip_suffix("/32").is_some_and(|ip| ip.parse::<Ipv4Addr>().is_ok()), "AllowedIPs"),
        _ => Err("key not allowed here".to_string()),
    }
}

fn ok_if(good: bool, what: &str) -> Result<(), String> {
    if good { Ok(()) } else { Err(format!("bad value for {what}")) }
}

fn is_cidr(value: &str) -> bool {
    Net::parse(value).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::base64_encode;

    fn key(n: u8) -> String {
        base64_encode(&[n; 32])
    }

    fn sample() -> String {
        let peers = vec![HubPeer { name: "my-mac".into(), public_key: key(2), address: "10.77.0.2".parse().unwrap() }];
        render(&key(1), &Net::parse("10.77.0.0/24").unwrap(), 51830, &peers)
    }

    #[test]
    fn render_has_interface_and_peer_lines() {
        let text = sample();
        assert!(text.contains("Address = 10.77.0.1/24"));
        assert!(text.contains("ListenPort = 51830"));
        assert!(text.contains("AllowedIPs = 10.77.0.2/32"));
        assert!(text.contains("# my-mac"));
    }

    #[test]
    fn rendered_text_validates() {
        assert!(validate(&sample()).is_ok());
    }

    #[test]
    fn validator_refuses_command_keys_and_junk() {
        let evil = sample().replace("ListenPort = 51830", "PostUp = touch /tmp/x");
        assert!(validate(&evil).is_err());
        assert!(validate("[Peer]\nPublicKey = x\n").is_err());
        assert!(validate("").is_err());
        assert!(validate(&format!("{}\n[Interface]\n", sample())).is_err());
        assert!(validate(&sample().replace("/32", "/24")).is_err());
    }
}

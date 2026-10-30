//! Argument validation for `join-share-root`. Anything not listed is refused;
//! every argument is checked before any command runs as root.
use crate::constants::{DEFAULT_PF_ANCHOR, DEFAULT_WG_NAME, PARENT_LISTENER_PORT, PF_ANCHOR_PREFIX};
use crate::crypto::is_wg_key;
use std::net::Ipv4Addr;
use std::path::PathBuf;

/// A command plus the names it works on (defaults when no option is given).
#[derive(Debug, PartialEq, Eq)]
pub struct RootRequest {
    pub command: RootCommand,
    pub wg_name: String,
    pub anchor: String,
    pub parent_port: u16,
}

#[derive(Debug, PartialEq, Eq)]
pub enum RootCommand {
    Up { conf: PathBuf },
    Down,
    AddPeer { public_key: String, address: Ipv4Addr },
    RemovePeer { public_key: String },
    PfLoad { iface: Option<String> },
    PfUnload,
    Show,
}

/// `utun` plus digits, or a valid WireGuard config name.
pub fn is_iface_name(name: &str) -> bool {
    let utun_digits = name.strip_prefix("utun").is_some_and(|d| !d.is_empty() && d.len() <= 6 && d.bytes().all(|b| b.is_ascii_digit()));
    utun_digits || is_wg_name(name)
}

/// wg-quick's own rule for interface names (at most 15 characters), minus a leading dash.
pub fn is_wg_name(name: &str) -> bool {
    let chars_ok = name.bytes().all(|b| b.is_ascii_alphanumeric() || b"_=+.-".contains(&b));
    chars_ok && !name.is_empty() && name.len() <= 15 && !name.starts_with('-')
}

/// Must live under `com.apple/` (Apple's main ruleset already scans it); one extra segment only.
pub fn is_anchor_name(name: &str) -> bool {
    let rest_ok = |rest: &str| !rest.is_empty() && rest.len() <= 48 && rest.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b));
    name.strip_prefix(PF_ANCHOR_PREFIX).is_some_and(rest_ok)
}

fn exact<const N: usize>(args: &[String]) -> Result<&[String; N], String> {
    args.try_into().map_err(|_| format!("expected {N} argument(s)"))
}

fn key_arg(text: &str) -> Result<String, String> {
    if is_wg_key(text) { Ok(text.to_string()) } else { Err("not a WireGuard public key".into()) }
}

fn address_arg(text: &str) -> Result<Ipv4Addr, String> {
    text.parse().map_err(|_| "not an IPv4 address".to_string())
}

fn conf_arg(text: &str, wg_name: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(text);
    let named_right = path.file_name().is_some_and(|n| *n == *format!("{wg_name}.conf"));
    if path.is_absolute() && named_right {
        return Ok(path);
    }
    Err(format!("config must be an absolute path ending in {wg_name}.conf"))
}

fn iface_arg(args: &[String]) -> Result<Option<String>, String> {
    match args {
        [] => Ok(None),
        [name] if is_iface_name(name) => Ok(Some(name.clone())),
        [_] => Err("bad interface name".into()),
        _ => Err("expected at most 1 argument".into()),
    }
}

/// Removes `--flag value` from the list and returns the value.
fn take_option(args: &mut Vec<String>, flag: &str) -> Result<Option<String>, String> {
    let Some(pos) = args.iter().position(|a| a == flag) else {
        return Ok(None);
    };
    if pos + 1 >= args.len() {
        return Err(format!("{flag} needs a value"));
    }
    let value = args.remove(pos + 1);
    args.remove(pos);
    Ok(Some(value))
}

fn parse_command(args: &[String], wg_name: &str) -> Result<RootCommand, String> {
    let (name, rest) = args.split_first().ok_or("missing subcommand")?;
    match name.as_str() {
        "up" => Ok(RootCommand::Up { conf: conf_arg(&exact::<1>(rest)?[0], wg_name)? }),
        "down" => exact::<0>(rest).map(|_| RootCommand::Down),
        "add-peer" => {
            let [key, addr] = exact::<2>(rest)?;
            Ok(RootCommand::AddPeer { public_key: key_arg(key)?, address: address_arg(addr)? })
        }
        "remove-peer" => Ok(RootCommand::RemovePeer { public_key: key_arg(&exact::<1>(rest)?[0])? }),
        "pf-load" => Ok(RootCommand::PfLoad { iface: iface_arg(rest)? }),
        "pf-unload" => exact::<0>(rest).map(|_| RootCommand::PfUnload),
        "show" => exact::<0>(rest).map(|_| RootCommand::Show),
        other => Err(format!("unknown subcommand: {other}")),
    }
}

/// `args` is everything after the program name: a subcommand, its arguments,
/// and optionally `--wg <name>`, `--anchor <name>` and `--parent-port <n>` anywhere.
pub fn parse(args: &[String]) -> Result<RootRequest, String> {
    let mut args = args.to_vec();
    let wg_name = take_option(&mut args, "--wg")?.unwrap_or_else(|| DEFAULT_WG_NAME.to_string());
    let anchor = take_option(&mut args, "--anchor")?.unwrap_or_else(|| DEFAULT_PF_ANCHOR.to_string());
    let parent_port = match take_option(&mut args, "--parent-port")? {
        Some(text) => text.parse::<u16>().ok().filter(|p| *p > 0).ok_or("bad --parent-port")?,
        None => PARENT_LISTENER_PORT,
    };
    if !is_wg_name(&wg_name) {
        return Err("bad --wg name".into());
    }
    if !is_anchor_name(&anchor) {
        return Err("bad --anchor name (must be com.apple/<name>)".into());
    }
    Ok(RootRequest { command: parse_command(&args, &wg_name)?, wg_name, anchor, parent_port })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::base64_encode;

    fn parse(args: &[String]) -> Result<RootCommand, String> {
        super::parse(args).map(|r| r.command)
    }

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    fn key() -> String {
        base64_encode(&[9u8; 32])
    }

    #[test]
    fn accepts_every_listed_subcommand() {
        let k = key();
        assert_eq!(parse(&args(&["up", "/x/state/wg-metaservice.conf"])).unwrap(), RootCommand::Up { conf: "/x/state/wg-metaservice.conf".into() });
        assert_eq!(parse(&args(&["down"])).unwrap(), RootCommand::Down);
        assert_eq!(
            parse(&args(&["add-peer", &k, "10.77.0.2"])).unwrap(),
            RootCommand::AddPeer { public_key: k.clone(), address: "10.77.0.2".parse().unwrap() }
        );
        assert_eq!(parse(&args(&["remove-peer", &k])).unwrap(), RootCommand::RemovePeer { public_key: k });
        assert_eq!(parse(&args(&["pf-load"])).unwrap(), RootCommand::PfLoad { iface: None });
        assert_eq!(parse(&args(&["pf-load", "utun7"])).unwrap(), RootCommand::PfLoad { iface: Some("utun7".into()) });
        assert_eq!(parse(&args(&["pf-unload"])).unwrap(), RootCommand::PfUnload);
        assert_eq!(parse(&args(&["show"])).unwrap(), RootCommand::Show);
    }

    #[test]
    fn refuses_everything_else() {
        let k = key();
        for bad in [
            vec![],
            vec!["shell"],
            vec!["down", "extra"],
            vec!["show", "-v"],
            vec!["add-peer", k.as_str()],
            vec!["add-peer", "not-a-key", "10.77.0.2"],
            vec!["add-peer", k.as_str(), "10.77.0.2; reboot"],
            vec!["add-peer", k.as_str(), "example.com"],
            vec!["remove-peer", "short"],
            vec!["up"],
            vec!["up", "relative/wg-metaservice.conf"],
            vec!["up", "/x/state/wg-hub.conf"],
            vec!["up", "/etc/passwd"],
            vec!["pf-load", "en0"],
            vec!["pf-load", "utun7", "extra"],
            vec!["pf-unload", "x"],
        ] {
            assert!(parse(&args(&bad)).is_err(), "{bad:?} must be refused");
        }
    }

    #[test]
    fn names_default_and_can_be_overridden() {
        let default = super::parse(&args(&["show"])).unwrap();
        assert_eq!((default.wg_name.as_str(), default.anchor.as_str()), ("wg-metaservice", "com.apple/joinshare"));
        let custom = super::parse(&args(&["show", "--wg", "wg-e2e", "--anchor", "com.apple/joinshare-e2e"])).unwrap();
        assert_eq!((custom.wg_name.as_str(), custom.anchor.as_str()), ("wg-e2e", "com.apple/joinshare-e2e"));
        let port = super::parse(&args(&["pf-load", "--parent-port", "9192"])).unwrap();
        assert_eq!((default.parent_port, port.parent_port), (9102, 9192));
        let up = super::parse(&args(&["--wg", "wg-e2e", "up", "/s/wg-e2e.conf"])).unwrap();
        assert_eq!(up.command, RootCommand::Up { conf: "/s/wg-e2e.conf".into() });
    }

    #[test]
    fn bad_names_are_refused() {
        for bad in [
            vec!["show", "--wg", "../x"],
            vec!["show", "--wg", "-evil"],
            vec!["show", "--wg", "this-name-is-way-too-long"],
            vec!["show", "--wg"],
            vec!["pf-load", "--parent-port", "0"],
            vec!["pf-load", "--parent-port", "99999"],
            vec!["pf-load", "--anchor", "evil"],
            vec!["pf-load", "--anchor", "com.apple/"],
            vec!["pf-load", "--anchor", "com.apple/a/b"],
            vec!["pf-load", "--anchor", "com.apple/a b"],
            vec!["up", "/s/wg-metaservice.conf", "--wg", "wg-e2e"],
        ] {
            assert!(super::parse(&args(&bad)).is_err(), "{bad:?} must be refused");
        }
    }

    #[test]
    fn interface_names() {
        assert!(is_iface_name("utun0"));
        assert!(is_iface_name("utun123"));
        assert!(is_iface_name("wg-meta"));
        assert!(!is_iface_name("utun"));
        assert!(!is_iface_name("utunx"));
        assert!(!is_iface_name("utun1234567"));
        assert!(!is_iface_name("en0"));
        assert!(!is_iface_name("utun1;ls"));
    }
}

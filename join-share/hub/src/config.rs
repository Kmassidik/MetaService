//! Settings from the environment (CONTRACT section 2). `from_lookup` takes a
//! lookup function so tests never touch the process environment.
use crate::constants::{DEFAULT_PF_ANCHOR, DEFAULT_WG_NAME};
use crate::peers::Net;
use crate::root_args::{is_anchor_name, is_wg_name};
use crate::supported::Builds;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::str::FromStr;

#[derive(Clone, Debug)]
pub struct Config {
    pub net: Net,
    pub wg_port: u16,
    pub endpoint: String,
    pub public_bind: SocketAddr,
    pub public_url: String,
    pub admin_bind: SocketAddr,
    pub parent_url: String,
    pub state_dir: PathBuf,
    pub parent_db: PathBuf,
    pub builds: Builds,
    pub root_helper: PathBuf,
    pub rate_limit_per_min: u32,
    pub wg_name: String,
    pub pf_anchor: String,
    pub parent_port: u16,
}

type Lookup<'a> = &'a dyn Fn(&str) -> Option<String>;

fn value(get: Lookup, key: &str) -> Option<String> {
    get(key).map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

fn required(get: Lookup, key: &str) -> Result<String, String> {
    value(get, key).ok_or_else(|| format!("{key} must be set"))
}

fn parsed<T: FromStr>(get: Lookup, key: &str, default: &str) -> Result<T, String> {
    let text = value(get, key).unwrap_or_else(|| default.to_string());
    text.parse().map_err(|_| format!("{key} is not valid: {text}"))
}

const DEFAULT_ROOT_HELPER: &str = "/usr/local/libexec/join-share/join-share-root";

fn valid_endpoint(endpoint: &str) -> bool {
    endpoint.rsplit_once(':').is_some_and(|(host, port)| !host.is_empty() && port.parse::<u16>().is_ok())
}

fn port_of_url(url: &str) -> Option<u16> {
    url.trim_end_matches('/').rsplit_once(':')?.1.parse().ok().filter(|p| *p > 0)
}

fn clean_public_url(url: &str) -> Result<String, String> {
    let url = url.trim_end_matches('/');
    if url.starts_with("https://") || url.starts_with("http://") {
        return Ok(url.to_string());
    }
    Err("JOIN_SHARE_PUBLIC_URL must start with http:// or https://".into())
}

impl Config {
    pub fn from_env() -> Result<Config, String> {
        Self::from_lookup(&|key| std::env::var(key).ok())
    }

    pub fn from_lookup(get: Lookup) -> Result<Config, String> {
        let endpoint = required(get, "JOIN_SHARE_ENDPOINT")?;
        if !valid_endpoint(&endpoint) {
            return Err("JOIN_SHARE_ENDPOINT must be host:port".into());
        }
        let wg_name = value(get, "JOIN_SHARE_WG_NAME").unwrap_or_else(|| DEFAULT_WG_NAME.into());
        let pf_anchor = value(get, "JOIN_SHARE_PF_ANCHOR").unwrap_or_else(|| DEFAULT_PF_ANCHOR.into());
        if !is_wg_name(&wg_name) {
            return Err("JOIN_SHARE_WG_NAME is not a valid interface name".into());
        }
        if !is_anchor_name(&pf_anchor) {
            return Err("JOIN_SHARE_PF_ANCHOR must look like com.apple/<name>".into());
        }
        let parent_url = value(get, "JOIN_SHARE_PARENT_URL").unwrap_or_else(|| "http://10.77.0.1:9102".into());
        let parent_port = port_of_url(&parent_url).ok_or("JOIN_SHARE_PARENT_URL must end in :port")?;
        Ok(Config {
            parent_port,
            wg_name,
            pf_anchor,
            net: Net::parse(&value(get, "JOIN_SHARE_NET").unwrap_or_else(|| "10.77.0.0/24".into()))?,
            wg_port: parsed(get, "JOIN_SHARE_WG_PORT", "51830")?,
            endpoint,
            public_bind: parsed(get, "JOIN_SHARE_PUBLIC_BIND", "127.0.0.1:9110")?,
            public_url: clean_public_url(&required(get, "JOIN_SHARE_PUBLIC_URL")?)?,
            admin_bind: parsed(get, "JOIN_SHARE_ADMIN_BIND", "127.0.0.1:9111")?,
            parent_url,
            state_dir: PathBuf::from(value(get, "JOIN_SHARE_STATE").unwrap_or_else(|| "state".into())),
            parent_db: PathBuf::from(required(get, "JOIN_SHARE_PARENT_DB")?),
            builds: Builds {
                dir: PathBuf::from(required(get, "JOIN_SHARE_BUILDS_DIR")?),
                mac_agent: value(get, "JOIN_SHARE_MAC_AGENT").map(PathBuf::from),
            },
            root_helper: value(get, "JOIN_SHARE_ROOT_HELPER").map_or_else(|| PathBuf::from(DEFAULT_ROOT_HELPER), PathBuf::from),
            rate_limit_per_min: parsed(get, "JOIN_SHARE_RATE_LIMIT", "60")?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn minimal() -> HashMap<&'static str, &'static str> {
        HashMap::from([
            ("JOIN_SHARE_ENDPOINT", "mini.example.com:51830"),
            ("JOIN_SHARE_PUBLIC_URL", "https://join.example.com/"),
            ("JOIN_SHARE_PARENT_DB", "/x/root.sqlite3"),
            ("JOIN_SHARE_BUILDS_DIR", "/x/builds"),
        ])
    }

    fn load(map: &HashMap<&str, &str>) -> Result<Config, String> {
        Config::from_lookup(&|k| map.get(k).map(|v| v.to_string()))
    }

    #[test]
    fn defaults_match_the_contract() {
        let c = load(&minimal()).unwrap();
        assert_eq!(c.net.cidr(), "10.77.0.0/24");
        assert_eq!(c.wg_port, 51830);
        assert_eq!(c.public_bind.to_string(), "127.0.0.1:9110");
        assert_eq!(c.admin_bind.to_string(), "127.0.0.1:9111");
        assert_eq!(c.parent_url, "http://10.77.0.1:9102");
        assert_eq!(c.parent_port, 9102);
        assert_eq!(c.public_url, "https://join.example.com");
        assert_eq!(c.root_helper.to_str(), Some("/usr/local/libexec/join-share/join-share-root"));
        assert!(c.builds.mac_agent.is_none());
        assert_eq!((c.wg_name.as_str(), c.pf_anchor.as_str()), ("wg-metaservice", "com.apple/joinshare"));
    }

    #[test]
    fn must_be_set_rules() {
        for key in ["JOIN_SHARE_ENDPOINT", "JOIN_SHARE_PUBLIC_URL", "JOIN_SHARE_PARENT_DB", "JOIN_SHARE_BUILDS_DIR"] {
            let mut map = minimal();
            map.remove(key);
            let err = load(&map).unwrap_err();
            assert!(err.contains(key), "{err}");
        }
    }

    #[test]
    fn rejects_bad_values() {
        let mut map = minimal();
        map.insert("JOIN_SHARE_ENDPOINT", "no-port");
        assert!(load(&map).is_err());
        let mut map = minimal();
        map.insert("JOIN_SHARE_PUBLIC_URL", "ftp://x");
        assert!(load(&map).is_err());
        let mut map = minimal();
        map.insert("JOIN_SHARE_WG_PORT", "99999");
        assert!(load(&map).is_err());
        let mut map = minimal();
        map.insert("JOIN_SHARE_PF_ANCHOR", "com.example/x");
        assert!(load(&map).is_err());
        let mut map = minimal();
        map.insert("JOIN_SHARE_WG_NAME", "bad name");
        assert!(load(&map).is_err());
    }

    #[test]
    fn overrides_apply() {
        let mut map = minimal();
        map.insert("JOIN_SHARE_NET", "10.88.0.0/24");
        map.insert("JOIN_SHARE_ADMIN_BIND", "127.0.0.1:9999");
        map.insert("JOIN_SHARE_WG_NAME", "wg-e2e");
        map.insert("JOIN_SHARE_PARENT_URL", "http://10.88.0.1:9192");
        map.insert("JOIN_SHARE_PF_ANCHOR", "com.apple/joinshare-e2e");
        let c = load(&map).unwrap();
        assert_eq!(c.net.cidr(), "10.88.0.0/24");
        assert_eq!(c.admin_bind.port(), 9999);
        assert_eq!(c.parent_port, 9192);
        assert_eq!((c.wg_name.as_str(), c.pf_anchor.as_str()), ("wg-e2e", "com.apple/joinshare-e2e"));
    }
}

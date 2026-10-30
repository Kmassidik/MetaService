//! Fixed numbers from CONTRACT.md that are not settings.

/// Parent's agent listener a far PC reports to (reached at the hub address).
pub const PARENT_LISTENER_PORT: u16 = 9102;
/// Helper port on a far PC, bound to its WireGuard address only.
pub const HELPER_PORT: u16 = 9101;
/// WireGuard persistent keepalive written for far PCs.
pub const KEEPALIVE_SECS: u32 = 25;
/// Link, pending machine and enrollment lifetime.
pub const LIFETIME_SECS: i64 = 900;
/// Wrong approval codes allowed before the pending machine is refused.
pub const CODE_TRIES: i64 = 5;
/// Public and admin request bodies are tiny JSON.
pub const BODY_LIMIT_BYTES: usize = 16 * 1024;
/// Default wg-quick config/interface name (JOIN_SHARE_WG_NAME); wg-quick derives it from the config file name.
pub const DEFAULT_WG_NAME: &str = "wg-metaservice";
/// pf anchor the hub rules live in.
/// Under com.apple/ because Apple's main ruleset already scans "com.apple/*";
/// the main ruleset and /etc/pf.conf are never touched.
pub const DEFAULT_PF_ANCHOR: &str = "com.apple/joinshare";
/// Every anchor name must live under this prefix (JOIN_SHARE_PF_ANCHOR).
pub const PF_ANCHOR_PREFIX: &str = "com.apple/";
/// Marker prefix (in the root-only run folder): we turned pf on, so unload turns it off again.
pub const PF_MARKER_PREFIX: &str = "pf-enabled-by-";
/// Folder only root can write; holds the validated copy of the hub config.
pub const ROOT_RUN_DIR: &str = "/var/run/join-share";
/// Last segment of the download route.
pub const HELPER_FILE: &str = "metaservice-agent";

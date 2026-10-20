//! Reads a version out of what a program prints. Anything that is not plainly a version gives None: a version is never guessed.
use regex::Regex;
use std::sync::OnceLock;

fn pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"\b(\d{1,4}(?:\.\d{1,4}){1,2})\b").expect("the version pattern is valid"))
}

/// The version in the output of `incus version`. The server's is preferred; "unreachable" or junk gives None.
/// Example: "Client version: 6.0.3\nServer version: 6.0.3" gives "6.0.3".
pub fn parse_incus_version(output: &str) -> Option<String> {
    let line = |prefix: &str| output.lines().find_map(|l| l.trim().strip_prefix(prefix).map(str::to_string));
    let chosen = line("Server version:").filter(|text| pattern().is_match(text)).or_else(|| line("Client version:"))?;
    pattern().captures(&chosen).map(|found| found[1].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_servers_version_wins_and_the_clients_is_the_fallback() {
        assert_eq!(parse_incus_version("Client version: 6.0.3\nServer version: 6.0.3\n").as_deref(), Some("6.0.3"));
        assert_eq!(parse_incus_version("Client version: 6.0.0\nServer version: 6.5\n").as_deref(), Some("6.5"));
        assert_eq!(parse_incus_version("Client version: 6.0.3\nServer version: unreachable\n").as_deref(), Some("6.0.3"));
    }

    #[test]
    fn anything_else_is_none() {
        for junk in ["", "nothing here", "Server version: unreachable", "Client version: v6", "\0\0", &"9".repeat(5000)] {
            assert_eq!(parse_incus_version(junk), None, "{junk:.20}");
        }
    }

    #[test]
    fn hostile_output_is_cut_down_to_the_digits() {
        assert_eq!(parse_incus_version("Server version: 6.0.3'; DROP TABLE x;-- $(reboot)").as_deref(), Some("6.0.3"));
        assert_eq!(parse_incus_version("Server version: <script>1.2</script>").as_deref(), Some("1.2"));
    }
}

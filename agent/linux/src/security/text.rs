//! Text that came from a log is written by whoever knocked on the door. Everything that reaches the parent goes through here first.

pub const MAX_USER_CHARS: usize = 64;
pub const MAX_DETAIL_CHARS: usize = 160;
const MAX_HOSTNAME_BYTES: usize = 253;

/// Invisible characters that reorder or hide text (zero-width, bidi overrides, byte order mark).
fn is_invisible(c: char) -> bool {
    matches!(c, '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{FEFF}')
}

/// The text without control or invisible characters, cut to `max` characters. Empty after cleaning gives None.
pub fn clean(text: &str, max: usize) -> Option<String> {
    let cleaned: String = text
        .chars()
        .filter(|c| !c.is_control() && !is_invisible(*c))
        .take(max)
        .collect();
    let trimmed = cleaned.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

pub fn user(text: &str) -> Option<String> {
    clean(text, MAX_USER_CHARS)
}

pub fn detail(text: &str) -> String {
    clean(text, MAX_DETAIL_CHARS).unwrap_or_default()
}

/// An IPv4 or IPv6 address in its plain written form, or a plausible hostname; anything else is None.
pub fn address(text: &str) -> Option<String> {
    if let Ok(ip) = text.parse::<std::net::IpAddr>() {
        return Some(ip.to_string());
    }
    plausible_hostname(text).then(|| text.to_ascii_lowercase())
}

fn plausible_hostname(text: &str) -> bool {
    let allowed = text
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_');
    let has_letter = text.chars().any(|c| c.is_ascii_alphabetic());
    let well_placed =
        !text.starts_with(['.', '-']) && !text.ends_with(['-']) && !text.contains("..");
    !text.is_empty() && text.len() <= MAX_HOSTNAME_BYTES && allowed && has_letter && well_placed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn control_and_invisible_characters_go_and_length_is_cut() {
        assert_eq!(
            user("ro\u{0}ot\n\u{1b}[31m\u{202E}x").as_deref(),
            Some("root[31mx")
        );
        assert_eq!(
            user(&"a".repeat(500)).unwrap().chars().count(),
            MAX_USER_CHARS
        );
        assert_eq!(detail(&"é".repeat(500)).chars().count(), MAX_DETAIL_CHARS);
        assert_eq!(user("\u{0}\n "), None);
    }

    #[test]
    fn addresses_are_ips_or_plausible_hostnames_and_nothing_else() {
        assert_eq!(address("203.0.113.9").as_deref(), Some("203.0.113.9"));
        assert_eq!(address("2001:DB8::1").as_deref(), Some("2001:db8::1"));
        assert_eq!(
            address("Scanner.Example.com").as_deref(),
            Some("scanner.example.com")
        );
        for bad in [
            "",
            "999.1.1.1",
            "1.2.3",
            "a b",
            "<script>",
            "-x.com",
            "a..b",
            "x;rm -rf /",
            "12345",
            &"a".repeat(300),
        ] {
            assert_eq!(address(bad), None, "{bad:?}");
        }
    }
}

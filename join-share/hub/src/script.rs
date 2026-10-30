//! The join script: `join-share/script/join.sh` embedded at build time, with
//! the four placeholders filled in. Callers pass only validated values (hex
//! link id, os/cpu words, the configured public URL).
const TEMPLATE: &str = include_str!("../../script/join.sh");

pub fn render(template: &str, link: &str, public_url: &str, os: &str, cpu: &str) -> String {
    template
        .replace("@LINK@", link)
        .replace("@PUBLIC_URL@", public_url)
        .replace("@OS@", os)
        .replace("@CPU@", cpu)
}

pub fn join_script(link: &str, public_url: &str, os: &str, cpu: &str) -> String {
    render(TEMPLATE, link, public_url, os, cpu)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replaces_every_placeholder() {
        let out = render("a=@LINK@ b=@PUBLIC_URL@ c=@OS@ d=@CPU@ again=@LINK@", "L", "https://x", "mac", "arm64");
        assert_eq!(out, "a=L b=https://x c=mac d=arm64 again=L");
    }

    #[test]
    fn embedded_script_has_no_placeholder_left() {
        let out = join_script("abc", "https://x", "linux", "x86_64");
        for placeholder in ["@LINK@", "@PUBLIC_URL@", "@OS@", "@CPU@"] {
            assert!(!out.contains(placeholder), "{placeholder} left");
        }
    }
}

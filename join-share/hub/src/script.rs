//! The join script: `join-share/script/join.sh` embedded at build time, with
//! the four placeholders filled in. Callers pass only validated values (hex
//! link id, os/cpu words, the configured public URL).
const SHELL_TEMPLATE: &str = include_str!("../../script/join.sh");
const POWERSHELL_TEMPLATE: &str = include_str!("../../script/join.ps1");

/// The script for the system: shell for Mac and Linux, PowerShell for Windows.
pub fn template_for(os: &str) -> &'static str {
    if os == "windows" { POWERSHELL_TEMPLATE } else { SHELL_TEMPLATE }
}

pub fn render(template: &str, link: &str, public_url: &str, os: &str, cpu: &str) -> String {
    template
        .replace("@LINK@", link)
        .replace("@PUBLIC_URL@", public_url)
        .replace("@OS@", os)
        .replace("@CPU@", cpu)
}

pub fn join_script(link: &str, public_url: &str, os: &str, cpu: &str) -> String {
    render(template_for(os), link, public_url, os, cpu)
}

/// The content type the script is served as: PowerShell for Windows, shell for the rest.
pub fn content_type_for(os: &str) -> &'static str {
    if os == "windows" { "text/plain; charset=utf-8" } else { "text/x-shellscript" }
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
        for os in ["linux", "windows"] {
            let out = join_script("abc", "https://x", os, "x86_64");
            for placeholder in ["@LINK@", "@PUBLIC_URL@", "@OS@", "@CPU@"] {
                assert!(!out.contains(placeholder), "{os}: {placeholder} left");
            }
        }
    }

    #[test]
    fn windows_gets_the_powershell_script() {
        let out = join_script("abc", "https://x", "windows", "x86_64");
        assert!(out.contains("$env:USERPROFILE"), "the windows script is powershell");
        assert!(out.contains(" irm "));
        let linux = join_script("abc", "https://x", "linux", "x86_64");
        assert!(linux.contains("#!/bin/sh"));
    }
}

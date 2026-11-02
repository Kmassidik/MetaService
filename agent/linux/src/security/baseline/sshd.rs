//! Does SSH accept passwords? Resolved the way sshd reads its configuration: files in order, `Include` expanded where it stands, the first
//! `PasswordAuthentication` wins, `Match` blocks (conditional) are skipped to the end of their file, and nothing said means yes.
//! `KbdInteractiveAuthentication` can also let a password in through PAM; this check only follows PasswordAuthentication, which decides the plain case.
use crate::security::env::Environment;
use std::io;
use std::path::{Path, PathBuf};

const MAIN_CONFIG: &str = "/etc/ssh/sshd_config";
const CONFIG_DIRECTORY: &str = "/etc/ssh";
const KEYWORD: &str = "passwordauthentication";
const DEFAULT_ACCEPTS_PASSWORDS: bool = true;
/// sshd allows 16 nested includes; a config deeper than this is not one we trust ourselves to read.
const MAX_INCLUDE_DEPTH: usize = 8;

/// Some(true): passwords are accepted. None: a file we needed could not be read.
pub fn password_login(env: &Environment) -> Option<bool> {
    let mut found = None;
    let read_all = walk(env, &env.at(MAIN_CONFIG), 0, &mut found);
    read_all
        .ok()
        .map(|()| found.unwrap_or(DEFAULT_ACCEPTS_PASSWORDS))
}

/// Reads one file in order. `found` takes the first PasswordAuthentication value seen anywhere.
fn walk(env: &Environment, path: &Path, depth: usize, found: &mut Option<bool>) -> io::Result<()> {
    if depth > MAX_INCLUDE_DEPTH {
        return Err(io::Error::other("sshd_config includes are nested too deep"));
    }
    let text = std::fs::read_to_string(path)?;
    for line in text.lines() {
        let Some((keyword, value)) = split(line) else {
            continue;
        };
        match keyword.as_str() {
            "match" => return Ok(()),
            "include" => include(env, &value, depth, found)?,
            KEYWORD => *found = found.or_else(|| yes_or_no(&value)),
            _ => {}
        }
        if found.is_some() {
            return Ok(());
        }
    }
    Ok(())
}

fn include(
    env: &Environment,
    patterns: &str,
    depth: usize,
    found: &mut Option<bool>,
) -> io::Result<()> {
    for pattern in patterns.split_whitespace() {
        for file in expand(env, pattern)? {
            // First value wins in sshd, so a file after the decision (even an unreadable one) cannot change the answer.
            if found.is_some() {
                return Ok(());
            }
            walk(env, &file, depth + 1, found)?;
        }
    }
    Ok(())
}

/// A comment-free line as a lowercase keyword and its value. `Keyword value` and `Keyword=value` both work.
fn split(line: &str) -> Option<(String, String)> {
    let content = line.split('#').next().unwrap_or("").trim();
    let at = content.find(|c: char| c.is_whitespace() || c == '=')?;
    let value = content[at..]
        .trim_start_matches(|c: char| c.is_whitespace() || c == '=')
        .trim();
    Some((content[..at].to_ascii_lowercase(), value.to_string()))
}

fn yes_or_no(value: &str) -> Option<bool> {
    match value.trim_matches('"').to_ascii_lowercase().as_str() {
        "yes" => Some(true),
        "no" => Some(false),
        _ => None,
    }
}

/// The files an Include pattern names, in the order sshd reads them (sorted). Only the last path part may have `*` or `?`.
fn expand(env: &Environment, pattern: &str) -> io::Result<Vec<PathBuf>> {
    let absolute = if pattern.starts_with('/') {
        pattern.to_string()
    } else {
        format!("{CONFIG_DIRECTORY}/{pattern}")
    };
    let (directory, name) = absolute.rsplit_once('/').unwrap_or(("", &absolute));
    if !name.contains(['*', '?']) {
        return Ok(vec![env.at(&absolute)]);
    }
    let entries = match std::fs::read_dir(env.at(directory)) {
        Ok(entries) => entries,
        Err(cause) if cause.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(cause) => return Err(cause),
    };
    let mut files = Vec::new();
    for entry in entries {
        let entry = entry?;
        let matches = entry
            .file_name()
            .to_str()
            .is_some_and(|file| glob_matches(name, file));
        if matches && entry.path().is_file() {
            files.push(entry.path());
        }
    }
    files.sort();
    Ok(files)
}

/// `*` any run of characters, `?` any one character.
fn glob_matches(pattern: &str, name: &str) -> bool {
    fn go(pattern: &[char], name: &[char]) -> bool {
        match (pattern.first(), name.first()) {
            (None, None) => true,
            (Some('*'), _) => {
                go(&pattern[1..], name) || (!name.is_empty() && go(pattern, &name[1..]))
            }
            (Some('?'), Some(_)) => go(&pattern[1..], &name[1..]),
            (Some(p), Some(n)) if p == n => go(&pattern[1..], &name[1..]),
            _ => false,
        }
    }
    go(
        &pattern.chars().collect::<Vec<_>>(),
        &name.chars().collect::<Vec<_>>(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn machine(files: &[(&str, &str)]) -> (PathBuf, Environment) {
        let root = std::env::temp_dir().join(format!("ms-sshd-{}", rand::random::<u64>()));
        for (path, text) in files {
            let target = root.join(path.trim_start_matches('/'));
            std::fs::create_dir_all(target.parent().unwrap()).unwrap();
            std::fs::write(target, text).unwrap();
        }
        let env = Environment {
            root: root.clone(),
            home: root.clone(),
            user: "u".into(),
            auth_log: root.join("a"),
            fail2ban_log: root.join("f"),
        };
        (root, env)
    }

    fn answer(files: &[(&str, &str)]) -> Option<bool> {
        let (root, env) = machine(files);
        let result = password_login(&env);
        let _ = std::fs::remove_dir_all(root);
        result
    }

    const INCLUDE: &str = "Include /etc/ssh/sshd_config.d/*.conf\n";

    #[test]
    fn nothing_said_means_yes_and_a_plain_no_means_no() {
        assert_eq!(
            answer(&[("/etc/ssh/sshd_config", "# nothing\nPort 22\n")]),
            Some(true)
        );
        assert_eq!(
            answer(&[("/etc/ssh/sshd_config", "PasswordAuthentication no\n")]),
            Some(false)
        );
        assert_eq!(
            answer(&[(
                "/etc/ssh/sshd_config",
                "  passwordauthentication=NO # comment\n"
            )]),
            Some(false)
        );
        assert_eq!(
            answer(&[("/etc/ssh/sshd_config", "#PasswordAuthentication no\n")]),
            Some(true),
            "a comment says nothing"
        );
    }

    #[test]
    fn the_first_occurrence_wins() {
        assert_eq!(
            answer(&[(
                "/etc/ssh/sshd_config",
                "PasswordAuthentication yes\nPasswordAuthentication no\n"
            )]),
            Some(true)
        );
        assert_eq!(
            answer(&[(
                "/etc/ssh/sshd_config",
                "PasswordAuthentication no\nPasswordAuthentication yes\n"
            )]),
            Some(false)
        );
    }

    #[test]
    fn includes_are_read_where_they_stand_in_sorted_order() {
        let early = format!("{INCLUDE}PasswordAuthentication yes\n");
        let files = [
            ("/etc/ssh/sshd_config", early.as_str()),
            (
                "/etc/ssh/sshd_config.d/50-cloud.conf",
                "PasswordAuthentication no\n",
            ),
            (
                "/etc/ssh/sshd_config.d/60-x.conf",
                "PasswordAuthentication yes\n",
            ),
        ];
        assert_eq!(
            answer(&files),
            Some(false),
            "the include comes before the main file's own line"
        );
        let late = format!("PasswordAuthentication yes\n{INCLUDE}");
        assert_eq!(
            answer(&[
                ("/etc/ssh/sshd_config", late.as_str()),
                (
                    "/etc/ssh/sshd_config.d/50.conf",
                    "PasswordAuthentication no\n"
                )
            ]),
            Some(true)
        );
        let sorted = [
            ("/etc/ssh/sshd_config", INCLUDE),
            (
                "/etc/ssh/sshd_config.d/60.conf",
                "PasswordAuthentication yes\n",
            ),
            (
                "/etc/ssh/sshd_config.d/10.conf",
                "PasswordAuthentication no\n",
            ),
        ];
        assert_eq!(answer(&sorted), Some(false));
    }

    #[test]
    fn a_directory_that_is_not_included_is_not_read() {
        assert_eq!(
            answer(&[
                ("/etc/ssh/sshd_config", "Port 22\n"),
                (
                    "/etc/ssh/sshd_config.d/a.conf",
                    "PasswordAuthentication no\n"
                )
            ]),
            Some(true)
        );
    }

    #[test]
    fn match_blocks_are_ignored_to_the_end_of_their_file() {
        let text =
            "PasswordAuthentication no\nMatch User bob\n  PasswordAuthentication yes\n".to_string();
        assert_eq!(
            answer(&[("/etc/ssh/sshd_config", text.as_str())]),
            Some(false)
        );
        let hidden = "Match Address 10.0.0.0/8\n  PasswordAuthentication no\n";
        let main = format!("{INCLUDE}PasswordAuthentication yes\n");
        let files = [
            ("/etc/ssh/sshd_config", main.as_str()),
            ("/etc/ssh/sshd_config.d/a.conf", hidden),
        ];
        assert_eq!(
            answer(&files),
            Some(true),
            "the Match in an include does not reach the main file"
        );
    }

    #[test]
    fn an_unreadable_or_missing_main_file_is_unknown_and_a_missing_include_folder_is_fine() {
        assert_eq!(answer(&[("/etc/hostname", "x")]), None);
        assert_eq!(answer(&[("/etc/ssh/sshd_config", INCLUDE)]), Some(true));
    }

    /// A path that is a directory cannot be read as a file, on any user including root.
    const UNREADABLE: (&str, &str) = ("/etc/ssh/bad.conf/inside", "x");
    const GOOD_NO: (&str, &str) = ("/etc/ssh/good.conf", "PasswordAuthentication no\n");
    const GOOD_YES: (&str, &str) = ("/etc/ssh/good.conf", "PasswordAuthentication yes\n");

    #[test]
    fn an_unreadable_file_after_the_decision_does_not_matter() {
        let main = "Include /etc/ssh/good.conf\nInclude /etc/ssh/bad.conf\n";
        let files = [("/etc/ssh/sshd_config", main), GOOD_NO, UNREADABLE];
        assert_eq!(answer(&files), Some(false));
        let files = [("/etc/ssh/sshd_config", main), GOOD_YES, UNREADABLE];
        assert_eq!(answer(&files), Some(true));
        let own = "PasswordAuthentication no\nInclude /etc/ssh/bad.conf\n";
        assert_eq!(
            answer(&[("/etc/ssh/sshd_config", own), UNREADABLE]),
            Some(false)
        );
    }

    #[test]
    fn an_unreadable_file_before_any_decision_is_unknown() {
        let main = "Include /etc/ssh/bad.conf\nInclude /etc/ssh/good.conf\n";
        assert_eq!(
            answer(&[("/etc/ssh/sshd_config", main), GOOD_NO, UNREADABLE]),
            None
        );
    }

    #[test]
    fn the_wildcards() {
        assert!(
            glob_matches("*.conf", "50-cloud.conf")
                && glob_matches("a?c", "abc")
                && !glob_matches("*.conf", "x.conf.bak")
                && !glob_matches("a?c", "ac")
        );
    }
}

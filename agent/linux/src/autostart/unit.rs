//! The pure part of `autostart`: the systemd user unit as text, and the helper's command line as `start.sh` wrote it. No file is read or written here.
use std::path::Path;

pub const UNIT_NAME: &str = "metaservice-agent.service";
pub const PROGRAM: &str = "metaservice-agent";
/// The line of start.sh that starts the helper: `nohup ./bin/metaservice-agent <arguments> >> logs/agent.log 2>&1 &`.
const START_LINE_PREFIX: &str = "nohup ./bin/metaservice-agent ";
const REDIRECT: &str = ">>";
/// The helper's own pid file, relative to the box. start.sh writes it; so does the unit, so `stop.sh` and the update find a helper that systemd started.
pub const PID_FILE: &str = "state/agent.pid";
const RESTART_SECONDS: u32 = 10;
/// Characters that need no quoting in a unit file. A box folder with anything else is refused rather than escaped.
const PLAIN: &str = "_./:=@+,-";

/// The words after `nohup ./bin/metaservice-agent` in start.sh, as the program receives them (the first is `run`).
pub fn start_arguments(start_script: &str) -> Result<Vec<String>, String> {
    let line = start_script.lines().map(str::trim).find(|line| line.starts_with(START_LINE_PREFIX))
        .ok_or("start.sh has no line that starts the helper, so there is nothing to repeat at boot")?;
    let words = shell_words(&line[START_LINE_PREFIX.len()..])?;
    let arguments: Vec<String> = words.into_iter().take_while(|word| word != REDIRECT).collect();
    match arguments.first().map(String::as_str) {
        Some("run") => Ok(arguments),
        _ => Err("the start line in start.sh does not begin with `run`".into()),
    }
}

/// Splits one shell line into words: single quotes, double quotes and backslashes as `sh` reads them. Nothing is expanded.
fn shell_words(line: &str) -> Result<Vec<String>, String> {
    let mut words = Vec::new();
    let mut current = String::new();
    let mut started = false;
    let mut quote: Option<char> = None;
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (Some(q), c) if c == q => quote = None,
            (Some('"'), '\\') => current.push(chars.next().ok_or("start.sh ends inside a backslash")?),
            (Some(_), c) => current.push(c),
            (None, '\'' | '"') => { quote = Some(c); started = true; }
            (None, '\\') => { current.push(chars.next().ok_or("start.sh ends inside a backslash")?); started = true; }
            (None, c) if c.is_whitespace() => {
                if started { words.push(std::mem::take(&mut current)); started = false; }
            }
            (None, c) => { current.push(c); started = true; }
        }
    }
    if quote.is_some() {
        return Err("start.sh has a quote that is never closed".into());
    }
    if started { words.push(current); }
    Ok(words)
}

/// A word as a unit file reads it: bare when plain, otherwise in double quotes with `%` and `$` doubled so systemd does not expand them.
fn unit_word(word: &str) -> Result<String, String> {
    if word.chars().any(char::is_control) {
        return Err("an argument of the helper has a control character, which a service file cannot carry".into());
    }
    if !word.is_empty() && word.chars().all(is_plain) {
        return Ok(word.to_string());
    }
    let escaped: String = word.chars().map(|c| match c {
        '"' => "\\\"".to_string(),
        '\\' => "\\\\".to_string(),
        '%' => "%%".to_string(),
        '$' => "$$".to_string(),
        other => other.to_string(),
    }).collect();
    Ok(format!("\"{escaped}\""))
}

fn is_plain(c: char) -> bool { c.is_ascii_alphanumeric() || PLAIN.contains(c) }

/// The box folder must be a path a unit file and a shell line carry as they are.
pub fn check_box(box_dir: &Path) -> Result<&str, String> {
    box_dir.to_str().filter(|text| text.starts_with('/') && text.chars().all(is_plain))
        .ok_or_else(|| "the MetaService folder must be an absolute path with letters, digits and . _ / - only; this one is not".to_string())
}

/// The user unit: the same program with the same arguments as start.sh, from the box, restarted when it fails (a clean stop by `stop.sh` stays stopped).
pub fn unit_text(box_dir: &Path, arguments: &[String]) -> Result<String, String> {
    let folder = check_box(box_dir)?;
    let words = arguments.iter().map(|word| unit_word(word)).collect::<Result<Vec<_>, _>>()?.join(" ");
    Ok(format!(
        "[Unit]\nDescription=MetaService helper ({folder})\nAfter=network-online.target\n\n\
         [Service]\nType=simple\nWorkingDirectory={folder}\nExecStart={folder}/bin/{PROGRAM} {words}\n\
         ExecStartPost=-/bin/sh -c 'echo ${{MAINPID}} > {folder}/{PID_FILE}'\n\
         Restart=on-failure\nRestartSec={RESTART_SECONDS}\n\n[Install]\nWantedBy=default.target\n"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    const START: &str = "#!/bin/sh\ncd \"$(dirname \"$0\")\" || exit 1\nnohup ./bin/metaservice-agent run --state-dir state --engine incus --port 9101 --bind 127.0.0.1 --chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5 >> logs/agent.log 2>&1 &\necho $! > state/agent.pid\n";

    fn strings(items: &[&str]) -> Vec<String> { items.iter().map(|s| s.to_string()).collect() }

    #[test]
    fn reads_the_arguments_of_the_start_line() {
        let arguments = start_arguments(START).unwrap();
        assert_eq!(arguments, strings(&["run", "--state-dir", "state", "--engine", "incus", "--port", "9101", "--bind", "127.0.0.1", "--chat-port", "9200", "--chat-bind", "127.0.0.1", "--heartbeat-seconds", "5"]));
    }

    #[test]
    fn reads_quoted_words_like_sh() {
        let script = "nohup ./bin/metaservice-agent run --state-dir 'my state' --name \"a b\" x\\ y >> logs/agent.log 2>&1 &\n";
        assert_eq!(start_arguments(script).unwrap(), strings(&["run", "--state-dir", "my state", "--name", "a b", "x y"]));
    }

    #[test]
    fn refuses_a_script_without_a_start_line_or_with_a_broken_one() {
        assert!(start_arguments("#!/bin/sh\necho hi\n").is_err());
        assert!(start_arguments("nohup ./bin/metaservice-agent enroll --x y >> a 2>&1 &\n").is_err());
        assert!(start_arguments("nohup ./bin/metaservice-agent run 'open >> a\n").is_err());
    }

    #[test]
    fn the_unit_text_is_exact() {
        let arguments = start_arguments(START).unwrap();
        let text = unit_text(Path::new("/home/kurnia/metaservice-box"), &arguments).unwrap();
        let expected = "[Unit]\nDescription=MetaService helper (/home/kurnia/metaservice-box)\nAfter=network-online.target\n\n\
            [Service]\nType=simple\nWorkingDirectory=/home/kurnia/metaservice-box\n\
            ExecStart=/home/kurnia/metaservice-box/bin/metaservice-agent run --state-dir state --engine incus --port 9101 --bind 127.0.0.1 --chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5\n\
            ExecStartPost=-/bin/sh -c 'echo ${MAINPID} > /home/kurnia/metaservice-box/state/agent.pid'\n\
            Restart=on-failure\nRestartSec=10\n\n[Install]\nWantedBy=default.target\n";
        assert_eq!(text, expected);
    }

    #[test]
    fn odd_arguments_are_quoted_and_percent_and_dollar_doubled() {
        let text = unit_text(Path::new("/b"), &strings(&["run", "--name", "a b%c$d\"e"])).unwrap();
        assert!(text.contains("run --name \"a b%%c$$d\\\"e\"\n"), "{text}");
    }

    #[test]
    fn a_box_a_unit_file_cannot_carry_is_refused() {
        for bad in ["relative/box", "/home/a b/box", "/home/a'b", "/home/a%b", "/home/a\nb"] {
            assert!(unit_text(Path::new(bad), &strings(&["run"])).is_err(), "{bad}");
        }
        assert!(unit_text(Path::new("/b"), &strings(&["run", "bad\u{7}"])).is_err());
    }

    #[test]
    fn the_security_check_reads_the_unit_as_a_helper_unit() {
        let text = unit_text(Path::new("/b"), &strings(&["run"])).unwrap();
        assert!(text.lines().any(|line| line.starts_with("ExecStart") && line.contains(PROGRAM)));
    }
}

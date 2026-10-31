//! The fallback when `auth.log` cannot be read: the journal of the SSH service, asked as the helper's own user. A user outside the `systemd-journal`
//! group sees nothing, and then this answers empty. The cursor is the second of the last line read, so a second's late lines can be missed (never repeated).
use super::commands::Commands;
use super::cursor::Position;
use super::reader::{Line, Outcome, Parse};
use std::time::Duration;

const JOURNALCTL: &str = "journalctl";
const TIMEOUT: Duration = Duration::from_secs(15);
const SINCE_FORMAT_FROM: usize = 0;
const SINCE_FORMAT_TO: usize = 19;

/// Lines at or after `since` (Unix seconds). It stops after `max_items` events, but never in the middle of a second.
pub fn read<T>(
    commands: &dyn Commands,
    since: i64,
    max_items: usize,
    parse: Parse<'_, T>,
) -> Result<Outcome<T>, String> {
    let moment = super::group::iso(since).replace('T', " ");
    let since_text = moment
        .get(SINCE_FORMAT_FROM..SINCE_FORMAT_TO)
        .ok_or("bad time")?;
    let arguments = [
        "-u",
        "ssh",
        "-u",
        "sshd",
        "--no-pager",
        "-o",
        "short-iso",
        "--utc",
        "--since",
        since_text,
    ];
    let output = commands.run(JOURNALCTL, &arguments, TIMEOUT)?;
    let mut outcome = Outcome {
        position: Position::Journal(since - 1),
        reset: false,
        items: Vec::new(),
    };
    let mut last_second = since - 1;
    for text in output.lines() {
        let Some(Line { epoch, item }) = parse(text) else {
            continue;
        };
        if epoch < since {
            continue;
        }
        if outcome.items.len() >= max_items && epoch != last_second {
            break;
        }
        last_second = last_second.max(epoch);
        outcome.items.extend(item);
    }
    outcome.position = Position::Journal(last_second);
    Ok(outcome)
}

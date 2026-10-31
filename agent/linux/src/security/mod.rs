//! The login log and baseline settings of this machine, served as `GET /v1/security/events` (contract/openapi.yaml).
//!
//! Everything is read as the helper's own user: no root, no sudo. The logs are `auth.log` (and the file it rotated to) and `fail2ban.log`; when
//! `auth.log` cannot be read, the SSH journal is tried instead. A cursor (see cursor.rs) lets the parent ask only for what is new.
//! `limit` counts the log lines that became events, before repeated failures from one user and address are grouped into one event with a `count`.
//! Tries are counted by connection inside a response, so one `Failed password` plus its `Connection closed ... [preauth]` is one try; a connection
//! whose lines fall in two responses can count once in each.
mod bantime;
mod baseline;
mod clock;
mod commands;
mod cursor;
mod env;
mod group;
mod journal;
mod model;
mod parse;
mod query;
mod reader;
#[cfg(test)]
mod route_tests;
#[cfg(test)]
mod tests;
mod text;

use crate::http::{error, App};
use axum::extract::{RawQuery, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use baseline::BaselineReader;
use clock::Zone;
use commands::{Commands, SystemCommands};
use cursor::{Cursor, Position};
use group::Seen;
use reader::{Line, Outcome, Source, Unavailable};
use std::collections::HashSet;
use std::io;
use std::sync::{Arc, Mutex};

pub use env::Environment;
pub use model::Answer;

/// The first read keeps this much history.
const WINDOW_SECONDS: i64 = 7 * 24 * 3600;
/// A window for a dump that wants every line there is.
const EVERYTHING_SECONDS: i64 = 200 * 365 * 24 * 3600;

pub struct Security {
    env: Environment,
    commands: Arc<dyn Commands>,
    now: fn() -> i64,
    zone: Zone,
    window: i64,
    baseline: BaselineReader,
    /// Read problems already written to the helper's log, so a poll every minute does not repeat them.
    reported: Mutex<HashSet<String>>,
}

fn system_now() -> i64 {
    crate::sandbox::time::now() as i64
}

impl Security {
    pub fn system() -> Security {
        Security::new(
            Environment::system(),
            Arc::new(SystemCommands),
            system_now,
            clock::system_zone,
        )
    }

    pub fn new(
        env: Environment,
        commands: Arc<dyn Commands>,
        now: fn() -> i64,
        zone: Zone,
    ) -> Security {
        Security {
            env,
            commands,
            now,
            zone,
            window: WINDOW_SECONDS,
            baseline: BaselineReader::new(),
            reported: Mutex::new(HashSet::new()),
        }
    }

    /// What happened since `after` (a cursor this function gave before), at most `limit` lines' worth, and the baseline.
    pub fn events(&self, after: Option<&str>, limit: usize) -> Answer {
        let (cursor, mut reset) = match after.filter(|text| !text.is_empty()).map(Cursor::decode) {
            None => (Cursor::start(), false),
            Some(Some(cursor)) => (cursor, false),
            Some(None) => (Cursor::start(), true),
        };
        let now = (self.now)();
        let cutoff = now - self.window;
        let parse_line = |text: &str| self.parse_line(text, now);
        let auth = self.read_auth(cursor.auth, limit, cutoff, &parse_line);
        let fail2ban = self.read_fail2ban(
            cursor.fail2ban,
            limit.saturating_sub(auth.items.len()),
            cutoff,
            &parse_line,
        );
        reset |= auth.reset || fail2ban.reset;
        let next = Cursor {
            auth: auth.position,
            fail2ban: fail2ban.position,
        };
        let seen: Vec<Seen> = auth.items.into_iter().chain(fail2ban.items).collect();
        Answer {
            cursor: next.encode(),
            reset,
            events: group::events(&seen, bantime::seconds(&self.env)),
            baseline: self.baseline.current(&self.env, self.commands.as_ref()),
        }
    }

    fn parse_line(&self, text: &str, now: i64) -> Option<Line<Seen>> {
        let stamped = clock::stamp(text.trim_end(), now, self.zone)?;
        Some(Line {
            epoch: stamped.epoch,
            item: parse::parse(stamped.rest).map(|parsed| Seen {
                epoch: stamped.epoch,
                parsed,
            }),
        })
    }

    fn read_auth(
        &self,
        from: Position,
        limit: usize,
        cutoff: i64,
        parse_line: reader::Parse<'_, Seen>,
    ) -> Outcome<Seen> {
        let source = Source {
            current: self.env.auth_log.clone(),
            rotated: env::rotated(&self.env.auth_log),
        };
        match reader::read(&source, from, limit, cutoff, parse_line) {
            Ok(outcome) => outcome,
            Err(Unavailable::Missing) => self.journal_instead(from, limit, cutoff, parse_line),
            Err(Unavailable::Io(cause)) if cause.kind() == io::ErrorKind::PermissionDenied => {
                self.journal_instead(from, limit, cutoff, parse_line)
            }
            Err(Unavailable::Io(cause)) => self.unreadable(&source.current, &cause, from),
        }
    }

    /// Moving over to the journal (or back) cannot continue the old position, so it says so.
    fn journal_instead(
        &self,
        from: Position,
        limit: usize,
        cutoff: i64,
        parse_line: reader::Parse<'_, Seen>,
    ) -> Outcome<Seen> {
        let since = match from {
            Position::Journal(second) => second + 1,
            _ => cutoff,
        };
        match journal::read(self.commands.as_ref(), since, limit, parse_line) {
            Ok(mut outcome) => {
                outcome.reset = matches!(from, Position::File(_));
                outcome
            }
            Err(message) => {
                self.report("journal", &message);
                Outcome {
                    position: from,
                    reset: false,
                    items: Vec::new(),
                }
            }
        }
    }

    fn read_fail2ban(
        &self,
        from: Position,
        limit: usize,
        cutoff: i64,
        parse_line: reader::Parse<'_, Seen>,
    ) -> Outcome<Seen> {
        let kept = Outcome {
            position: from,
            reset: false,
            items: Vec::new(),
        };
        if limit == 0 {
            return kept;
        }
        let source = Source {
            current: self.env.fail2ban_log.clone(),
            rotated: env::rotated(&self.env.fail2ban_log),
        };
        match reader::read(&source, from, limit, cutoff, parse_line) {
            Ok(outcome) => outcome,
            Err(Unavailable::Missing) => kept,
            Err(Unavailable::Io(cause)) => self.unreadable(&source.current, &cause, from),
        }
    }

    fn unreadable(
        &self,
        path: &std::path::Path,
        cause: &io::Error,
        from: Position,
    ) -> Outcome<Seen> {
        self.report(&path.to_string_lossy(), &cause.to_string());
        Outcome {
            position: from,
            reset: false,
            items: Vec::new(),
        }
    }

    fn report(&self, what: &str, cause: &str) {
        let first_time = self
            .reported
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .insert(format!("{what}: {cause}"));
        if first_time {
            eprintln!("security: cannot read {what}: {cause}");
        }
    }
}

/// `GET /v1/security/events?after=&limit=`. Reading files and running programs blocks, so it runs off the async threads.
pub async fn events(State(app): State<Arc<App>>, RawQuery(raw): RawQuery) -> Response {
    let asked = match query::parse(raw.as_deref()) {
        Ok(asked) => asked,
        Err(message) => return error(StatusCode::BAD_REQUEST, "invalid_input", message),
    };
    let security = app.security.clone();
    match tokio::task::spawn_blocking(move || security.events(asked.after.as_deref(), asked.limit))
        .await
    {
        Ok(answer) => Json(answer).into_response(),
        Err(_) => error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal",
            "internal error",
        ),
    }
}

/// `metaservice-agent security-dump --auth FILE [--fail2ban FILE] [--limit N] [--all]`: the JSON the route would answer on a first call for those files,
/// with this machine's baseline. `all` keeps lines older than the seven-day window too.
pub fn dump(auth: &str, fail2ban: Option<&str>, limit: usize, all: bool) -> Result<String, String> {
    if !std::path::Path::new(auth).is_file() {
        return Err(format!("{auth} is not a file"));
    }
    let missing = std::path::PathBuf::from("/nonexistent/fail2ban.log");
    let env = Environment::system().with_logs(auth.into(), fail2ban.map_or(missing, Into::into));
    let mut security = Security::new(
        env,
        Arc::new(SystemCommands),
        system_now,
        clock::system_zone,
    );
    if all {
        security.window = EVERYTHING_SECONDS;
    }
    serde_json::to_string_pretty(&security.events(None, limit)).map_err(|cause| cause.to_string())
}

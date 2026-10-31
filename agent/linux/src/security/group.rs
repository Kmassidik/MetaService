//! Parsed lines into the events of one response. Failed tries of one connection count once as a connection, and repeats of the same
//! user and address inside the response become one event whose `count` says how many.
use super::model::{Event, EventType};
use super::parse::{Attempt, Parsed};
use super::text;
use std::collections::HashMap;

/// One parsed line and the second it was written.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Seen {
    pub epoch: i64,
    pub parsed: Parsed,
}

/// One connection to the server: the lines that name the same address and port, or a lone line that names no port.
struct Connection {
    user: Option<String>,
    address: Option<String>,
    tries: u32,
    summarised: bool,
    epoch: i64,
    why: &'static str,
}

struct Tally {
    user: Option<String>,
    address: Option<String>,
    count: u32,
    epoch: i64,
    why: &'static str,
}

impl Connection {
    /// Each try counts; a connection with only a summary line stands for one try.
    fn count(&self) -> u32 {
        self.tries.max(u32::from(self.summarised))
    }
}

pub fn iso(epoch: i64) -> String {
    crate::stats::iso8601(u64::try_from(epoch).unwrap_or(0))
}

/// `bantime` is how long a ban lasts when the jail says so. The events come out oldest first.
pub fn events(seen: &[Seen], bantime: Option<i64>) -> Vec<Event> {
    let mut out = failed_events(seen);
    out.extend(seen.iter().filter_map(|line| other_event(line, bantime)));
    out.sort_by(|a, b| a.time.cmp(&b.time));
    out
}

fn other_event(seen: &Seen, bantime: Option<i64>) -> Option<Event> {
    let time = iso(seen.epoch);
    let event = |kind, user, address, method, until, detail| Event {
        time: time.clone(),
        kind,
        user,
        address,
        method,
        count: 1,
        until,
        detail,
    };
    match &seen.parsed {
        Parsed::Login {
            user,
            address,
            method,
        } => Some(event(
            EventType::Login,
            user.clone(),
            address.clone(),
            *method,
            None,
            None,
        )),
        Parsed::Blocked { address, jail } => Some(event(
            EventType::Blocked,
            None,
            address.clone(),
            None,
            bantime.map(|seconds| iso(seen.epoch + seconds)),
            jail_detail(jail),
        )),
        Parsed::Unblocked { address, jail } => Some(event(
            EventType::Unblocked,
            None,
            address.clone(),
            None,
            None,
            jail_detail(jail),
        )),
        Parsed::Failed { .. } => None,
    }
}

fn jail_detail(jail: &str) -> Option<String> {
    text::clean(&format!("fail2ban jail {jail}"), text::MAX_DETAIL_CHARS)
}

/// Failed lines: first per connection (same address and port), then per user and address.
fn failed_events(seen: &[Seen]) -> Vec<Event> {
    let mut connections: Vec<Connection> = Vec::new();
    let mut known: HashMap<(String, u16), usize> = HashMap::new();
    for line in seen {
        let Parsed::Failed {
            user,
            address,
            port,
            attempt,
            why,
        } = &line.parsed
        else {
            continue;
        };
        let index = match (address, port) {
            (Some(address), Some(port)) => *known
                .entry((address.clone(), *port))
                .or_insert_with(|| open(&mut connections, line.epoch, why)),
            _ => open(&mut connections, line.epoch, why),
        };
        let connection = &mut connections[index];
        connection.user = connection.user.take().or_else(|| user.clone());
        connection.address = connection.address.take().or_else(|| address.clone());
        connection.tries += u32::from(*attempt == Attempt::Try);
        connection.summarised |= *attempt == Attempt::Summary;
        connection.epoch = connection.epoch.max(line.epoch);
        connection.why = why;
    }
    into_events(&connections)
}

fn open(connections: &mut Vec<Connection>, epoch: i64, why: &'static str) -> usize {
    connections.push(Connection {
        user: None,
        address: None,
        tries: 0,
        summarised: false,
        epoch,
        why,
    });
    connections.len() - 1
}

fn into_events(connections: &[Connection]) -> Vec<Event> {
    let mut slots: HashMap<(&Option<String>, &Option<String>), usize> = HashMap::new();
    let mut tallies: Vec<Tally> = Vec::new();
    for connection in connections {
        let index = *slots
            .entry((&connection.user, &connection.address))
            .or_insert_with(|| {
                tallies.push(Tally {
                    user: connection.user.clone(),
                    address: connection.address.clone(),
                    count: 0,
                    epoch: connection.epoch,
                    why: connection.why,
                });
                tallies.len() - 1
            });
        let tally = &mut tallies[index];
        tally.count += connection.count();
        if connection.epoch >= tally.epoch {
            tally.epoch = connection.epoch;
            tally.why = connection.why;
        }
    }
    tallies.into_iter().map(failed_event).collect()
}

fn failed_event(tally: Tally) -> Event {
    Event {
        time: iso(tally.epoch),
        kind: EventType::FailedLogin,
        user: tally.user,
        address: tally.address,
        method: None,
        count: tally.count.max(1),
        until: None,
        detail: Some(text::detail(tally.why)),
    }
}

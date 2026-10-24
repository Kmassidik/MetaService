//! The sandboxes this helper has, and the events it keeps about them.
//!
//! In memory, because a sandbox is short-lived and the machine that runs it is the only one that knows it. The helper is the owner of the end time: `due`
//! takes out every sandbox whose time has come, even when the Root cannot be reached, so none outlives its time. It also remembers which ids it had, so a
//! delete of one that is already gone is still a 204 and only an id this helper never saw is a 404.
use super::record::Sandbox;
use super::time::iso8601;
use serde::ser::SerializeStruct;
use serde::{Serialize, Serializer};
use std::collections::{BTreeMap, HashSet, VecDeque};
use std::sync::Mutex;

/// What happened to a sandbox: what this slice can change.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum EventKind {
    Started,
    Paused,
    Resumed,
    Ended,
}

/// Why the helper ended it by itself, or because it was deleted.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum EndReason {
    Deleted,
    Timeout,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event {
    pub seq: u64,
    /// Seconds since 1970, UTC.
    pub at: u64,
    pub id: String,
    pub kind: EventKind,
    /// Only on `Ended`.
    pub reason: Option<EndReason>,
    pub running_ms: u64,
}

impl Serialize for Event {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut out = serializer.serialize_struct("Event", 6)?;
        out.serialize_field("seq", &self.seq)?;
        out.serialize_field("at", &iso8601(self.at))?;
        out.serialize_field("id", &self.id)?;
        out.serialize_field("kind", &self.kind)?;
        if let Some(reason) = self.reason {
            out.serialize_field("reason", &reason)?;
        }
        out.serialize_field("running_ms", &self.running_ms)?;
        out.end()
    }
}

/// What the sandboxes on this machine hold: vCPU and memory of the running ones, disk of every one of them.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Booking {
    pub vcpu: u64,
    pub ram_mb: u64,
    pub disk_mb: u64,
}

/// How long the events are kept, and how many: a Root that fell further behind reads the whole list again (410 `too_old`).
pub const MAX_EVENTS: usize = 10_000;
pub const EVENT_SECONDS: u64 = 86_400;
/// How many ids of gone sandboxes are remembered for an idempotent delete.
const GONE_IDS: usize = 1_000;

#[derive(Default)]
struct Inner {
    sandboxes: BTreeMap<String, Sandbox>,
    /// The ids of sandboxes this helper had and no longer has, oldest first.
    gone: VecDeque<String>,
    was_known: HashSet<String>,
    events: VecDeque<Event>,
    last_seq: u64,
}

#[derive(Default)]
pub struct Store {
    inner: Mutex<Inner>,
}

impl Store {
    /// Keeps the new sandbox and says it started.
    pub fn insert(&self, sandbox: Sandbox, now: u64) {
        let mut inner = self.inner.lock().unwrap();
        inner.record(&sandbox.id, EventKind::Started, None, sandbox.running_ms(now), now);
        inner.sandboxes.insert(sandbox.id.clone(), sandbox);
    }

    pub fn get(&self, id: &str) -> Option<Sandbox> {
        self.inner.lock().unwrap().sandboxes.get(id).cloned()
    }

    /// Every sandbox that is not gone, by id.
    pub fn list(&self) -> Vec<Sandbox> {
        self.inner.lock().unwrap().sandboxes.values().cloned().collect()
    }

    /// Takes out one sandbox and says it ended. None when this helper does not have it.
    pub fn delete(&self, id: &str, now: u64) -> Option<Sandbox> {
        let mut inner = self.inner.lock().unwrap();
        let sandbox = inner.sandboxes.remove(id)?;
        inner.forget(id);
        inner.record(id, EventKind::Ended, Some(EndReason::Deleted), sandbox.running_ms(now), now);
        Some(sandbox)
    }

    pub fn set_end(&self, id: &str, end_at: u64, on_end: super::record::OnEnd) -> Option<Sandbox> {
        let mut inner = self.inner.lock().unwrap();
        let found = inner.sandboxes.get_mut(id)?;
        found.end_at = end_at;
        found.on_end = on_end;
        Some(found.clone())
    }

    /// Pauses it and says so. Its end time does not move, and a pause of one that is already paused is not a second event.
    pub fn pause(&self, id: &str, now: u64) -> Option<Sandbox> {
        let mut inner = self.inner.lock().unwrap();
        let found = inner.sandboxes.get_mut(id)?;
        if found.paused() {
            return Some(found.clone());
        }
        found.pause(now);
        let paused = found.clone();
        inner.record(id, EventKind::Paused, None, paused.running_ms(now), now);
        Some(paused)
    }

    /// Resumes it and says so. The time it spent paused is not counted as running time, then or later.
    pub fn resume(&self, id: &str, now: u64) -> Option<Sandbox> {
        let mut inner = self.inner.lock().unwrap();
        let found = inner.sandboxes.get_mut(id)?;
        if !found.paused() {
            return Some(found.clone());
        }
        found.resume(now);
        let resumed = found.clone();
        inner.record(id, EventKind::Resumed, None, resumed.running_ms(now), now);
        Some(resumed)
    }

    /// Every sandbox whose end time has come: taken out, marked gone and said to have ended on its time.
    pub fn due(&self, now: u64) -> Vec<Sandbox> {
        let mut inner = self.inner.lock().unwrap();
        let due: Vec<String> = inner.sandboxes.values().filter(|sandbox| sandbox.end_at <= now).map(|sandbox| sandbox.id.clone()).collect();
        due.into_iter()
            .filter_map(|id| {
                let sandbox = inner.sandboxes.remove(&id)?;
                inner.forget(&id);
                inner.record(&id, EventKind::Ended, Some(EndReason::Timeout), sandbox.running_ms(now), now);
                Some(sandbox)
            })
            .collect()
    }

    /// Whether this helper ever had that sandbox, so a second delete is still a 204.
    pub fn was_known(&self, id: &str) -> bool {
        let inner = self.inner.lock().unwrap();
        inner.was_known.contains(id) || inner.sandboxes.contains_key(id)
    }

    /// The events after `after`, oldest first, with the number of the newest one. Err when the caller fell behind what is kept.
    pub fn events_after(&self, after: u64, limit: usize) -> Result<(Vec<Event>, u64), ()> {
        let inner = self.inner.lock().unwrap();
        let oldest = inner.last_seq.saturating_sub(inner.events.len() as u64);
        if after < oldest {
            return Err(());
        }
        let events = inner.events.iter().filter(|event| event.seq > after).take(limit).cloned().collect();
        Ok((events, inner.last_seq))
    }

    /// The number of the last event: the Root reads the events when this moves.
    pub fn changes(&self) -> u64 {
        self.inner.lock().unwrap().last_seq
    }

    /// How many sandboxes are running now: a paused one is not running, and it uses no CPU or memory while it waits.
    pub fn running(&self) -> usize {
        self.inner.lock().unwrap().sandboxes.values().filter(|sandbox| !sandbox.paused()).count()
    }

    /// How many are paused. They keep their disk and their place on the machine, which is why their disk is still booked below.
    pub fn paused(&self) -> usize {
        self.inner.lock().unwrap().sandboxes.values().filter(|sandbox| sandbox.paused()).count()
    }

    pub fn booked(&self) -> Booking {
        self.inner.lock().unwrap().sandboxes.values().fold(Booking::default(), |all, sandbox| {
            // A paused sandbox holds no vCPU and no memory; it does hold its disk, which is what makes a resume possible.
            let running = u64::from(!sandbox.paused());
            Booking {
                vcpu: all.vcpu + u64::from(sandbox.vcpu) * running,
                ram_mb: all.ram_mb + sandbox.ram_mb * running,
                disk_mb: all.disk_mb + sandbox.disk_mb,
            }
        })
    }
}

impl Inner {
    /// Remembers a sandbox this helper no longer has, and forgets the oldest when there are too many.
    fn forget(&mut self, id: &str) {
        if !self.was_known.insert(id.to_string()) {
            return;
        }
        self.gone.push_back(id.to_string());
        while self.gone.len() > GONE_IDS {
            if let Some(oldest) = self.gone.pop_front() {
                self.was_known.remove(&oldest);
            }
        }
    }

    fn record(&mut self, id: &str, kind: EventKind, reason: Option<EndReason>, running_ms: u64, now: u64) {
        self.last_seq += 1;
        self.events.push_back(Event { seq: self.last_seq, at: now, id: id.to_string(), kind, reason, running_ms });
        while self.events.len() > MAX_EVENTS || self.events.front().is_some_and(|oldest| now.saturating_sub(oldest.at) > EVENT_SECONDS) {
            self.events.pop_front();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sandbox::record::{CreateRequest, OnEnd};
    use serde_json::json;

    const ID: &str = "abcdefghij0123456789";
    const OTHER: &str = "zyxwvutsrq9876543210";
    const NOW: u64 = 1_792_834_200;

    fn sandbox(id: &str, vcpu: u32, ram_mb: u64, disk_mb: u64, end_at: u64) -> Sandbox {
        let body = json!({"id": id, "template": "base", "vcpu": vcpu, "ram_mb": ram_mb, "disk_mb": disk_mb, "end_at": crate::sandbox::time::iso8601(end_at),
            "on_end": "kill", "internet": false, "env_vars": {}, "access_token": "t".repeat(40)});
        let request = CreateRequest::parse(body.to_string().as_bytes()).ok().unwrap();
        Sandbox::new(&request, "1".into(), format!("fingerprint-{id}"), NOW)
    }

    fn store_with_one() -> Store {
        let store = Store::default();
        store.insert(sandbox(ID, 2, 512, 1024, NOW + 300), NOW);
        store
    }

    #[test]
    fn a_new_sandbox_is_there_and_says_it_started() {
        let store = store_with_one();
        assert_eq!(store.get(ID).map(|found| found.id), Some(ID.to_string()));
        assert_eq!(store.list().len(), 1);
        let (events, last) = store.events_after(0, 10).ok().unwrap();
        assert_eq!((events.len(), last), (1, 1));
        assert_eq!((events[0].kind, events[0].reason), (EventKind::Started, None));
    }

    #[test]
    fn an_unknown_id_is_nothing_and_was_never_known() {
        let store = store_with_one();
        assert!(store.get("nosuchid01234567890").is_none());
        assert!(!store.was_known(OTHER));
        assert!(store.set_end(OTHER, NOW, OnEnd::Kill).is_none());
        assert!(store.delete(OTHER, NOW).is_none());
        assert!(!store.was_known(OTHER), "a delete of something this helper never had must not remember it");
    }

    #[test]
    fn its_end_time_takes_it_out_and_says_why() {
        let store = store_with_one();
        assert!(store.due(NOW + 299).is_empty(), "one second before the end time it is still there");
        let gone = store.due(NOW + 300);
        assert_eq!(gone.iter().map(|found| found.id.as_str()).collect::<Vec<_>>(), [ID]);
        assert!(store.get(ID).is_none());
        assert!(store.was_known(ID), "a deleted sandbox that ran out of time is still one this helper had");
        let (events, last) = store.events_after(0, 10).ok().unwrap();
        assert_eq!(last, 2);
        assert_eq!((events[1].kind, events[1].reason, events[1].running_ms), (EventKind::Ended, Some(EndReason::Timeout), 300_000));
        assert!(store.due(NOW + 400).is_empty(), "it is only taken out once");
    }

    #[test]
    fn a_delete_takes_it_out_and_a_second_one_changes_nothing() {
        let store = store_with_one();
        assert_eq!(store.delete(ID, NOW + 5).map(|found| found.id), Some(ID.to_string()));
        assert!(store.delete(ID, NOW + 6).is_none());
        assert!(store.was_known(ID));
        assert!(store.list().is_empty());
        let (events, last) = store.events_after(0, 10).ok().unwrap();
        assert_eq!(last, 2);
        assert_eq!((events[1].kind, events[1].reason), (EventKind::Ended, Some(EndReason::Deleted)));
    }

    #[test]
    fn a_new_end_time_is_kept_as_asked() {
        let store = store_with_one();
        let changed = store.set_end(ID, NOW + 600, OnEnd::Pause).unwrap();
        assert_eq!((changed.end_at, changed.on_end), (NOW + 600, OnEnd::Pause));
        assert_eq!(store.get(ID).unwrap().end_at, NOW + 600);
    }

    #[test]
    fn a_pause_keeps_the_end_time_and_its_running_time_stands_still() {
        let store = store_with_one();
        let paused = store.pause(ID, NOW + 10).unwrap();
        assert!(paused.paused() && paused.state() == "paused");
        assert_eq!(paused.end_at, NOW + 300, "a pause does not move when it ends");
        assert_eq!(paused.running_ms(NOW + 40), 10_000, "the time it has spent paused is not running time");
        assert_eq!((store.running(), store.paused()), (0, 1));
        assert_eq!(store.booked(), Booking { vcpu: 0, ram_mb: 0, disk_mb: 1024 }, "a paused sandbox holds no vCPU and no memory, and keeps its disk");
        assert_eq!(store.pause(ID, NOW + 20).map(|found| found.running_ms(NOW + 40)), Some(10_000), "a second pause does not restart its clock");
        let resumed = store.resume(ID, NOW + 40).unwrap();
        assert!(!resumed.paused() && resumed.state() == "running");
        assert_eq!(resumed.running_ms(NOW + 60), 30_000, "10 s before the pause, 20 s after it");
        assert_eq!(resumed.end_at, NOW + 300, "and the end time is still the one it had");
        assert_eq!((store.running(), store.paused()), (1, 0));
        let (events, last) = store.events_after(0, 10).ok().unwrap();
        assert_eq!(last, 3, "started, paused, resumed: nothing more");
        assert_eq!(events.iter().map(|event| event.kind).collect::<Vec<_>>(), [EventKind::Started, EventKind::Paused, EventKind::Resumed]);
        assert_eq!(events[2].running_ms, 10_000);
        assert_eq!(store.resume(ID, NOW + 70).map(|found| found.running_ms(NOW + 70)), Some(40_000), "a resume of a running sandbox changes nothing");
    }

    #[test]
    fn a_paused_sandbox_that_runs_out_of_time_is_still_taken_away() {
        let store = store_with_one();
        store.pause(ID, NOW + 10).unwrap();
        let gone = store.due(NOW + 300);
        assert_eq!(gone.iter().map(|found| found.paused()).collect::<Vec<_>>(), [true], "its end time belongs to the helper, not to its engine");
        assert!(store.get(ID).is_none());
        assert_eq!(store.paused(), 0);
    }

    #[test]
    fn a_pause_of_an_unknown_sandbox_is_nothing() {
        let store = store_with_one();
        assert!(store.pause(OTHER, NOW).is_none());
        assert!(store.resume(OTHER, NOW).is_none());
        assert_eq!(store.changes(), 1, "and it says nothing happened");
    }

    #[test]
    fn the_events_come_in_order_and_only_after_the_number_asked_for() {
        let store = Store::default();
        for (number, id) in [ID, OTHER].iter().enumerate() {
            store.insert(sandbox(id, 1, 512, 1024, NOW + 60), NOW + number as u64);
        }
        let (events, last) = store.events_after(0, 10).ok().unwrap();
        assert_eq!((events.iter().map(|event| event.seq).collect::<Vec<_>>(), last), (vec![1, 2], 2));
        let (later, last) = store.events_after(1, 10).ok().unwrap();
        assert_eq!((later.len(), last), (1, 2));
        assert!(store.events_after(2, 10).ok().unwrap().0.is_empty());
        assert_eq!(store.changes(), 2);
        assert_eq!(store.events_after(0, 1).ok().unwrap().0.len(), 1, "a limit is a limit");
    }

    #[test]
    fn a_root_that_fell_too_far_behind_is_told_to_read_everything_again() {
        let store = Store::default();
        store.inner.lock().unwrap().last_seq = MAX_EVENTS as u64 + 5;
        assert_eq!(store.events_after(0, 10), Err(()), "the oldest events are gone");
        assert!(store.events_after(MAX_EVENTS as u64 + 5, 10).is_ok());
    }

    #[test]
    fn what_the_sandboxes_hold_is_added_up() {
        let store = Store::default();
        store.insert(sandbox(ID, 2, 512, 1024, NOW + 60), NOW);
        store.insert(sandbox(OTHER, 4, 1024, 2048, NOW + 60), NOW);
        assert_eq!(store.running(), 2);
        assert_eq!(store.booked(), Booking { vcpu: 6, ram_mb: 1536, disk_mb: 3072 });
        store.delete(ID, NOW);
        assert_eq!((store.running(), store.booked()), (1, Booking { vcpu: 4, ram_mb: 1024, disk_mb: 2048 }));
    }
}

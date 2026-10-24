//! Sandboxes: the helper's half of contract/openapi.yaml, `/v1/sandboxes`, `/v1/sandbox-events` and `/v1/sandbox-templates`.
//!
//! A sandbox is not another kind of workload (sandbox/README.md): there are many of them, they live for minutes, programs make them, and they must be gone
//! at their end time even when the Root is down. So they get their own records, their own list, their own events and their own routes.
//!
//! This slice is the contract and a simulated engine: the records, the end times, the events and the routes are real, and nothing is virtualised yet. The
//! Firecracker engine (jailer, a network namespace per sandbox, the daemon inside, snapshots, pause and resume, the way into a port) comes later and only
//! has to be given as another `SandboxEngine`. A helper with no engine answers 404 on every sandbox route and says nothing about sandboxes in its facts,
//! which is what the contract says a helper from before them does.
mod engine;
pub mod firecracker;
mod record;
mod routes;
pub mod runner;
mod store;
#[cfg(test)]
mod tests;
mod time;

pub use engine::{Limits, Sample, SandboxEngine, SimulatedSandboxEngine, Template, SIMULATED};
pub use record::{CreateRequest, EndRequest, Sandbox};
pub use store::Event;

pub(crate) use routes::{create, delete, events, get, list, metrics, ports, set_end, templates};

use crate::models::{SandboxBooking, SandboxEngineInfo, SandboxFacts, SandboxTemplateFacts};
use sha2::{Digest, Sha256};use std::sync::Arc;
use std::time::Duration;
use store::Store;

/// Seconds between two looks at the end times. A sandbox outlives its time by at most this much.
pub const SWEEP_SECONDS: u64 = 2;
/// How many events one read answers with, when the Root does not say.
pub const EVENTS_PER_READ: usize = 500;

/// Why a sandbox request cannot be answered the way it asked. Each one becomes one status code in routes.rs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// This helper cannot run sandboxes at all, so every sandbox route is a 404, like a helper from before them.
    NoEngine,
    NotFound,
    Invalid(String),
    /// This id was used before, for a different sandbox.
    IdTaken,
    /// The machine has not built that template (yet).
    TemplateNotReady(String),
    /// Not enough room for one of its sizes, or for the sandbox itself.
    Room { message: String, resource: &'static str, needed: u64, free: u64 },
    /// Nothing can be passed into a sandbox yet, because there is no network for one.
    NoPortProxy,
    /// The Root asks for events that are no longer kept.
    TooOld,
    /// The engine's own reason, for the helper's log only.
    Engine(String),
}

/// What a create answered: the sandbox, and whether it was made now (201) or is the one an earlier, identical call made (200).
#[derive(Clone, Debug, PartialEq)]
pub struct Made {
    pub sandbox: Sandbox,
    pub made: bool,
}

/// The sandboxes this helper has, over the engine that runs them.
///
/// The store is the truth the Root reads; the engine is asked to start and stop. The end time belongs to the helper, so a sweep runs when this starts and
/// every few seconds after, whatever the Root is doing.
pub struct Sandboxes {
    store: Store,
    engine: Option<Arc<dyn SandboxEngine>>,
}

impl Sandboxes {
    pub fn new(engine: Option<Arc<dyn SandboxEngine>>) -> Arc<Sandboxes> {
        Arc::new(Sandboxes { store: Store::default(), engine })
    }

    /// A helper that cannot run sandboxes: every sandbox route is a 404 and its facts say nothing about them.
    pub fn disabled() -> Arc<Sandboxes> {
        Self::new(None)
    }

    /// The test engine, with its end times kept from this moment on. It needs no root and no Firecracker, and nothing inside it can be reached.
    pub fn simulated(limits: Limits) -> Arc<Sandboxes> {
        Self::running(Arc::new(SimulatedSandboxEngine::new(limits)))
    }

    /// Any engine, with its end times kept from this moment on and acted on every few seconds: the helper owns the end time, so it does not wait for
    /// the Root to ask.
    pub fn running(engine: Arc<dyn SandboxEngine>) -> Arc<Sandboxes> {
        let sandboxes = Self::new(Some(engine));
        sandboxes.sweep();
        let ticking = sandboxes.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(SWEEP_SECONDS));
            ticking.sweep();
        });
        sandboxes
    }

    pub fn enabled(&self) -> bool {
        self.engine.is_some()
    }

    fn engine(&self) -> Result<&Arc<dyn SandboxEngine>, Refusal> {
        self.engine.as_ref().ok_or(Refusal::NoEngine)
    }

    /// Ends every sandbox whose time has come, and everything it had: the record is gone from the store either way, so what is left on the machine is
    /// the engine's to take away, and nothing this helper no longer has may keep a namespace or a disk.
    pub fn sweep(&self) {
        let Some(engine) = self.engine.as_ref() else { return };
        for sandbox in self.store.due(time::now()) {
            if let Err(cause) = engine.delete(&sandbox.id) {
                eprintln!("sandbox {} could not be removed at its end time: {cause}", sandbox.id);
            }
        }
    }

    /// Makes a sandbox and answers once it is ready. The same id with the same body is answered with the sandbox it already made (a retry is safe);
    /// the same id with a different body is refused, so two sandboxes never share an id.
    pub fn create(&self, body: &[u8]) -> Result<Made, Refusal> {
        let engine = self.engine()?;
        let request = CreateRequest::parse(body).map_err(Refusal::Invalid)?;
        self.sweep();
        if let Some(existing) = self.store.get(&request.id) {
            if existing.fingerprint() == fingerprint(body) {
                return Ok(Made { sandbox: existing, made: false });
            }
            return Err(Refusal::IdTaken);
        }
        // An id this helper had and no longer has cannot be answered with that sandbox again, so it is not given to a new one either.
        if self.store.was_known(&request.id) {
            return Err(Refusal::IdTaken);
        }
        let build = template_build(engine, &request.template)?;
        self.check_room(engine.limits(), &request)?;
        let sandbox = Sandbox::new(&request, build, fingerprint(body), time::now());
        engine.create(&sandbox).map_err(Refusal::Engine)?;
        self.store.insert(sandbox.clone(), time::now());
        Ok(Made { sandbox, made: true })
    }

    pub fn list(&self) -> Result<Vec<Sandbox>, Refusal> {
        self.engine()?;
        self.sweep();
        Ok(self.store.list())
    }

    pub fn get(&self, id: &str) -> Result<Sandbox, Refusal> {
        self.engine()?;
        if !record::is_sandbox_id(id) {
            return Err(Refusal::NotFound);
        }
        self.sweep();
        self.store.get(id).ok_or(Refusal::NotFound)
    }

    /// Removes the sandbox and everything it had. A sandbox this helper had and no longer has is not an error: the answer is the same.
    pub fn delete(&self, id: &str) -> Result<(), Refusal> {
        let engine = self.engine()?;
        if !record::is_sandbox_id(id) {
            return Err(Refusal::NotFound);
        }
        self.sweep();
        if self.store.delete(id, time::now()).is_none() {
            if !self.store.was_known(id) {
                return Err(Refusal::NotFound);
            }
            return Ok(());
        }
        engine.delete(id).map_err(Refusal::Engine)
    }

    pub fn set_end(&self, id: &str, body: &[u8]) -> Result<Sandbox, Refusal> {
        self.engine()?;
        if !record::is_sandbox_id(id) {
            return Err(Refusal::NotFound);
        }
        let request = EndRequest::parse(body).map_err(Refusal::Invalid)?;
        self.store.set_end(id, request.end_at, request.on_end).ok_or(Refusal::NotFound)
    }

    pub fn metrics(&self, id: &str) -> Result<Vec<Sample>, Refusal> {
        let engine = self.engine()?;
        let sandbox = self.get(id)?;
        Ok(engine.metrics(&sandbox, time::now()))
    }

    /// The events after `after`, and the number of the newest one.
    pub fn events(&self, after: u64, limit: usize) -> Result<(Vec<Event>, u64), Refusal> {
        self.engine()?;
        self.store.events_after(after, limit).map_err(|_| Refusal::TooOld)
    }

    pub fn templates(&self) -> Result<Vec<Template>, Refusal> {
        Ok(self.engine()?.templates())
    }

    /// What the facts say about sandboxes, or None when this helper cannot run them.
    pub fn facts(&self) -> Option<SandboxFacts> {
        let engine = self.engine.as_ref()?;
        let limits = engine.limits();
        let booked = self.store.booked();
        Some(SandboxFacts {
            engine: SandboxEngineInfo { name: engine.name().into(), version: engine.version() },
            max_running: limits.max_running,
            running: self.store.running(),
            // Nothing can be paused yet: a sandbox is killed at its end time in this slice.
            paused: 0,
            max_vcpu: limits.max_vcpu,
            max_ram_mb: limits.max_ram_mb,
            max_disk_mb: limits.max_disk_mb,
            booked: SandboxBooking { vcpu: booked.vcpu, ram_mb: booked.ram_mb, disk_mb: booked.disk_mb },
            templates: engine.templates().iter().map(|template| SandboxTemplateFacts { id: template.id.clone(), build: template.build.clone(), ready: template.ready() }).collect(),
            changes: self.store.changes(),
        })
    }

    /// The room this machine has for the sandbox it is asked for: one slot, and one of each of its sizes.
    fn check_room(&self, limits: Limits, request: &CreateRequest) -> Result<(), Refusal> {
        let booked = self.store.booked();
        let free = [
            (Size::Slots, 1, u64::from(limits.max_running).saturating_sub(self.store.running() as u64)),
            (Size::Vcpu, u64::from(request.vcpu), u64::from(limits.max_vcpu).saturating_sub(booked.vcpu)),
            (Size::RamMb, request.ram_mb, limits.max_ram_mb.saturating_sub(booked.ram_mb)),
            (Size::DiskMb, request.disk_mb, limits.max_disk_mb.saturating_sub(booked.disk_mb)),
        ];
        free.into_iter().find(|(_, needed, free)| needed > free).map_or(Ok(()), |(resource, needed, free)| Err(Refusal::Room { message: resource.message().into(), resource: resource.name(), needed, free }))
    }
}

/// The sizes a sandbox asks for, as the refusal names them (`resource` in the contract).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Size {
    Slots,
    Vcpu,
    RamMb,
    DiskMb,
}

impl Size {
    fn name(self) -> &'static str {
        match self {
            Size::Slots => "slots",
            Size::Vcpu => "vcpu",
            Size::RamMb => "ram_mb",
            Size::DiskMb => "disk_mb",
        }
    }

    fn message(self) -> &'static str {
        match self {
            Size::Slots => "this machine is running all the sandboxes it may run",
            Size::Vcpu => "not enough vCPU left on this machine for this sandbox",
            Size::RamMb => "not enough memory left on this machine for this sandbox",
            Size::DiskMb => "not enough disk left on this machine for this sandbox",
        }
    }
}

/// The build of the template the sandbox must start from, or a refusal when this machine has no ready template by that name.
fn template_build(engine: &Arc<dyn SandboxEngine>, template: &str) -> Result<String, Refusal> {
    engine.templates().into_iter().find(|found| found.id == template && found.ready()).map(|found| found.build.clone()).ok_or_else(|| Refusal::TemplateNotReady(template.to_string()))
}

/// A short, stable name for a create body, so a retry with the same id and the same body is answered with the sandbox it already made.
fn fingerprint(body: &[u8]) -> String {
    Sha256::digest(body).iter().map(|byte| format!("{byte:02x}")).collect()
}

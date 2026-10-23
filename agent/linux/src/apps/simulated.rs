//! The simulated engine's idea of the app installs: an in-memory set of installed apps per VM and a behaviour tests can switch.
//! It answers with the same lines the real script prints, so the parser and the error mapping run the same way.
use super::report::AppFailure;
use super::script::RESULT_MARKER;
use super::App;
use std::collections::HashSet;
use std::sync::Mutex;
use std::time::Duration;

/// What the pretend vendor installer prints as its version, and the SHA-256 of the pretend installer file.
pub const SIMULATED_VERSION: &str = "2026.9.4";
pub const SIMULATED_SHA256: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

/// How a simulated install of a missing app goes (switched by tests).
#[cfg_attr(not(test), allow(dead_code))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SimulatedApp {
    Works,
    Fails(AppFailure),
    /// Waits this long, then works.
    Delay(Duration),
    /// Prints nothing the helper can read.
    Garbage,
}

pub struct SimulatedApps {
    behaviour: Mutex<SimulatedApp>,
    installed: Mutex<HashSet<(String, App)>>,
}

#[cfg_attr(not(test), allow(dead_code))]
impl SimulatedApps {
    pub fn new() -> Self {
        SimulatedApps { behaviour: Mutex::new(SimulatedApp::Works), installed: Mutex::new(HashSet::new()) }
    }

    pub fn set_behaviour(&self, behaviour: SimulatedApp) {
        *self.behaviour.lock().unwrap() = behaviour;
    }

    pub fn is_installed(&self, id: &str, app: App) -> bool {
        self.installed.lock().unwrap().contains(&(id.to_string(), app))
    }

    /// What the script would have printed for this app in this VM.
    pub fn run(&self, id: &str, app: App) -> String {
        let key = (id.to_string(), app);
        if self.installed.lock().unwrap().contains(&key) {
            return result_lines(app, false, None);
        }
        let behaviour = *self.behaviour.lock().unwrap();
        match behaviour {
            SimulatedApp::Garbage => "something else entirely\n".into(),
            SimulatedApp::Fails(failure) => format!("simulated installer output\n{}", failure_lines(app, failure)),
            SimulatedApp::Works => self.finish(key, app),
            SimulatedApp::Delay(wait) => {
                std::thread::sleep(wait);
                self.finish(key, app)
            }
        }
    }

    fn finish(&self, key: (String, App), app: App) -> String {
        self.installed.lock().unwrap().insert(key);
        result_lines(app, true, Some(SIMULATED_SHA256))
    }
}

fn result_lines(app: App, installed: bool, sha256: Option<&str>) -> String {
    let sha = sha256.map(|hash| format!("sha256={hash}\n")).unwrap_or_default();
    format!("{RESULT_MARKER}\napp={}\ninstalled={installed}\nversion={SIMULATED_VERSION}\n{sha}", app.name())
}

fn failure_lines(app: App, failure: AppFailure) -> String {
    format!("{RESULT_MARKER}\napp={}\ninstalled=false\nfailure={}\n", app.name(), failure.code())
}

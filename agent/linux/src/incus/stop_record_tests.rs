//! A container the GPU watchdog stopped carries a record; starting it again clears the record first.
use super::*;
use crate::models::Capabilities;

const STOPPED_BY_WATCHDOG: &str = r#"[{"name":"ms-w-1","status":"Stopped","config":{"user.metaservice.id":"w-1","user.metaservice.name":"d","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1","user.metaservice.gpu_mode":"container","user.metaservice.gpu_memory_gb":"4","user.metaservice.gpu_stop_code":"gpu_memory_over_limit","user.metaservice.gpu_stop_used_mib":"5325"}}]"#;
const STOPPED_BY_HAND: &str = r#"[{"name":"ms-w-1","status":"Stopped","config":{"user.metaservice.id":"w-1","user.metaservice.name":"d","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1"}}]"#;

struct Recording {
    list: &'static str,
    calls: Mutex<Vec<String>>,
}

impl Runner for Recording {
    fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push(arguments.join(" "));
        Ok(if arguments[0] == "list" { self.list.to_string() } else { String::new() })
    }

    fn run_with_input(&self, arguments: &[String], _input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.run(arguments, timeout)
    }
}

fn start_and_collect(list: &'static str) -> Vec<String> {
    let runner = Arc::new(Recording { list, calls: Mutex::new(Vec::new()) });
    let capabilities = Capabilities { vm: false, container: true, gpu_in_vm: false, gpu_in_container: true, cpu: CpuOffer::HOST_ONLY, sandbox: false };
    let engine = IncusEngine::new(runner.clone(), capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1);
    let _ = engine.set_running("w-1", true);
    let calls = runner.calls.lock().unwrap();
    calls.iter().filter(|call| !call.starts_with("list")).cloned().collect()
}

#[test]
fn starting_a_container_the_watchdog_stopped_clears_the_record_first() {
    let calls = start_and_collect(STOPPED_BY_WATCHDOG);
    assert_eq!(calls[..3], ["config unset ms-w-1 user.metaservice.gpu_stop_code", "config unset ms-w-1 user.metaservice.gpu_stop_used_mib", "start ms-w-1"]);
}

#[test]
fn starting_any_other_container_changes_no_settings() {
    assert_eq!(start_and_collect(STOPPED_BY_HAND), ["start ms-w-1"]);
}

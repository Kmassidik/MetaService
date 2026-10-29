//! Docker containers and unmanaged Incus instances. Discovery is read-only; actions always resolve a fresh target first.
use crate::incus::{ProcessRunner, Runner};
use crate::models::{CommandType, EngineError};
use serde::Serialize;
use serde_json::Value;
use std::sync::Arc;
use std::time::Duration;

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(30);
const ACTION_TIMEOUT: Duration = Duration::from_secs(90);
const MAX_SERVICES: usize = 5000;
const MAX_ERROR_BYTES: usize = 300;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Runtime {
    Docker,
    Incus,
}

impl Runtime {
    fn prefix(self) -> &'static str {
        match self {
            Runtime::Docker => "docker:",
            Runtime::Incus => "incus:",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ExternalKind {
    Vm,
    Container,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ExternalState {
    Running,
    Stopped,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ExternalService {
    pub id: String,
    pub name: String,
    pub runtime: Runtime,
    pub kind: ExternalKind,
    pub state: ExternalState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ExternalWarning {
    pub runtime: Runtime,
    pub message: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct Discovery {
    pub services: Vec<ExternalService>,
    pub warnings: Vec<ExternalWarning>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExternalAction {
    Start,
    Stop,
    Restart,
}

impl ExternalAction {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "start" => Some(Self::Start),
            "stop" => Some(Self::Stop),
            "restart" => Some(Self::Restart),
            _ => None,
        }
    }

    pub fn command_type(self) -> CommandType {
        match self {
            Self::Start => CommandType::Start,
            Self::Stop => CommandType::Stop,
            Self::Restart => CommandType::Restart,
        }
    }

    fn verb(self) -> &'static str {
        match self {
            Self::Start => "start",
            Self::Stop => "stop",
            Self::Restart => "restart",
        }
    }

    pub fn final_state(self) -> &'static str {
        match self {
            Self::Stop => "stopped",
            Self::Start | Self::Restart => "running",
        }
    }
}

pub struct ExternalServices {
    docker: Option<Arc<dyn Runner>>,
    incus: Option<Arc<dyn Runner>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExternalTarget {
    runtime: Runtime,
    native_id: String,
}

impl ExternalServices {
    pub fn empty() -> Self {
        Self { docker: None, incus: None }
    }

    pub fn system(incus_path: Option<String>) -> Self {
        let docker = find_program("docker").map(|path| Arc::new(ProcessRunner { path }) as Arc<dyn Runner>);
        let incus = incus_path.map(|path| Arc::new(ProcessRunner { path }) as Arc<dyn Runner>);
        Self { docker, incus }
    }

    #[cfg(test)]
    fn with_runners(docker: Option<Arc<dyn Runner>>, incus: Option<Arc<dyn Runner>>) -> Self {
        Self { docker, incus }
    }

    pub fn discover(&self) -> Discovery {
        let mut found = Discovery::default();
        self.discover_runtime(Runtime::Docker, &mut found);
        self.discover_runtime(Runtime::Incus, &mut found);
        found.services.sort_by(|a, b| a.id.cmp(&b.id));
        found
    }

    fn runner(&self, runtime: Runtime) -> Option<&Arc<dyn Runner>> {
        match runtime {
            Runtime::Docker => self.docker.as_ref(),
            Runtime::Incus => self.incus.as_ref(),
        }
    }

    fn discover_runtime(&self, runtime: Runtime, found: &mut Discovery) {
        let Some(runner) = self.runner(runtime) else { return };
        let arguments = match runtime {
            Runtime::Docker => vec!["ps".into(), "-a".into(), "--no-trunc".into(), "--format".into(), "{{json .}}".into()],
            Runtime::Incus => vec!["list".into(), "--format".into(), "json".into()],
        };
        match runner.run(&arguments, DISCOVERY_TIMEOUT) {
            Ok(output) => match parse(runtime, &output) {
                Ok(mut services) => found.services.append(&mut services),
                Err(message) => found.warnings.push(ExternalWarning { runtime, message }),
            },
            Err(EngineError::NotFound) => {}
            Err(EngineError::Failed(message)) => found.warnings.push(ExternalWarning { runtime, message: bounded_message(&message, "runtime query failed") }),
        }
    }

    pub fn resolve(&self, id: &str) -> Result<ExternalTarget, EngineError> {
        let found = self.discover().services.into_iter().find(|service| service.id == id).ok_or(EngineError::NotFound)?;
        let native_id = id.strip_prefix(found.runtime.prefix()).filter(|native| !native.is_empty()).ok_or(EngineError::NotFound)?;
        Ok(ExternalTarget { runtime: found.runtime, native_id: native_id.to_string() })
    }

    pub fn execute(&self, target: &ExternalTarget, action: ExternalAction) -> Result<(), EngineError> {
        let runner = self.runner(target.runtime).ok_or(EngineError::NotFound)?;
        let arguments = vec![action.verb().into(), target.native_id.clone()];
        runner.run(&arguments, ACTION_TIMEOUT).map(|_| ())
    }
}

fn find_program(program: &str) -> Option<String> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path).map(|folder| folder.join(program)).find(|candidate| candidate.is_file()).map(|candidate| candidate.display().to_string())
}

fn parse(runtime: Runtime, output: &str) -> Result<Vec<ExternalService>, String> {
    match runtime {
        Runtime::Docker => parse_docker(output),
        Runtime::Incus => parse_incus(output),
    }
}

fn parse_docker(output: &str) -> Result<Vec<ExternalService>, String> {
    let mut services = Vec::new();
    for line in output.lines().filter(|line| !line.trim().is_empty()).take(MAX_SERVICES) {
        let item: Value = serde_json::from_str(line).map_err(|_| "docker returned unreadable service data".to_string())?;
        let Some(id) = text(&item, "ID") else { continue };
        let Some(name) = text(&item, "Names") else { continue };
        let state = match text(&item, "State").as_deref() {
            Some("running") => ExternalState::Running,
            Some("exited" | "created") => ExternalState::Stopped,
            _ => ExternalState::Unknown,
        };
        services.push(ExternalService { id: format!("docker:{id}"), name, runtime: Runtime::Docker, kind: ExternalKind::Container, state, image: text(&item, "Image") });
    }
    Ok(services)
}

fn parse_incus(output: &str) -> Result<Vec<ExternalService>, String> {
    let Value::Array(items) = serde_json::from_str(output).map_err(|_| "incus returned unreadable service data".to_string())? else {
        return Err("incus returned unreadable service data".into());
    };
    Ok(items.iter().take(MAX_SERVICES).filter_map(parse_incus_instance).collect())
}

fn parse_incus_instance(item: &Value) -> Option<ExternalService> {
    let config = item.get("config").and_then(Value::as_object);
    if config.is_some_and(|config| config.contains_key("user.metaservice.id")) {
        return None;
    }
    let name = text(item, "name")?;
    let kind = match text(item, "type").as_deref() {
        Some("virtual-machine") => ExternalKind::Vm,
        Some("container") => ExternalKind::Container,
        _ => return None,
    };
    let state = match text(item, "status").as_deref() {
        Some("Running") => ExternalState::Running,
        Some("Stopped") => ExternalState::Stopped,
        _ => ExternalState::Unknown,
    };
    let image = config.and_then(|config| config.get("image.alias")).and_then(Value::as_str).map(str::to_string);
    Some(ExternalService { id: format!("incus:{name}"), name, runtime: Runtime::Incus, kind, state, image })
}

fn text(item: &Value, key: &str) -> Option<String> {
    item.get(key).and_then(Value::as_str).filter(|value| !value.is_empty()).map(str::to_string)
}

pub fn bounded_message(reason: &str, fallback: &str) -> String {
    let mut message = reason.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut end = MAX_ERROR_BYTES.min(message.len());
    while !message.is_char_boundary(end) {
        end -= 1;
    }
    message.truncate(end);
    if message.is_empty() { fallback.into() } else { message }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::CommandState;
    use crate::ssh_keys_tests::{machine, send, TOKEN};
    use axum::http::StatusCode;
    use serde_json::json;
    use std::collections::VecDeque;
    use std::sync::Mutex;

    struct FakeRunner {
        answers: Mutex<VecDeque<Result<String, EngineError>>>,
        calls: Mutex<Vec<Vec<String>>>,
    }

    impl FakeRunner {
        fn new(answers: Vec<Result<String, EngineError>>) -> Arc<Self> {
            Arc::new(Self { answers: Mutex::new(answers.into()), calls: Mutex::new(Vec::new()) })
        }
    }

    impl Runner for FakeRunner {
        fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
            self.calls.lock().unwrap().push(arguments.to_vec());
            self.answers.lock().unwrap().pop_front().unwrap_or_else(|| Ok(String::new()))
        }

        fn run_with_input(&self, arguments: &[String], _input: &[u8], timeout: Duration) -> Result<String, EngineError> {
            self.run(arguments, timeout)
        }
    }

    fn docker_line(id: &str, name: &str, state: &str) -> String {
        json!({"ID": id, "Names": name, "Image": "nginx:latest", "State": state}).to_string()
    }

    #[test]
    fn discovery_parses_stopped_docker_and_excludes_managed_incus_by_metadata() {
        let docker = FakeRunner::new(vec![Ok(format!("{}\n{}\n", docker_line("full-docker-id", "web", "running"), docker_line("stopped-id", "old", "exited")))]);
        let incus = FakeRunner::new(vec![Ok(json!([
            {"name":"ms-w-1","type":"virtual-machine","status":"Running","config":{"user.metaservice.id":"w-1"}},
            {"name":"elsewhere","type":"container","status":"Stopped","config":{"image.alias":"ubuntu/24.04"}}
        ]).to_string())]);
        let services = ExternalServices::with_runners(Some(docker.clone()), Some(incus.clone()));
        let found = services.discover();
        assert_eq!(found.warnings, Vec::new());
        assert_eq!(found.services.iter().map(|service| service.id.as_str()).collect::<Vec<_>>(), ["docker:full-docker-id", "docker:stopped-id", "incus:elsewhere"]);
        assert_eq!(found.services[1].state, ExternalState::Stopped);
        assert_eq!(found.services[2].kind, ExternalKind::Container);
        assert_eq!(found.services[2].image.as_deref(), Some("ubuntu/24.04"));
        assert_eq!(*docker.calls.lock().unwrap(), vec![vec!["ps", "-a", "--no-trunc", "--format", "{{json .}}"].into_iter().map(String::from).collect::<Vec<_>>()]);
        assert_eq!(*incus.calls.lock().unwrap(), vec![vec!["list", "--format", "json"].into_iter().map(String::from).collect::<Vec<_>>()]);
    }

    #[test]
    fn missing_runtimes_are_omitted_and_query_failures_are_bounded_warnings() {
        assert_eq!(ExternalServices::empty().discover(), Discovery::default());
        let long = format!("  query failed\n{}", "x".repeat(400));
        let docker = FakeRunner::new(vec![Err(EngineError::Failed(long))]);
        let found = ExternalServices::with_runners(Some(docker.clone()), None).discover();
        assert!(found.services.is_empty());
        assert_eq!(found.warnings.len(), 1);
        assert_eq!(found.warnings[0].runtime, Runtime::Docker);
        assert!(found.warnings[0].message.starts_with("query failed"));
        assert!(found.warnings[0].message.len() <= MAX_ERROR_BYTES);
        assert_eq!(docker.calls.lock().unwrap().len(), 1, "discovery only lists; it never probes or starts a daemon");
    }

    #[test]
    fn actions_resolve_fresh_targets_and_use_exact_fixed_argv() {
        for action in [ExternalAction::Start, ExternalAction::Stop, ExternalAction::Restart] {
            let docker = FakeRunner::new(vec![Ok(docker_line("abc123", "web", "exited")), Ok(String::new())]);
            let services = ExternalServices::with_runners(Some(docker.clone()), None);
            let target = services.resolve("docker:abc123").unwrap();
            services.execute(&target, action).unwrap();
            assert_eq!(docker.calls.lock().unwrap()[1], vec![action.verb().to_string(), "abc123".to_string()]);
        }
        let incus = FakeRunner::new(vec![Ok(json!([{"name":"native-name","type":"container","status":"Stopped","config":{}}]).to_string()), Ok(String::new())]);
        let services = ExternalServices::with_runners(None, Some(incus.clone()));
        let target = services.resolve("incus:native-name").unwrap();
        services.execute(&target, ExternalAction::Restart).unwrap();
        assert_eq!(incus.calls.lock().unwrap()[1], vec!["restart", "native-name"]);
    }

    #[test]
    fn unknown_ids_do_not_mutate_anything() {
        let docker = FakeRunner::new(vec![Ok(docker_line("known", "web", "running"))]);
        let services = ExternalServices::with_runners(Some(docker.clone()), None);
        assert_eq!(services.resolve("docker:unknown"), Err(EngineError::NotFound));
        assert_eq!(docker.calls.lock().unwrap().len(), 1);
    }

    fn service_with(services: ExternalServices) -> Arc<crate::service::Service> {
        let (_, service) = machine();
        let service = Arc::try_unwrap(service).ok().unwrap().with_external_services(services);
        Arc::new(service)
    }

    #[tokio::test]
    async fn routes_list_services_and_reject_unknown_targets() {
        let docker = FakeRunner::new(vec![Ok(docker_line("abc", "web", "running")), Ok(docker_line("abc", "web", "running"))]);
        let service = service_with(ExternalServices::with_runners(Some(docker), None));
        let (status, answer) = send(&service, "GET", "/v1/external-services", "", TOKEN).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(answer["services"][0]["id"], "docker:abc");
        assert_eq!(answer["warnings"], json!([]));
        let (status, _) = send(&service, "POST", "/v1/external-services/docker:missing/start", "", TOKEN).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        let (status, _) = send(&service, "GET", "/v1/external-services", "", "wrong").await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn failed_commands_keep_the_real_bounded_error_and_are_idempotent() {
        let docker = FakeRunner::new(vec![Ok(docker_line("abc", "web", "running")), Err(EngineError::Failed("permission denied\nby daemon".into()))]);
        let service = service_with(ExternalServices::with_runners(Some(docker.clone()), None));
        let command = service.change_external("external-command", "docker:abc", ExternalAction::Restart).await.unwrap();
        assert_eq!(command.kind, CommandType::Restart);
        assert_eq!(command.state, CommandState::Failed);
        assert_eq!(command.workload_id, None);
        assert_eq!(command.result.as_ref().unwrap().get("error").map(String::as_str), Some("permission denied by daemon"));
        let repeated = service.change_external("external-command", "docker:abc", ExternalAction::Restart).await.unwrap();
        assert_eq!(repeated, command);
        assert_eq!(docker.calls.lock().unwrap().len(), 2);
    }
}

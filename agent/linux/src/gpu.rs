//! Can containers use this machine's GPU? Incus' `nvidia.runtime=true` needs NVIDIA's container toolkit on the host,
//! so a GPU alone is not enough. This looks for the toolkit (fixed program names, fixed arguments, never a shell) and
//! turns "no" into a plain sentence instead of a raw Incus error.
use crate::models::{Capabilities, GpuMode, Kind, Refusal};
use crate::preflight::HostProbe;
use crate::validate::CreateRequest;

/// The toolkit's programs and the one argument that makes each print its version and exit.
const TOOLKIT_PROGRAMS: [(&str, &str); 2] = [("nvidia-ctk", "--version"), ("nvidia-container-cli", "--version")];

pub const NO_TOOLKIT_MESSAGE: &str = "This machine has an NVIDIA GPU but not the NVIDIA container toolkit, so containers cannot use it yet. Install the toolkit on the machine first.";
pub const NO_GPU_MESSAGE: &str = "This machine has no NVIDIA GPU to share with a container.";

/// True when one of the toolkit's programs runs and succeeds.
pub fn toolkit_ready(probe: &dyn HostProbe) -> bool {
    TOOLKIT_PROGRAMS.iter().any(|(program, argument)| probe.run(program, &[argument]).is_some_and(|answer| answer.success))
}

/// Why a container that asks to share the GPU cannot be made here, in plain words. None when the request does not need the GPU or can have it.
pub fn refusal(request: &CreateRequest, gpu_found: bool, capabilities: &Capabilities) -> Option<Refusal> {
    let wants_gpu_container = request.gpu_mode == GpuMode::Container && request.kind == Kind::Container;
    if !wants_gpu_container || capabilities.gpu_in_container {
        return None;
    }
    let message = if gpu_found { NO_TOOLKIT_MESSAGE } else { NO_GPU_MESSAGE };
    Some(Refusal { code: "missing_capability", message: message.to_string(), resource: "capability", needed: 1, free: 0 })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::preflight::ProbeOutput;

    struct Answers(Vec<(&'static str, bool)>);

    impl HostProbe for Answers {
        fn run(&self, program: &str, arguments: &[&str]) -> Option<ProbeOutput> {
            assert_eq!(arguments, ["--version"], "only the fixed argument is ever passed");
            self.0.iter().find(|(name, _)| *name == program).map(|(_, success)| ProbeOutput { success: *success, stdout: String::new(), stderr: String::new() })
        }
    }

    fn request(kind: Kind, gpu_mode: GpuMode) -> CreateRequest {
        CreateRequest { command_id: "c".into(), name: "n".into(), kind, cpu: 1, ram_mb: 512, disk_gb: 1, gpu_mode, image: None, gpu_memory_gb: None }
    }

    fn capabilities(gpu_in_container: bool) -> Capabilities {
        Capabilities { vm: false, container: true, gpu_in_vm: false, gpu_in_container }
    }

    #[test]
    fn either_toolkit_program_that_runs_counts() {
        assert!(toolkit_ready(&Answers(vec![("nvidia-ctk", true)])));
        assert!(toolkit_ready(&Answers(vec![("nvidia-ctk", false), ("nvidia-container-cli", true)])));
    }

    #[test]
    fn a_missing_or_broken_toolkit_does_not_count() {
        assert!(!toolkit_ready(&Answers(vec![])));
        assert!(!toolkit_ready(&Answers(vec![("nvidia-ctk", false), ("nvidia-container-cli", false)])));
    }

    #[test]
    fn a_gpu_container_without_the_toolkit_is_refused_by_name() {
        let refused = refusal(&request(Kind::Container, GpuMode::Container), true, &capabilities(false)).expect("refused");
        assert_eq!((refused.code, refused.message.as_str()), ("missing_capability", NO_TOOLKIT_MESSAGE));
        assert!(refused.message.contains("NVIDIA container toolkit") && !refused.message.to_lowercase().contains("incus"));
    }

    #[test]
    fn a_gpu_container_on_a_machine_without_a_gpu_says_so() {
        let refused = refusal(&request(Kind::Container, GpuMode::Container), false, &capabilities(false)).expect("refused");
        assert_eq!(refused.message, NO_GPU_MESSAGE);
    }

    #[test]
    fn everything_else_is_left_to_the_budget_checks() {
        assert!(refusal(&request(Kind::Container, GpuMode::Container), true, &capabilities(true)).is_none());
        assert!(refusal(&request(Kind::Container, GpuMode::None), true, &capabilities(false)).is_none());
        assert!(refusal(&request(Kind::Vm, GpuMode::Container), true, &capabilities(false)).is_none());
        assert!(refusal(&request(Kind::Vm, GpuMode::Passthrough), true, &capabilities(false)).is_none());
    }
}

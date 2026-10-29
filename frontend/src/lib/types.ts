// The shapes the control panel's API sends, as far as the panel reads them. A field the panel never reads is not listed.

export type MachineState = 'online' | 'busy' | 'offline'
export type WorkloadKind = 'vm' | 'container'
/** What the panel can ask for on a VM. Delete asks for confirmation first. */
export type WorkloadAction = 'start' | 'stop' | 'delete'

export interface Gpu {
  vendor: string
  model: string
  /** The card's own memory; left out for a GPU that uses the machine's memory, and by older helpers. */
  memory_mb?: number | null
  /** The details below are left out by a helper that does not say them (an older one, the macOS helper, an old NVIDIA driver). */
  architecture?: string | null
  compute_capability?: string | null
  driver_version?: string | null
  max_clock_mhz?: number | null
  /** True when the GPU has no memory of its own and works in the machine's memory (a DGX Spark). */
  uses_system_memory?: boolean | null
}

/** Something on a machine that stops it from running workloads, with the way to fix it. */
export interface Problem {
  code: string
  message: string
  fix: string
}

export interface Capabilities {
  vm: boolean
  container: boolean
  gpu_in_vm: boolean
  gpu_in_container: boolean
  /** True when the helper can limit a container's GPU memory; false or left out for an older helper. */
  gpu_memory_limit?: boolean
  /** The CPU models a VM can be given, `host` first; left out when the helper offers only the machine's own CPU. */
  cpu_models?: string[]
  /** True when a VM can be given more than one socket. */
  cpu_topology?: boolean
  /** The CPU flags a VM can have switched on or off. */
  cpu_flags?: string[]
  /** True when a container can get a hard cap on its CPU time. */
  cpu_limit?: boolean
  /** True when the helper serves the web terminal; left out by an older helper (a Mac is still allowed by its system). */
  terminal?: boolean
  /** True when the helper can run sandboxes right now; left out by an older helper, and read as false. */
  sandbox?: boolean
}

/** The CPU flags the Create VM window can switch, as the helpers name them. */
export type CpuFlagId = 'nested-virt' | 'aes'

/** What the Add machine form saved for a machine. */
export interface MachineSettings {
  profile: string
  labels: string[]
  notes: string | null
  ram_reserve_mb: number | null
  disk_reserve_gb: number | null
  ram_allowance_mb: number | null
  disk_allowance_gb: number | null
  allow_gpu: boolean
  vm_cpu: number | null
  vm_ram_mb: number | null
  vm_disk_gb: number | null
  vm_image: string | null
  vm_max_running: number | null
  subdomain: string | null
  public_chat: boolean
  ai_model: string | null
  /** user@host[:port] the ssh command goes through; null uses the machine's office address. */
  ssh_jump: string | null
}

/** The app (OpenClaw or Hermes) the parent installs inside a VM after it starts, as the machine list reports it. */
export interface WorkloadApp {
  name: string
  state: 'installing' | 'ready' | 'failed'
  message: string | null
}

export type ExternalRuntime = 'docker' | 'incus' | 'apple'
export type ExternalServiceState = 'running' | 'stopped' | 'unknown'
export type ExternalServiceAction = 'start' | 'stop' | 'restart'

/** A container or VM that already exists outside MetaService's managed workloads. */
export interface ExternalService {
  id: string
  name: string
  runtime: ExternalRuntime
  kind: WorkloadKind
  state: ExternalServiceState
  image: string | null
}

export interface ExternalWarning {
  runtime: ExternalRuntime
  message: string
}

export interface ExternalServicesReply {
  services: ExternalService[]
  warnings: ExternalWarning[]
}

export interface Workload {
  id: string
  name: string
  kind: WorkloadKind
  state: string
  cpu: number
  ram_mb: number
  disk_gb: number
  /** Whether the GPU was given to it: `container` shares the machine's GPU. Older answers may leave it out. */
  gpu_mode?: 'none' | 'container' | 'passthrough'
  address?: string | null
  bundle_version?: string | null
  /** Only on a VM that stopped by itself: why, as the machine reported it. Null otherwise. Text from inside the VM: read it with `readStoppedReason`, never trust its shape. */
  stopped_reason?: unknown
  /** The GPU memory limit booked for this VM, in GB; null or left out when it has none. Read it with `readGpuMemoryGb`. */
  gpu_memory_gb?: unknown
  /** How the VM came up: with systemd, or plain (no systemd). Null when the machine does not say. */
  init_mode?: 'systemd' | 'plain' | null
  /** The app being installed in, or installed in, the VM. Null or left out when there is none. */
  app?: WorkloadApp | null
}

/** What a machine's helper can offer for sandboxes, as the machine reports it. Null or left out when it does not say, or says it cannot run any. */
export interface SandboxFacts {
  /** The program that runs the sandboxes; `version` is null when it could not tell. */
  engine: {
    name: 'firecracker'
    version: string | null
  }
  /** How many sandboxes may run at once on this machine. */
  max_running: number
  running: number
  paused: number
  /** The most one sandbox may have here. */
  max_vcpu: number
  max_ram_mb: number
  max_disk_mb: number
  /** What the sandboxes hold: vCPU and memory of the running ones, disk of all of them (paused ones included). */
  booked: {
    vcpu: number
    ram_mb: number
    disk_mb: number
  }
  /** The templates built on this machine, and whether a sandbox can be made from each. */
  templates: {
    id: string
    build: string
    ready: boolean
  }[]
  /** The number of the last sandbox event on this machine. */
  changes: number
}

/** The program a machine uses to make VMs, as the helper reports it. `version` is null when the engine could not tell. */
export interface Engine {
  name: string
  version: string | null
  ready: boolean
}

/**
 * Ruvio (the chat) on one machine. `unavailable`: nothing is pinned on the parent and nothing is installed, so it cannot be turned on
 * (turning it on answers 409 `no_chat_built` when no chat is built, `no_bundle_pinned` when several are built and none is pinned).
 * `off`: not installed. `on`: the pinned version runs. `outdated`: another version than the pinned one runs.
 * `installing` and `removing`: a command is going.
 */
export type RuvioState = 'unavailable' | 'off' | 'on' | 'outdated' | 'installing' | 'removing'

export interface Ruvio {
  installed: string | null
  pinned: string | null
  state: RuvioState
}

/** Whether the parent can replace a machine's helper program with a different one, as GET /api/machines says it. */
export interface HelperUpdateInfo {
  available: boolean
  /** The build (SHA-256) the helper reported; null for an older helper that does not say. */
  current_build: string | null
  /** The build the parent can put there; null when it has none for this kind of computer. */
  newest_build: string | null
  /** Why there is nothing to offer, in plain words. */
  reason: string | null
}

/** The answer of POST /api/machines/{id}/update-helper. */
export interface HelperUpdateResult {
  result: 'updated' | 'rolled_back' | 'failed'
  message: string
}

export interface Machine {
  id: string
  name: string
  state: MachineState
  os: string
  arch: string
  ip?: string
  cpu_cores?: number | null
  /** The CPU's name as the helper reports it (cleaned by the parent); null or left out for a helper that does not say. */
  cpu_model?: string | null
  /** What the machine is made of (the computer, each kind of CPU core, the drives); null or left out for a helper that does not say. Read it with `readHardware`. */
  hardware?: unknown
  ram_total_mb?: number | null
  disk_total_gb?: number | null
  free_ram_mb?: number | null
  free_disk_gb?: number | null
  gpu: Gpu[]
  capabilities?: Capabilities
  /** The card's memory booked for VMs; null or left out unless the machine has an NVIDIA card it can share. Read it with `readGpuBooking`. */
  gpu_booking?: unknown
  last_seen?: string | null
  bundle_version?: string | null
  problems?: Problem[]
  settings?: Partial<MachineSettings>
  workloads: Workload[]
  /** The helper's version; null until the helper reports it. */
  agent_version?: string | null
  /** The SHA-256 of the helper's program file; null until the helper reports it (an older helper never does). */
  agent_build?: string | null
  /** Whether a different helper program is on offer for this machine. */
  update?: HelperUpdateInfo
  /** Null until the helper reports it. */
  engine?: Engine | null
  /** What the helper can offer for sandboxes; null or left out when it does not say, or says it cannot run any. */
  sandbox?: SandboxFacts | null
  /** Only in GET /api/machines/{id}. The helper's folder on the machine; null when the parent did not install it over SSH. */
  box?: string | null
  /** Only in GET /api/machines/{id}. The helper's port on the machine; null when the parent did not install it over SSH. */
  agent_port?: number | null
  /** Only in GET /api/machines/{id}. Null until the machine has reported once. */
  ruvio?: Ruvio | null
}

/**
 * The body of PATCH /api/machines/{id}/settings. Send only what changes. A listed field set to null is cleared
 * (the ones that can be cleared); a field not listed here is refused with a 400. The answer is the machine, as GET gives it.
 */
export interface MachineSettingsPatch {
  name?: string
  labels?: string[]
  notes?: string
  allow_gpu?: boolean
  ram_reserve_mb?: number | null
  disk_reserve_gb?: number | null
  ram_allowance_mb?: number | null
  disk_allowance_gb?: number | null
  vm_max_running?: number | null
  vm_cpu?: number | null
  vm_ram_mb?: number | null
  vm_disk_gb?: number | null
  vm_image?: string | null
  subdomain?: string | null
  ai_model?: string | null
  ssh_jump?: string | null
}

export interface CommandResult {
  error?: string
  backup_id?: string
  /** Set by a create order that succeeded: the id the machine gave the new VM. */
  workload_id?: string
}

/** One order the Root gave an Agent (create, start, stop, delete) and how it ended. */
export interface Command {
  id: string
  type: string
  machine: string
  workload_id?: string | null
  state: 'queued' | 'running' | 'succeeded' | 'failed' | string
  created_at: string
  params: Record<string, unknown>
  result?: CommandResult | null
  finished_at?: string | null
}

/** One row of the AI use per machine (and per VM). */
export interface UsageRow {
  machine: string
  workload?: string | null
  requests: number
  prompt_tokens: number
  completion_tokens: number
}

/** A computer found on the network by Find machines. */
export interface Device {
  id: string
  hostname?: string | null
  ip: string
  mac?: string | null
  vendor?: string | null
  seen_by?: string[]
  agent_port_open?: boolean
  machine?: string | null
}

export type ScanSourceResult = string

export interface Scan {
  id: string
  state: string
  finished_at?: string | null
  results: Device[]
  sources: Record<string, ScanSourceResult>
}

export interface Requirement {
  id: string
  label: string
  ok: boolean
  detail: string
  /** What to do by hand: a cross always has one; a tick has one only when it still has something worth doing (full VMs on a containers-only computer). */
  fix?: string
  /** Present when the parent can install it itself: which part, and whether sudo on that computer asks for a password. */
  install?: InstallOffer
}

export interface InstallOffer {
  part: string
  needs_password: boolean
}

export interface ComputerInfo {
  name: string
  os: string
  arch: string
  cpu_cores: number
  ram_mb: number
  disk_gb: number
}

export type StepState = 'pending' | 'running' | 'done' | 'failed'

export interface InstallStep {
  id: string
  label: string
  state: StepState
  detail?: string | null
}

export interface InstallJob {
  id: string
  name: string
  state: 'running' | 'done' | 'failed'
  steps: InstallStep[]
  error?: string | null
  warning?: string | null
}

export interface Bundle {
  pinned?: boolean
  version: string
  platform: string
  sha256: string
  size: number
}

export interface BundleOverview {
  bundles: Bundle[]
  pinned: string | null
  previous?: string | null
}

/** The numbers behind a refusal for lack of room. */
export interface RefusalNumbers {
  needed: number
  free: number
  unit: string
}

export interface AuthStatus {
  configured: boolean
  /** The shortest admin password the server accepts: 8, or 12 when the panel is public (https). */
  min_password_length?: number
}

export interface Session {
  username: string
  csrf_token: string
}

/** What the Find machines page needs to know before a scan. */
export interface ScanSetup {
  subnet?: string | null
  router_configured: boolean
  nmap_available: boolean
  /** The router's address when it is on the scanned network; it is not a machine to add. */
  gateway?: string | null
  /** This computer's own addresses on the scanned network; it runs MetaService, so it is not a machine to add. */
  own_addresses?: string[]
}

export interface BrainStatus {
  configured: boolean
  model?: string
  host?: string
  max_tokens?: number
  usage: UsageRow[]
}

/** A number typed into a form: a number, the text of one, or empty. */
export type FormNumber = number | string | null | undefined

/** The New VM form's fields. */
export interface WorkloadForm {
  name: string
  kind: string
  cpu: FormNumber
  ramGb: FormNumber
  diskGb: FormNumber
  machine?: string
  /** `container` (the whole card, no limit) or `shared` (a limit on its memory) when the person chose the GPU; left out or `none` otherwise. */
  gpuMode?: string
  /** The GB of GPU memory typed for a shared partition (a number or its text); undefined until the choice is made. */
  gpuMemoryGb?: FormNumber
  /** The catalog id of the image to start from (`blank` when none is picked); sent only when it is not `blank`. */
  bundle?: string
  /** VMs: the sockets the CPUs are spread over (cores per socket = cpu / sockets); 1 or undefined is the engine's own layout. */
  cpuSockets?: FormNumber
  /** VMs: the CPU model; undefined or `host` is the machine's own CPU. */
  cpuType?: string | undefined
  /** VMs: the flags switched on or off; a flag left out keeps what the CPU model gives. */
  cpuFlags?: Partial<Record<CpuFlagId, 'on' | 'off'>> | undefined
  /** Containers: the hard cap on CPU time, in cores (1.5 is one and a half); empty for no cap. */
  cpuLimit?: FormNumber
}

/** Step one of Connect: the SSH host key a computer shows, to confirm before any login. */
export interface ProbeResult {
  host: string
  address: string
  key_type: string
  fingerprint: string
  trusted: boolean
  /** The logins that computer accepts (ssh's names: publickey, password...). Missing when it did not say. */
  login_methods?: string[] | null
}

/** Step two of Connect: what the computer is, and whether MetaService can be installed there. */
export interface VerifyResult {
  host: string
  fingerprint: string
  facts: { os: string; arch: string; version: string; chip: string; user: string; home: string; computer_name?: string; cpu_cores: number | null; ram_mb: number | null; disk_free_gb: number | null }
  requirements: Requirement[]
  can_add: boolean
  isolation: string[]
  system: string
}

/** The Connect form's fields. */
export interface ConnectForm {
  host: string
  port: string
  user: string
  password: string
  useKey: boolean
  /** Set when the login is for a machine that is already added: the parent reads its address and host key from the machine's own record. */
  machineId?: string
}

/** "What will change": the install plan for another computer, before anything is done. */
export interface PlanPreview {
  box: string
  level: string
  steps: { id: string; label: string; changes: string[] }[]
  notes: string[]
}

/** A machine that was installed over SSH, as the panel lists them. */
export interface RemoteMachineInfo {
  machine: string
  host: string
  ssh_port: number
  ssh_user: string
  level: string
  box: string
  agent_port: number
  engine: string
  has_key: boolean
  /** Absent when the machine has no tunnel (it only reports in). */
  tunnel?: { state: 'connecting' | 'connected' | 'disconnected'; since: string; local_port: number | null; failures: number }
}


/** One reading of a machine, as GET /api/machines/{id}/stats carries it (docs/monitor-contract.md). A number the machine could not give yet is null, never 0. */
export interface StatsCpu {
  /** Logical CPUs (threads). */
  core_count: number
  total_percent: number | null
  cores_percent: number[] | null
  load: { one: number | null; five: number | null; fifteen: number | null }
  /** The next six are left out by a helper that does not know them (an older helper, or a system that does not say). */
  physical_cores?: number
  /** For each logical CPU, the index of its physical core. */
  core_of?: number[]
  /** Apple Silicon: the groups the system names. */
  clusters?: StatsCluster[]
  breakdown?: StatsBreakdown
  frequency_mhz?: { average: number; max: number }
  temperature_celsius?: number
}

export interface StatsCluster {
  name: string
  logical: number
}

/** Percent of the last interval in each CPU state. A Mac gives user, system, nice and idle only. */
export interface StatsBreakdown {
  user?: number
  system?: number
  nice?: number
  idle?: number
  iowait?: number
  irq?: number
  softirq?: number
  steal?: number
}

export interface StatsMemory {
  total_bytes: number
  used_bytes: number
  cached_bytes: number
  free_bytes: number
  swap_total_bytes: number
  swap_used_bytes: number
}

export interface StatsDisk {
  mount: string
  name: string
  fs: string
  total_bytes: number
  used_bytes: number
  free_bytes: number
}

export interface StatsNetwork {
  received_total_bytes: number
  sent_total_bytes: number
  received_bytes_per_second: number | null
  sent_bytes_per_second: number | null
  /** Running totals since boot. A Mac counts drops on the way in only. */
  errors_in_total?: number
  errors_out_total?: number
  drops_in_total?: number
  drops_out_total?: number
}

export type GpuVendor = 'nvidia' | 'amd' | 'apple' | 'intel' | 'unknown'

/** A program holding GPU memory (NVIDIA only). */
export interface StatsGpuProgram {
  name: string
  memory_bytes: number
}

/** One GPU. A number the machine cannot read is null (or, for the optional ones, left out), never 0. */
export interface StatsGpu {
  name: string
  utilization_percent: number | null
  memory_used_bytes: number | null
  memory_total_bytes: number | null
  temperature_celsius: number | null
  vendor?: GpuVendor
  power_watts?: number
  power_limit_watts?: number
  fan_percent?: number
  clock_mhz?: number
  processes?: StatsGpuProgram[]
}

/** One GPU's numbers in a history point; `index` is its place in the reading's gpus list. */
export interface StatsHistoryGpu {
  index: number
  utilization_percent?: number
  memory_used_bytes?: number
  temperature_celsius?: number
  power_watts?: number
}

export interface StatsProcess {
  pid: number
  name: string
  user: string
  cpu_percent: number | null
  memory_bytes: number
  threads?: number
}

export interface MachineStats {
  taken_at: string
  measuring: boolean
  uptime_seconds: number
  cpu: StatsCpu
  memory: StatsMemory
  disks: StatsDisk[]
  network: StatsNetwork
  /** Left out when the helper gives no disk speed. */
  disk_io?: { read_bytes_per_second: number; write_bytes_per_second: number }
  /** How many programs run in all; the list holds only the busiest. */
  process_count?: number
  /** Left out when the machine cannot say. */
  gpus: StatsGpu[]
  processes: StatsProcess[]
}

/** One reading the parent kept (GET /api/machines/{id}/stats/history). Optional numbers are left out when the helper did not give them. */
export interface StatsHistoryPoint {
  /** Seconds since 1970. */
  t: number
  cpu_percent: number
  cpu_breakdown?: StatsBreakdown
  load?: [number, number, number]
  mem_used: number
  mem_cached: number
  mem_total: number
  swap_used: number
  swap_total: number
  disk_read?: number
  disk_write?: number
  net_in_bps: number | null
  net_out_bps: number | null
  /** Left out when the machine has no GPU with a number. */
  gpus?: StatsHistoryGpu[]
  net_drops?: number
  processes_count?: number
}

export interface StatsHistoryReply {
  interval_seconds: number
  points: StatsHistoryPoint[]
}

/** One public key allowed to log in to a VM. `added_at` is Unix seconds. */
export interface SshKey {
  id: string
  type: string
  fingerprint: string
  comment: string
  added_at: number
}

/** Whether an SSH server was found inside the VM: `unknown` means it never reported. */
export type SshdState = 'running' | 'installed' | 'missing' | 'unknown'

/** Where the SSH server inside the VM is: idle (nothing going on), installing (the helper is setting it up) or failed (see the message). */
export type SshdProgress = 'idle' | 'installing' | 'failed'

/** How to log in to the VM from outside: the jump host, whether it is the machine's own office address, and the ready-to-paste command. */
export interface SshConnect {
  jump: string | null
  jumpIsDefault: boolean
  vmAddress: string | null
  command: string | null
}

/**
 * The answer of every SSH-keys call. `applied` false means the list is saved but not written into the VM yet.
 * `connect` is null when the parent is old and does not send it; then only the old plain line can be shown.
 */
export interface SshKeyList {
  keys: SshKey[]
  applied: boolean
  sshd: SshdState
  sshdState: SshdProgress
  sshdMessage: string | null
  connect: SshConnect | null
}

export interface MachineStatsReply {
  /** old_helper: the machine is online but its helper does not answer the stats route yet (stats is null). */
  state: 'online' | 'offline' | 'old_helper'
  last_seen: string | null
  fetched_at: string | null
  stats: MachineStats | null
}

/** A sandbox API key as the panel lists it. The key text itself is never listed: it is shown once, when it is made. */
export interface SandboxKey {
  id: string
  team: string
  team_name: string
  /** `msb_ab12cd34`: enough to tell two keys apart, never enough to call the API. */
  prefix: string
  created_at: string
  last_used_at: string | null
  revoked_at: string | null
}

/** The one answer that carries a key's text. It cannot be asked for again. */
export interface SandboxKeyMade {
  id: string
  team: string
  team_name: string
  prefix: string
  key: string
  created_at: string
}

/** One sandbox that is still alive, as the live list shows it. */
export interface SandboxLive {
  id: string
  team: string
  team_name: string
  machine: string
  state: string
  template: string
  vcpu: number
  ram_mb: number
  disk_mb: number
  created_at: string
  end_at: string
}

/** One team's finished sandbox runs inside the usage window. */
export interface SandboxUsageTeam {
  team: string
  team_name: string
  sandboxes: number
  seconds: number
  vcpu_seconds: number
  ram_mb_seconds: number
}

/** What each team used in the window the panel asked for. */
export interface SandboxUsageReply {
  days: number
  starts_at: string
  ends_at: string
  teams: SandboxUsageTeam[]
}

/** What a tile of the Storage tab is: disktree's kinds of data, plus the folders VMs and containers live in. */
export type StorageKind = 'code' | 'agent' | 'toolchain' | 'synced' | 'git' | 'media' | 'documents' | 'cache' | 'vms' | 'other'
/** Why a folder's space could be had back (disktree's reasons). The panel only shows it; nothing is ever deleted from here. */
export type StorageReclaim = 'regenerable' | 'sync_history' | 'package_store' | 'build_output' | 'reinstallable' | 'sandbox_layers' | 'snapshots' | 'trash' | 'temporary'

/** One entry of a storage map. `parent` is the place of its folder in the list (-1 for the first); a `rest` is a folder's smaller entries added together. */
export interface StorageNode {
  parent: number
  name: string
  type: 'dir' | 'file' | 'rest'
  bytes: number
  files: number
  items: number
  kind: StorageKind
  reclaim: StorageReclaim | null
  modified: number | null
}

export interface StorageMap {
  root: string
  finished_at: string
  seconds: number
  entries: number
  unreadable: number
  disk: { total_bytes: number; used_bytes: number; free_bytes: number }
  nodes: StorageNode[]
}

export interface Storage {
  scanning: boolean
  progress: { entries: number; bytes: number } | null
  error: string | null
  map: StorageMap | null
}

/** GET /api/machines/{id}/storage and POST .../storage/scan. */
export interface MachineStorageReply {
  state: 'online' | 'offline' | 'old_helper'
  storage: Storage | null
}

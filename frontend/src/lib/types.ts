// The shapes the control panel's API sends, as far as the panel reads them. A field the panel never reads is not listed.

export type MachineState = 'online' | 'busy' | 'offline'
export type WorkloadKind = 'vm' | 'container'
/** What the panel can ask for on a VM. Delete asks for confirmation first. */
export type WorkloadAction = 'start' | 'stop' | 'delete'

export interface Gpu {
  vendor: string
  model: string
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
}

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
}

export interface Workload {
  id: string
  name: string
  kind: WorkloadKind
  state: string
  cpu: number
  ram_mb: number
  disk_gb: number
  address?: string | null
  bundle_version?: string | null
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

export interface Machine {
  id: string
  name: string
  state: MachineState
  os: string
  arch: string
  ip?: string
  cpu_cores?: number | null
  ram_total_mb?: number | null
  disk_total_gb?: number | null
  free_ram_mb?: number | null
  free_disk_gb?: number | null
  gpu: Gpu[]
  capabilities?: Capabilities
  last_seen?: string | null
  bundle_version?: string | null
  problems?: Problem[]
  settings?: Partial<MachineSettings>
  workloads: Workload[]
  /** The helper's version; null until the helper reports it. */
  agent_version?: string | null
  /** Null until the helper reports it. */
  engine?: Engine | null
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
}

export interface CommandResult {
  error?: string
  backup_id?: string
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
  optional: boolean
  detail: string
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


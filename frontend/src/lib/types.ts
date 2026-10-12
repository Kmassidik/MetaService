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

/** What the Add machine form is filled with before anything is typed. */
export interface InstallDefaults {
  name: string
  ram_reserve_mb: number
  disk_reserve_gb: number
  agent_ready: boolean
  chat_available: boolean
  profile: string
  computer: ComputerInfo
  ai_model?: string
  vm_cpu: number
  vm_ram_mb: number
  vm_disk_gb: number
  requirements: Requirement[]
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
}

/** A one-time token for a machine added from a scan. */
export interface Invite {
  name: string
  ip?: string | null
  enrollment_token: string
  expires_at?: string
  command?: string
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

/** The Add machine form's fields. */
export interface InstallForm {
  name: string
  profile: string
  labels: string
  notes: string
  chat: boolean
  ramReserveMb: FormNumber
  diskReserveGb: FormNumber
  ramAllowanceMb: FormNumber
  diskAllowanceGb: FormNumber
  allowGpu: boolean
  vmCpu: FormNumber
  vmRamMb: FormNumber
  vmDiskGb: FormNumber
  vmImage: string
  vmMaxRunning: FormNumber
  subdomain: string
  publicChat: boolean
  aiModel: string
}

/** The New VM form's fields. */
export interface WorkloadForm {
  name: string
  kind: string
  cpu: FormNumber
  ramGb: FormNumber
  diskGb: FormNumber
  machine?: string
}

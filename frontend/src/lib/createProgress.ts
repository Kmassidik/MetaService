// The progress window shown after Create: which step of making a VM is going, from the parent's create order and the machine's list of VMs (and the app inside the VM, when one was chosen).
// Pure functions, no DOM, no network, no clock: the page asks again by itself and these read whatever the newest answers say.
import { appLogoName, appTitle } from './appInstall.ts'
import type { LogoName } from './logos.ts'
import { reasonText } from './pendingVms.ts'
import { readStoppedReason } from './stoppedReason.ts'
import type { Command, Machine, Workload, WorkloadKind } from './types.ts'

export type StepId = 'waiting' | 'creating' | 'starting' | 'app'
export type StepState = 'done' | 'now' | 'next' | 'failed'
export type ProgressStatus = 'working' | 'ready' | 'failed'

export interface ProgressStep {
  id: StepId
  label: string
  state: StepState
}

export interface CreateProgress {
  status: ProgressStatus
  steps: ProgressStep[]
  /** Why the failing step failed, in plain words. Null unless the status is `failed`. */
  reason: string | null
}

/** Who and where, for the top of the window. */
export interface ProgressHeader {
  name: string
  machineId: string
  machineName: string
  kind: WorkloadKind
  /** The app chosen for the VM (`openclaw`, `hermes`); null when none. */
  app: string | null
  logo: LogoName | null
  /** The new VM's id once the machine or the order knows it. */
  workloadId: string | null
}

export interface ProgressView {
  progress: CreateProgress
  header: ProgressHeader
}

interface Outcome {
  state: Exclude<StepState, 'next'>
  reason?: string
}

interface Context {
  order: Command | undefined
  workload: Workload | null
}

const STEP_LABELS: Record<Exclude<StepId, 'app'>, string> = { waiting: 'Waiting for the machine', creating: 'Creating', starting: 'Starting' }
const MAKING_STATES = new Set(['provisioning', 'creating', 'starting'])
const RUNNING = 'running'
const UNNAMED = 'new VM'
const APP_PARAM = 'app'
const KIND_PARAM = 'kind'
const CONTAINER_KIND: WorkloadKind = 'container'
const STOPPED_TEXT = 'The VM was made but stopped right after it started.'
const APP_FAILED_TEXT = 'The app could not be installed.'

const NOW: Outcome = { state: 'now' }
const DONE: Outcome = { state: 'done' }

const isText = (value: unknown): value is string => typeof value === 'string' && value !== ''

/** The VM of this order on its machine: by id when the order knows it, before that by name while a VM of that name is being made. */
export function workloadOf(order: Command | undefined, machine: Machine | undefined): Workload | null {
  if (!order || !machine) return null
  const id = order.result?.workload_id
  if (isText(id)) return machine.workloads.find((workload) => workload.id === id) ?? null
  return machine.workloads.find((workload) => workload.name === order.params.name && MAKING_STATES.has(workload.state)) ?? null
}

/** The app chosen for the VM: what the order carries, else what the machine says is being installed. */
const appOf = (order: Command | undefined, workload: Workload | null): string | null => {
  const chosen = order?.params[APP_PARAM]
  return isText(chosen) ? chosen : (workload?.app?.name ?? null)
}

const waitingStep = (context: Context): Outcome => (context.order === undefined || context.order.state === 'queued' ? NOW : DONE)

function creatingStep({ order }: Context): Outcome {
  if (order?.state === 'failed') return { state: 'failed', reason: reasonText(order.result) }
  return order?.state === 'succeeded' ? DONE : NOW
}

function startingStep({ workload }: Context): Outcome {
  if (workload === null || MAKING_STATES.has(workload.state)) return NOW
  if (workload.state === RUNNING) return DONE
  const reason = readStoppedReason(workload.stopped_reason)
  const said = [reason?.message, reason?.log_tail].find(isText)
  return { state: 'failed', reason: said ?? STOPPED_TEXT }
}

function appStep({ workload }: Context): Outcome {
  const app = workload?.app
  if (app?.state === 'ready') return DONE
  if (app?.state === 'failed') return { state: 'failed', reason: app.message ?? APP_FAILED_TEXT }
  return NOW
}

const CORE_STEPS: ReadonlyArray<{ id: StepId; label: string; outcome: (context: Context) => Outcome }> = [
  { id: 'waiting', label: STEP_LABELS.waiting, outcome: waitingStep },
  { id: 'creating', label: STEP_LABELS.creating, outcome: creatingStep },
  { id: 'starting', label: STEP_LABELS.starting, outcome: startingStep },
]

/** The steps for this VM: the three of making it, and a fourth for the app when one was chosen. */
function stepsFor(app: string | null) {
  return app === null ? CORE_STEPS : [...CORE_STEPS, { id: 'app' as const, label: `Installing ${appTitle(app)}`, outcome: appStep }]
}

/** Where the VM is among the steps. Every step before the first unfinished one is done, and every step after it is waiting its turn. */
export function createProgress(order: Command | undefined, machine: Machine | undefined): CreateProgress {
  const workload = workloadOf(order, machine)
  const context: Context = { order, workload }
  const steps: ProgressStep[] = []
  let reason: string | null = null
  let blocked = false
  for (const step of stepsFor(appOf(order, workload))) {
    const outcome: Outcome | null = blocked ? null : step.outcome(context)
    steps.push({ id: step.id, label: step.label, state: outcome?.state ?? 'next' })
    blocked = blocked || outcome?.state !== 'done'
    reason = outcome?.state === 'failed' ? (outcome.reason ?? null) : reason
  }
  return { status: statusOf(steps), steps, reason }
}

function statusOf(steps: ProgressStep[]): ProgressStatus {
  if (steps.some((step) => step.state === 'failed')) return 'failed'
  return steps.every((step) => step.state === 'done') ? 'ready' : 'working'
}

/** The top of the window: the VM's name, its machine, its kind and app (for the picture), and its id once known. */
function headerFor(order: Command, machine: Machine | undefined): ProgressHeader {
  const workload = workloadOf(order, machine)
  const app = appOf(order, workload)
  const name = order.params.name
  const kind = order.params[KIND_PARAM]
  return {
    name: isText(name) ? name : UNNAMED,
    machineId: order.machine,
    machineName: machine?.name ?? order.machine,
    kind: kind === CONTAINER_KIND ? CONTAINER_KIND : 'vm',
    app,
    logo: appLogoName(app),
    workloadId: workload?.id ?? order.result?.workload_id ?? null,
  }
}

/** What the window shows for the order being watched; null when none is watched or the order is not known (yet). */
export function progressView(orders: Command[], machines: Machine[], watched: string | null): ProgressView | null {
  const order = watched === null ? undefined : orders.find((entry) => entry.id === watched)
  if (order === undefined) return null
  const machine = machines.find((entry) => entry.id === order.machine)
  return { progress: createProgress(order, machine), header: headerFor(order, machine) }
}

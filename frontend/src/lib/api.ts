// The only place that talks to the Root. Same-origin calls, cookie session, CSRF token kept in memory.
import { parseErrorDetail, type ErrorDetail } from './errorBody.ts'
import { parseUpdateResult } from './helperUpdate.ts'
import { parseMachineExtras, type MachineExtras } from './machineDetail.ts'
import { parseGpuCheck, type GpuCheckAnswer } from './gpuCheck.ts'
import { parseMachineImages, type MachineImages } from './images.ts'
import { LONG_REQUEST_TIMEOUT_MS, REQUEST_TIMEOUT_MS, TIMEOUT_MESSAGE } from './timeouts.ts'
import { parseSshKeyList } from './sshKeys.ts'
import { statsPath } from './stats.ts'
import { parseStatsReply } from './statsParse.ts'
import { parseHistoryReply } from './statsHistoryParse.ts'
import { parseTicket } from './terminal.ts'
import type { AuthStatus, BrainStatus, BundleOverview, Command, HelperUpdateResult, InstallJob, Machine, MachineSettingsPatch, MachineStatsReply, PlanPreview, StatsHistoryReply, ProbeResult, RefusalNumbers, RemoteMachineInfo, Scan, ScanSetup, Session, SshKeyList, VerifyResult, WorkloadAction } from './types.ts'

let csrfToken: string | null = null

/** The code of an ApiError for a request that got no answer in time. */
export const TIMEOUT_CODE = 'timeout'

type Method = 'GET' | 'POST' | 'PATCH' | 'DELETE'


export class ApiError extends Error {
  status: number
  code: string
  numbers?: RefusalNumbers

  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

/** One request to the Root. Returns the unchecked JSON body (null when there is none). Gives up after `timeoutMs` with the code `timeout`. */
async function send(method: Method, path: string, body?: unknown, timeoutMs = REQUEST_TIMEOUT_MS): Promise<unknown> {
  const controller = new AbortController()
  let timedOut = false
  const timer = setTimeout(() => {
    timedOut = true
    controller.abort()
  }, timeoutMs)
  try {
    return await exchange(method, path, body, controller.signal)
  } catch (error) {
    if (timedOut) throw new ApiError(0, TIMEOUT_CODE, TIMEOUT_MESSAGE)
    throw error
  } finally {
    clearTimeout(timer)
  }
}

async function exchange(method: Method, path: string, body: unknown, signal: AbortSignal, retried = false): Promise<unknown> {
  const headers: Record<string, string> = {}
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (method !== 'GET') headers['X-CSRF-Token'] = csrfToken ?? ''
  let response: Response
  try {
    response = await fetch(path, {
      method,
      headers,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      credentials: 'same-origin',
      cache: 'no-store',
      signal,
    })
  } catch {
    throw new ApiError(0, 'unreachable', 'Cannot reach the Root.')
  }
  if (response.status === 204) return null
  const data: unknown = await response.json().catch(() => null)
  // The Root makes a new CSRF token each time it starts, so a panel left open across a restart asks for the new one and tries once more.
  if (response.status === 403 && method !== 'GET' && !retried && !path.startsWith('/api/auth/')) {
    await getSession()
    return exchange(method, path, body, signal, true)
  }
  if (!response.ok) {
    const detail = parseErrorDetail(data)
    throw withNumbers(new ApiError(response.status, detail?.code ?? 'error', detail?.message ?? 'Request failed.'), detail)
  }
  return data
}

/** A call whose answer has no body (204). */
async function callNoBody(method: Method, path: string, body?: unknown, timeoutMs?: number): Promise<null> {
  await send(method, path, body, timeoutMs)
  return null
}

/** One call to the Root. The caller says what the answer looks like (T); the shape is trusted until a checking parser replaces this cast. */
async function call<T>(method: Method, path: string, body?: unknown, timeoutMs?: number): Promise<T> {
  const data = await send(method, path, body, timeoutMs)
  return data as T
}

const UNITS: Record<string, string> = { ram_mb: 'MB RAM', disk_gb: 'GB disk' }

function withNumbers(error: ApiError, detail: ErrorDetail | undefined): ApiError {
  const unit = detail?.resource ? UNITS[detail.resource] : undefined
  if (detail && unit && detail.needed !== undefined && detail.free !== undefined) {
    error.numbers = { needed: detail.needed, free: detail.free, unit }
  }
  return error
}

/** The signed-in operator's name, or null when not signed in. Also stores the session's CSRF token. */
export async function getSession(): Promise<string | null> {
  try {
    const session = await call<Session>('GET', '/api/session')
    csrfToken = session.csrf_token
    return session.username
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return null
    throw error
  }
}

export const authStatus = () => call<AuthStatus>('GET', '/api/auth/status')

/** First run: creates the admin login and signs in. */
export async function setupAdmin(username: string, password: string, confirm: string, setupToken: string): Promise<string> {
  const reply = await call<Session>('POST', '/api/auth/setup', { username, password, confirm, setup_token: setupToken })
  csrfToken = reply.csrf_token
  return reply.username
}

export async function login(username: string, password: string): Promise<string> {
  const reply = await call<Session>('POST', '/api/auth/login', { username, password })
  csrfToken = reply.csrf_token
  return reply.username
}

export const signOut = () => callNoBody('POST', '/api/auth/logout')

export const listMachines = async () => (await call<{ machines: Machine[] }>('GET', '/api/machines')).machines

/** What only one machine's own answer carries: helper version, engine, helper folder and port, and where Ruvio stands. */
export const machineExtras = async (id: string): Promise<MachineExtras> => parseMachineExtras(await call<unknown>('GET', `/api/machines/${encodeURIComponent(id)}`))
/** Changes the settings of a machine after it was added. Send only what changes; the parent refuses anything else with its reason. */
// Long: the Root sends the program over SSH and waits for the old one to stop (its own limit is 7 minutes).
export const updateHelper = async (id: string): Promise<HelperUpdateResult> => parseUpdateResult(await call<unknown>('POST', `/api/machines/${encodeURIComponent(id)}/update-helper`, undefined, LONG_REQUEST_TIMEOUT_MS))
export const updateMachineSettings = (id: string, patch: MachineSettingsPatch) => call<unknown>('PATCH', `/api/machines/${encodeURIComponent(id)}/settings`, patch)
export const removeMachine = (id: string) => callNoBody('DELETE', `/api/machines/${encodeURIComponent(id)}`)

export const scanSetup = () => call<ScanSetup>('GET', '/api/scan/setup')
export const startScan = () => call<unknown>('POST', '/api/scans')
export const latestScan = async () => (await call<{ scan: Scan | null }>('GET', '/api/scans/latest')).scan

export const createWorkload = (body: Record<string, unknown>) => call<unknown>('POST', '/api/workloads', body)

export const listCommands = async () => (await call<{ commands: Command[] }>('GET', '/api/commands?limit=15')).commands

export function workloadAction(machine: string, workload: string, action: WorkloadAction) {
  const body = action === 'delete' ? { confirm: true } : undefined
  return call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/workloads/${encodeURIComponent(workload)}/${action}`, body)
}

const sshKeysPath = (machine: string, workload: string) => `/api/machines/${encodeURIComponent(machine)}/workloads/${encodeURIComponent(workload)}/ssh-keys`

/** The SSH-keys routes answer with the whole list; an answer in another shape is an error, not an empty list. */
async function sshKeyAnswer(method: Method, path: string, body?: unknown): Promise<SshKeyList> {
  const list = parseSshKeyList(await call<unknown>(method, path, body))
  if (!list) throw new ApiError(502, 'bad_reply', 'The Root gave an answer the panel cannot read.')
  return list
}

export const listSshKeys = (machine: string, workload: string) => sshKeyAnswer('GET', sshKeysPath(machine, workload))
export const addSshKey = (machine: string, workload: string, publicKey: string) => sshKeyAnswer('POST', sshKeysPath(machine, workload), { public_key: publicKey })
export const removeSshKey = (machine: string, workload: string, keyId: string) => sshKeyAnswer('DELETE', `${sshKeysPath(machine, workload)}/${encodeURIComponent(keyId)}`)

/** The numbers behind a refusal, when the Root gave them. */
export function refusalText(error: ApiError): string {
  return error.numbers ? `${error.message}: needs ${error.numbers.needed} ${error.numbers.unit}, the best machine has ${error.numbers.free} free.` : error.message
}

export const bundleOverview = () => call<BundleOverview>('GET', '/api/bundles')
export const pinBundle = (version: string) => call<unknown>('POST', '/api/bundles/pin', { version })
export const rollbackBundle = () => call<unknown>('POST', '/api/bundles/rollback')
export const installBundle = (machine: string, workload?: string) =>
  call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/bundle/install`, workload ? { workload } : {})
/** Ruvio off: the chat stops and its data stays, so turning it on again brings the same data back. */
export const uninstallBundle = (machine: string, workload?: string) =>
  call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/bundle/uninstall`, workload ? { workload } : {})
export const chatLink = async (machine: string, workload?: string) =>
  (await call<{ url: string }>('GET', `/api/chat-link?machine=${encodeURIComponent(machine)}${workload ? `&workload=${encodeURIComponent(workload)}` : ''}`)).url

export const brainStatus = () => call<BrainStatus>('GET', '/api/brain')
export const testBrain = () => call<unknown>('POST', '/api/brain/test')

// Long on purpose: these four log in to the other computer over SSH (the Root waits up to 40 s to log in; a fix installs for minutes).
export const remoteProbe = (body: { host: string; port?: number }) => call<ProbeResult>('POST', '/api/remote/probe', body, LONG_REQUEST_TIMEOUT_MS)
export const remoteVerify = (body: Record<string, unknown>) => call<VerifyResult>('POST', '/api/remote/verify', body, LONG_REQUEST_TIMEOUT_MS)
export const remoteFix = (body: Record<string, unknown>) => call<VerifyResult>('POST', '/api/remote/fix', body, LONG_REQUEST_TIMEOUT_MS)
export const parentKey = async () => (await call<{ public_key: string }>('GET', '/api/remote/key')).public_key
export const remotePlan = (body: Record<string, unknown>) => call<PlanPreview>('POST', '/api/remote/plan', body)
export const remoteInstall = (body: Record<string, unknown>) => call<{ id: string }>('POST', '/api/remote/installs', body)
export const remoteInstallProgress = (id: string) => call<InstallJob>('GET', `/api/remote/installs/${encodeURIComponent(id)}`)
export const remoteMachines = async () => (await call<{ machines: RemoteMachineInfo[] }>('GET', '/api/remote/machines')).machines
// Long: the Root logs in over SSH to stop and clear the helper.
export const remoteRemove = (machine: string, body: Record<string, unknown>) => callNoBody('POST', `/api/remote/machines/${encodeURIComponent(machine)}/remove`, body, LONG_REQUEST_TIMEOUT_MS)

/** Asks for a one-use ticket to open the console of a running VM. The socket is opened with it; a new ticket is needed for every connection. */
export async function openTerminal(machine: string, workload: string): Promise<string> {
  const ticket = parseTicket(await call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/workloads/${encodeURIComponent(workload)}/terminal`))
  if (!ticket) throw new ApiError(502, 'bad_reply', 'The Root gave no console ticket.')
  return ticket.ticket
}

/** Looks inside one container for the GPU (read-only). Null when the parent's answer is not in the promised shape. */
export async function checkGpu(machine: string, workload: string): Promise<GpuCheckAnswer | null> {
  return parseGpuCheck(await call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/workloads/${encodeURIComponent(workload)}/gpu-check`))
}

/** The machine's latest reading (docs/monitor-contract.md). An offline machine answers with state offline and the last reading, or null. */
/** A machine's live reading. Ask `withProcesses` only while the list of programs is on screen. */
export const getMachineStats = async (id: string, withProcesses: boolean): Promise<MachineStatsReply> => parseStatsReply(await call<unknown>('GET', statsPath(id, withProcesses)))

/** The last hour of readings the parent kept for a machine, oldest first, so the charts are full when the page opens. */
export const getMachineHistory = async (id: string): Promise<StatsHistoryReply> => parseHistoryReply(await call<unknown>('GET', `/api/machines/${encodeURIComponent(id)}/stats/history`))

/** What the Create VM window may offer for one machine: the parent's catalog joined with what the machine has ready. */
export const getMachineImages = async (id: string): Promise<MachineImages> => parseMachineImages(await call<unknown>('GET', `/api/machines/${encodeURIComponent(id)}/images`))

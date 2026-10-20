// The only place that talks to the Root. Same-origin calls, cookie session, CSRF token kept in memory.
import type { AuthStatus, BrainStatus, BundleOverview, Command, InstallDefaults, InstallJob, Machine, PlanPreview, ProbeResult, RefusalNumbers, RemoteMachineInfo, Scan, ScreenInput, ScreenSession, ScanSetup, Session, VerifyResult, WorkloadAction } from './types.ts'

let csrfToken: string | null = null

type Method = 'GET' | 'POST' | 'DELETE'

/** The error object the Root sends with a refusal. */
interface ErrorBody {
  error?: { code?: string; message?: string; resource?: string; needed?: number; free?: number }
}

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

/** One call to the Root. The caller says what the answer looks like (T); an answer with no body (204) is null, so those calls are typed `null`. */
async function call<T>(method: Method, path: string, body?: unknown, retried = false): Promise<T> {
  const headers: Record<string, string> = {}
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (method !== 'GET') headers['X-CSRF-Token'] = csrfToken ?? ''
  let response: Response
  try {
    response = await fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'same-origin',
      cache: 'no-store',
    })
  } catch {
    throw new ApiError(0, 'unreachable', 'Cannot reach the Root.')
  }
  if (response.status === 204) return null as T
  const data: unknown = await response.json().catch(() => null)
  // The Root makes a new CSRF token each time it starts, so a panel left open across a restart asks for the new one and tries once more.
  if (response.status === 403 && method !== 'GET' && !retried && !path.startsWith('/api/auth/')) {
    await getSession()
    return call<T>(method, path, body, true)
  }
  if (!response.ok) {
    const detail = (data as ErrorBody | null)?.error
    throw withNumbers(new ApiError(response.status, detail?.code ?? 'error', detail?.message ?? 'Request failed.'), detail)
  }
  return data as T
}

const UNITS: Record<string, string> = { ram_mb: 'MB RAM', disk_gb: 'GB disk' }

function withNumbers(error: ApiError, detail: ErrorBody['error']): ApiError {
  const unit = detail?.resource ? UNITS[detail.resource] : undefined
  if (detail && unit && Number.isInteger(detail.needed) && Number.isInteger(detail.free)) {
    error.numbers = { needed: detail.needed as number, free: detail.free as number, unit }
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

export const signOut = () => call<null>('POST', '/api/auth/logout')

export const listMachines = async () => (await call<{ machines: Machine[] }>('GET', '/api/machines')).machines
export const installDefaults = () => call<InstallDefaults>('GET', '/api/installs/defaults')
export const startInstall = (body: Record<string, unknown>) => call<{ id: string }>('POST', '/api/installs', body)
export const installProgress = (id: string) => call<InstallJob>('GET', `/api/installs/${encodeURIComponent(id)}`)
export const removeMachine = (id: string) => call<null>('DELETE', `/api/machines/${encodeURIComponent(id)}`)

export const scanSetup = () => call<ScanSetup>('GET', '/api/scan/setup')
export const startScan = () => call<unknown>('POST', '/api/scans')
export const latestScan = async () => (await call<{ scan: Scan | null }>('GET', '/api/scans/latest')).scan

export const createWorkload = (body: Record<string, unknown>) => call<unknown>('POST', '/api/workloads', body)
export const listCommands = async () => (await call<{ commands: Command[] }>('GET', '/api/commands?limit=15')).commands

export function workloadAction(machine: string, workload: string, action: WorkloadAction) {
  const body = action === 'delete' ? { confirm: true } : undefined
  return call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/workloads/${encodeURIComponent(workload)}/${action}`, body)
}

/** The numbers behind a refusal, when the Root gave them. */
export function refusalText(error: ApiError): string {
  return error.numbers ? `${error.message}: needs ${error.numbers.needed} ${error.numbers.unit}, the best machine has ${error.numbers.free} free.` : error.message
}

export const bundleOverview = () => call<BundleOverview>('GET', '/api/bundles')
export const pinBundle = (version: string) => call<unknown>('POST', '/api/bundles/pin', { version })
export const rollbackBundle = () => call<unknown>('POST', '/api/bundles/rollback')
export const installBundle = (machine: string, workload?: string) =>
  call<unknown>('POST', `/api/machines/${encodeURIComponent(machine)}/bundle/install`, workload ? { workload } : {})
export const chatLink = async (machine: string, workload?: string) =>
  (await call<{ url: string }>('GET', `/api/chat-link?machine=${encodeURIComponent(machine)}${workload ? `&workload=${encodeURIComponent(workload)}` : ''}`)).url

export const brainStatus = () => call<BrainStatus>('GET', '/api/brain')
export const testBrain = () => call<unknown>('POST', '/api/brain/test')

export const remoteProbe = (body: { host: string; port?: number }) => call<ProbeResult>('POST', '/api/remote/probe', body)
export const remoteVerify = (body: Record<string, unknown>) => call<VerifyResult>('POST', '/api/remote/verify', body)
export const parentKey = async () => (await call<{ public_key: string }>('GET', '/api/remote/key')).public_key
export const remotePlan = (body: Record<string, unknown>) => call<PlanPreview>('POST', '/api/remote/plan', body)
export const remoteInstall = (body: Record<string, unknown>) => call<{ id: string }>('POST', '/api/remote/installs', body)
export const remoteInstallProgress = (id: string) => call<InstallJob>('GET', `/api/remote/installs/${encodeURIComponent(id)}`)
export const remoteMachines = async () => (await call<{ machines: RemoteMachineInfo[] }>('GET', '/api/remote/machines')).machines
export const remoteRemove = (machine: string, body: Record<string, unknown>) => call<null>('POST', `/api/remote/machines/${encodeURIComponent(machine)}/remove`, body)

export const openScreen = (machine: string) => call<ScreenSession>('POST', `/api/machines/${encodeURIComponent(machine)}/screen`)
export const takeScreenControl = (ticket: string) => call<ScreenSession>('POST', `/api/screen/${encodeURIComponent(ticket)}/control`, { confirm: true })
export const sendScreenInput = (ticket: string, events: ScreenInput[]) => call<null>('POST', `/api/screen/${encodeURIComponent(ticket)}/input`, { events })
export const closeScreen = (ticket: string) => call<null>('DELETE', `/api/screen/${encodeURIComponent(ticket)}`)

/** One picture of the screen as an image bitmap, or the reason there is none (the session ended, the machine did not answer). */
export async function screenPicture(ticket: string): Promise<ImageBitmap> {
  let response: Response
  try {
    response = await fetch(`/api/screen/${encodeURIComponent(ticket)}/frame`, { credentials: 'same-origin', cache: 'no-store' })
  } catch {
    throw new ApiError(0, 'unreachable', 'Cannot reach the Root.')
  }
  if (!response.ok) {
    const detail = ((await response.json().catch(() => null)) as ErrorBody | null)?.error
    throw new ApiError(response.status, detail?.code ?? 'error', detail?.message ?? 'No picture.')
  }
  return createImageBitmap(await response.blob())
}

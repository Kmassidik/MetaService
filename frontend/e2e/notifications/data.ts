// The stand-in data of the notifications test (never in the panel itself): one machine with four VMs whose newest orders are a running delete with a step, a delete that
// timed out, a delete that lost contact and a stop that failed; and 63 notifications with a mix of kinds, one unknown kind, hostile text and a few with no target.
// The routes answer like the parent will: GET /api/notifications pages newest first, POST /api/notifications/read marks ids or everything, a second delete is a 409.
import { isRecord, type Json } from '../support/json.ts'
import { machine } from '../security/data.ts'

export const MACHINE = 'rtx-pc'
export const NOTIFICATION_COUNT = 63
export const UNREAD_COUNT = 14
export const PAGE_SIZE_DEFAULT = 25
export const BACKUP_STEP = 'Backing up (this can take several minutes for big disks)'
export const HOSTILE = '<img src=x onerror="window.__xss=1">'
export const ALREADY_DELETING = 'This machine is already being deleted.'
/** The VMs and what their newest order is. */
export const VM_RUNNING_DELETE = 'vm-0019'
export const VM_TIMED_OUT = 'vm-0020'
export const VM_LOST_CONTACT = 'vm-0021'
export const VM_STOP_FAILED = 'vm-0022'

const MINUTE_MS = 60_000
const ago = (minutes: number): string => new Date(Date.now() - minutes * MINUTE_MS).toISOString()
const vm = (id: string, state: string): Json => ({ id, name: id, kind: 'vm', state, cpu: 2, ram_mb: 4096, disk_gb: 40, address: null, bundle_version: null })

export const standInMachines = (): Json[] => [machine(MACHINE, 'linux', { workloads: [vm(VM_RUNNING_DELETE, 'deleting'), vm(VM_TIMED_OUT, 'running'), vm(VM_LOST_CONTACT, 'stopped'), vm(VM_STOP_FAILED, 'running')] })]

const order = (id: string, type: string, workload: string, state: string, minutes: number, extra: Json): Json => ({
  id, type, machine: MACHINE, workload_id: workload, state, created_at: ago(minutes), params: {}, result: null, finished_at: null, step: null, step_at: null, ...extra,
})

export const standInCommands = (): Json[] => [
  order('c-run', 'delete', VM_RUNNING_DELETE, 'running', 3, { step: BACKUP_STEP, step_at: ago(1) }),
  order('c-time', 'delete', VM_TIMED_OUT, 'timed_out', 40, { finished_at: ago(10), step: 'Backing up (this can take several minutes for big disks)', result: { error: 'This took too long. Nothing more was done. Check the machine.' } }),
  order('c-lost', 'delete', VM_LOST_CONTACT, 'lost_contact', 30, { finished_at: ago(20), step: 'Deleting', result: { error: 'The machine stopped answering. The last step was Deleting.' } }),
  order('c-stop', 'stop', VM_STOP_FAILED, 'failed', 25, { finished_at: ago(24), result: { error: 'The VM did not stop in time.' } }),
]

const KINDS = ['job_succeeded', 'job_failed', 'job_timed_out', 'job_lost_contact']
const TITLES: Record<string, string> = { job_succeeded: 'Deleted', job_failed: 'Could not delete', job_timed_out: 'Delete took too long', job_lost_contact: 'Lost contact during delete' }

function notification(id: number): Json {
  const kind = id === 58 ? 'job_exploded' : (KINDS[id % KINDS.length] ?? 'job_failed')
  const target = id % 9 === 0 ? { machine: null, workload_id: null } : { machine: MACHINE, workload_id: `vm-${String(id).padStart(4, '0')}` }
  const title = id === 60 ? HOSTILE : `${TITLES[kind] ?? 'Notice'} ${String(target.workload_id ?? 'a machine')}`
  const detail = kind === 'job_succeeded' ? 'It took 4 minutes. A backup was kept.' : 'Check the machine, then try again.'
  return { id, kind, title, detail, command_id: `c-${id}`, ...target, created_at: ago(id * 17), read_at: id > NOTIFICATION_COUNT - UNREAD_COUNT ? null : ago(id * 17 - 1) }
}

export interface Notifications {
  all: Json[]
  /** Every body POSTed to the read route, in order. */
  reads: unknown[]
  /** Every delete the panel sent, as "<vm>". */
  deletes: string[]
}

export const makeNotifications = (): Notifications => ({ all: Array.from({ length: NOTIFICATION_COUNT }, (_, index) => notification(NOTIFICATION_COUNT - index)), reads: [], deletes: [] })

const unread = (state: Notifications): number => state.all.filter((row) => row.read_at === null).length

function markRead(state: Notifications, body: unknown): Json {
  const ids = isRecord(body) && Array.isArray(body.ids) ? body.ids : null
  const mark = state.all.filter((row) => row.read_at === null && (ids === null || ids.includes(row.id)))
  for (const row of mark) row.read_at = new Date().toISOString()
  return { marked: mark.length, unread_count: unread(state) }
}

function page(state: Notifications, query: URLSearchParams): Json {
  const size = Math.min(Number(query.get('page_size') ?? PAGE_SIZE_DEFAULT), 100)
  const number = Number(query.get('page') ?? 1)
  const rows = query.get('unread') === 'true' ? state.all.filter((row) => row.read_at === null) : state.all
  return { notifications: rows.slice((number - 1) * size, number * size), total: rows.length, unread_count: unread(state), page: number, page_size: size }
}

export function notificationRoutes(state: Notifications) {
  return (path: string, query: URLSearchParams, method: string, body: unknown): { status: number; body: unknown } | null => {
    if (path === '/api/notifications' && method === 'GET') return { status: 200, body: page(state, query) }
    if (path === '/api/notifications/read' && method === 'POST') {
      state.reads.push(body)
      return { status: 200, body: markRead(state, body) }
    }
    if (path === '/api/commands') return { status: 200, body: { commands: standInCommands() } }
    const deleted = /^\/api\/machines\/[a-z0-9-]+\/workloads\/([\w-]+)\/delete$/.exec(path)
    if (deleted && method === 'POST') {
      state.deletes.push(deleted[1] ?? '')
      return { status: 409, body: { error: { code: 'already_deleting', message: ALREADY_DELETING } } }
    }
    return null
  }
}

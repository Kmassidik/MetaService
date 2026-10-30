// Read the approvals and the recent calls (GET /api/mcp/approvals and /api/mcp/activity). See mcp/SPEC.md sections 5 and 7.
import { fields, listUnder, maybeText, maybeTime, maybeWhole, oneOf, text, time } from './mcpParse.ts'
import { UnreadableAnswer, type Fields } from './unreadable.ts'

export const REQUEST_KINDS = ['create', 'delete', 'start', 'stop'] as const
export type RequestKind = (typeof REQUEST_KINDS)[number]
export const REQUEST_STATES = ['pending_approval', 'approved', 'denied', 'running', 'done', 'failed', 'expired'] as const
export type RequestState = (typeof REQUEST_STATES)[number]

/** What the AI asked for. Names are typed by people or the AI: only ever shown as text. */
export interface RequestParams {
  machine: string | null
  vm: string | null
  size: string | null
  vcpu: number | null
  ramMb: number | null
  diskGb: number | null
  gpuMemoryGb: number | null
}

export interface McpRequest {
  id: string
  tokenName: string
  kind: RequestKind
  params: RequestParams
  state: RequestState
  createdAt: number
  expiresAt: number | null
  decidedBy: string | null
  decidedAt: number | null
}

export interface Approvals {
  pending: McpRequest[]
  recent: McpRequest[]
}

export interface ActivityRow {
  at: number
  tokenName: string
  /** The tool, for example `create_vm`. */
  tool: string
  target: string | null
  status: string
}

/** The first of these fields that holds text: the parent may send a name next to an id. */
function firstText(source: Fields, keys: string[]): string | null {
  for (const key of keys) {
    const value = maybeText(source, key)
    if (value) return value
  }
  return null
}

function params(value: unknown): RequestParams {
  const row = value === undefined || value === null ? {} : fields(value, 'the request details')
  return {
    machine: firstText(row, ['machine_name', 'machine']),
    vm: firstText(row, ['vm_name', 'name', 'vm']),
    size: maybeText(row, 'size'),
    vcpu: maybeWhole(row, 'vcpu', 1),
    ramMb: maybeWhole(row, 'ram_mb', 1),
    diskGb: maybeWhole(row, 'disk_gb', 1),
    gpuMemoryGb: maybeWhole(row, 'gpu_memory_gb', 1),
  }
}

function request(value: unknown): McpRequest {
  const row = fields(value, 'a request')
  return {
    id: text(row, 'id'),
    tokenName: text(row, 'token_name'),
    kind: oneOf(row.kind, REQUEST_KINDS, 'kind'),
    params: params(row.params),
    state: oneOf(row.state, REQUEST_STATES, 'state'),
    createdAt: time(row, 'created_at'),
    expiresAt: maybeTime(row, 'expires_at'),
    decidedBy: maybeText(row, 'decided_by'),
    decidedAt: maybeTime(row, 'decided_at'),
  }
}

const requests = (raw: unknown, key: string): McpRequest[] => listUnder(raw, key, 'the approvals answer').map(request)

/** `{pending: [...], recent: [...]}`, or one bare list that is split by state. */
export function parseApprovals(raw: unknown): Approvals {
  if (Array.isArray(raw)) {
    const all = raw.map(request)
    return { pending: all.filter((row) => row.state === 'pending_approval'), recent: all.filter((row) => row.state !== 'pending_approval') }
  }
  const row = fields(raw, 'the approvals answer')
  return { pending: requests(row, 'pending'), recent: row.recent === undefined ? [] : requests(row, 'recent') }
}

const ACTOR_PREFIX = 'mcp:'
const ACTION_PREFIX = 'mcp.'

function activityRow(value: unknown): ActivityRow {
  const row = fields(value, 'a call')
  const actor = text(row, 'actor')
  const action = text(row, 'action')
  if (!actor.startsWith(ACTOR_PREFIX)) throw new UnreadableAnswer('a call is not from an AI client')
  return {
    at: time(row, row.at === undefined ? 'created_at' : 'at'),
    tokenName: actor.slice(ACTOR_PREFIX.length),
    tool: action.startsWith(ACTION_PREFIX) ? action.slice(ACTION_PREFIX.length) : action,
    target: maybeText(row, 'target'),
    status: text(row, 'status'),
  }
}

/** The recent calls (GET /api/mcp/activity), newest first as the parent sends them. */
export const parseActivity = (raw: unknown): ActivityRow[] => listUnder(raw, 'activity', 'the activity answer').map(activityRow)

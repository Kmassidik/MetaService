// Read the AI access answers of the parent (tokens, the connection facts) before the panel trusts them. See mcp/SPEC.md sections 3 and 7.
import { fields, listUnder, maybeText, maybeTime, oneOf, text, time, whole, list } from './mcpParse.ts'
import { isFields, UnreadableAnswer, type Fields } from './unreadable.ts'

export const MCP_SCOPES = ['read', 'create', 'destroy', 'gpu', 'shared'] as const
export type McpScope = (typeof MCP_SCOPES)[number]

export interface McpQuotas {
  maxVms: number
  maxVcpu: number
  maxRamMb: number
  maxDiskGb: number
  createsPerDay: number
  /** The GPU memory cap; null when the token has no `gpu` scope. */
  gpuMemoryGb: number | null
}

/** The defaults of a new token (SPEC section 3). The parent's own answer wins when it sends them. */
export const DEFAULT_QUOTAS: McpQuotas = { maxVms: 3, maxVcpu: 8, maxRamMb: 16384, maxDiskGb: 200, createsPerDay: 10, gpuMemoryGb: 8 }
export const DEFAULT_SCOPES: McpScope[] = ['read', 'create']
export const DEFAULT_EXPIRY_DAYS = 90
export const MAX_EXPIRY_DAYS = 365

export interface McpToken {
  id: string
  /** Typed by the operator: only ever shown as text. */
  name: string
  prefix: string
  scopes: McpScope[]
  personId: string
  personName: string
  createdAt: number
  expiresAt: number
  lastUsedAt: number | null
  revokedAt: number | null
}

/** A person who uses AI clients. The quotas are the person's, counted over all their tokens. */
export interface McpPerson {
  id: string
  /** Typed by the operator: only ever shown as text. */
  name: string
  scopes: McpScope[]
  quotas: McpQuotas
  tokens: number
  vmsAlive: number
  lastUsedAt: number | null
  disabledAt: number | null
}

export interface McpInfo {
  endpoint: string
  tools: string[]
  defaults: { scopes: McpScope[]; quotas: McpQuotas; expiryDays: number }
}

function quotas(value: unknown): McpQuotas {
  const row = fields(value, 'quotas')
  return {
    maxVms: whole(row, 'max_vms', 1),
    maxVcpu: whole(row, 'max_vcpu', 1),
    maxRamMb: whole(row, 'max_ram_mb', 1),
    maxDiskGb: whole(row, 'max_disk_gb', 1),
    createsPerDay: whole(row, 'creates_per_day', 1),
    gpuMemoryGb: row.gpu_memory_gb === null || row.gpu_memory_gb === undefined ? null : whole(row, 'gpu_memory_gb', 1),
  }
}

const scopeList = (raw: unknown, what: string): McpScope[] => list(raw, what).map((scope) => oneOf(scope, MCP_SCOPES, 'scope'))

function token(value: unknown): McpToken {
  const row = fields(value, 'a token')
  return {
    id: text(row, 'id'),
    name: text(row, 'name'),
    prefix: text(row, 'prefix'),
    scopes: scopeList(row.scopes, 'scopes'),
    personId: text(row, 'person_id'),
    personName: text(row, 'person_name'),
    createdAt: time(row, 'created_at'),
    expiresAt: time(row, 'expires_at'),
    lastUsedAt: maybeTime(row, 'last_used_at'),
    revokedAt: maybeTime(row, 'revoked_at'),
  }
}

/** The tokens (GET /api/mcp/tokens): a bare list or `{tokens: [...]}`. */
export const parseTokens = (raw: unknown): McpToken[] => listUnder(raw, 'tokens', 'the tokens answer').map(token)

function person(value: unknown): McpPerson {
  const row = fields(value, 'a person')
  return {
    id: text(row, 'id'),
    name: text(row, 'name'),
    scopes: scopeList(row.scopes, 'scopes'),
    quotas: quotas(row.quotas),
    tokens: whole(row, 'tokens', 0),
    vmsAlive: whole(row, 'vms_alive', 0),
    lastUsedAt: maybeTime(row, 'last_used_at'),
    disabledAt: maybeTime(row, 'disabled_at'),
  }
}

/** The people (GET /api/mcp/people): a bare list or `{people: [...]}`. */
export const parsePeople = (raw: unknown): McpPerson[] => listUnder(raw, 'people', 'the people answer').map(person)

/** The token text from the reply that made it. It comes back this once and nowhere else. */
export function parseMadeToken(raw: unknown): string {
  const secret = text(fields(raw, 'the new token answer'), 'token')
  if (!secret) throw new UnreadableAnswer('the token text is empty')
  return secret
}

function toolName(value: unknown): string {
  if (typeof value === 'string') return value
  if (isFields(value)) return text(value, 'name')
  throw new UnreadableAnswer('a tool has no name')
}

function defaults(source: Fields): McpInfo['defaults'] {
  const row = source.defaults === undefined ? {} : fields(source.defaults, 'defaults')
  return {
    scopes: row.scopes === undefined ? DEFAULT_SCOPES : scopeList(row.scopes, 'default scopes'),
    quotas: row.quotas === undefined ? DEFAULT_QUOTAS : quotas({ gpu_memory_gb: DEFAULT_QUOTAS.gpuMemoryGb, ...fields(row.quotas, 'default quotas') }),
    expiryDays: row.expires_in_days === undefined ? DEFAULT_EXPIRY_DAYS : whole(row, 'expires_in_days', 1),
  }
}

/** The connection facts (GET /api/mcp/info): the endpoint, the tool names, the defaults of a new token. */
export function parseInfo(raw: unknown): McpInfo {
  const row = fields(raw, 'the info answer')
  const endpoint = maybeText(row, 'endpoint')
  if (!endpoint) throw new UnreadableAnswer('the endpoint is missing')
  return { endpoint, tools: list(row.tools ?? [], 'tools').map(toolName), defaults: defaults(row) }
}

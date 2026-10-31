// What the operator types in the Add person, Edit person and Create token windows, the checks before it is sent, and the bodies of the requests.
import { DEFAULT_EXPIRY_DAYS, DEFAULT_QUOTAS, DEFAULT_SCOPES, MAX_EXPIRY_DAYS, MCP_SCOPES, type McpInfo, type McpPerson, type McpScope } from './mcp.ts'

const MB_PER_GB = 1024
const NAME = /^[A-Za-z0-9 ._-]{1,40}$/
export const NAME_PROBLEM = 'The name may have 1 to 40 letters, digits, spaces, dots, dashes or underscores.'

export interface PersonDraft {
  name: string
  scopes: McpScope[]
  maxVms: number | null
  maxVcpu: number | null
  maxRamGb: number | null
  maxDiskGb: number | null
  createsPerDay: number | null
  gpuMemoryGb: number | null
}

export interface PersonBody {
  name: string
  scopes: McpScope[]
  quotas: Record<string, number>
}

export interface TokenDraft {
  name: string
  personId: string
  scopes: McpScope[]
  expiresInDays: number | null
}

export interface TokenBody {
  name: string
  person_id: string
  scopes: McpScope[]
  expires_in_days: number
}

const isWhole = (value: number | null): value is number => value !== null && Number.isInteger(value) && value >= 1

/** The scopes in the spec's order, so a body never depends on the order of the clicks. */
const inOrder = (scopes: McpScope[]): McpScope[] => MCP_SCOPES.filter((scope) => scopes.includes(scope))

/** Ticks or unticks one scope. */
export const toggleScope = (scopes: McpScope[], scope: McpScope, on: boolean): McpScope[] => [...scopes.filter((entry) => entry !== scope), ...(on ? [scope] : [])]

/** The starting values of Add person (the parent's defaults when it sent them, else the spec's) or of Edit person (the person's own). */
export function personDraftFor(defaults?: McpInfo['defaults'], person?: McpPerson): PersonDraft {
  const quotas = person?.quotas ?? defaults?.quotas ?? DEFAULT_QUOTAS
  return {
    name: person?.name ?? '',
    scopes: [...(person?.scopes ?? defaults?.scopes ?? DEFAULT_SCOPES)],
    maxVms: quotas.maxVms,
    maxVcpu: quotas.maxVcpu,
    maxRamGb: Math.round(quotas.maxRamMb / MB_PER_GB),
    maxDiskGb: quotas.maxDiskGb,
    createsPerDay: quotas.createsPerDay,
    gpuMemoryGb: quotas.gpuMemoryGb ?? DEFAULT_QUOTAS.gpuMemoryGb,
  }
}

/** The first thing wrong with a person, in plain words, or null when it can be sent. An edit keeps the name, so it is not checked. */
export function personProblem(draft: PersonDraft, adding: boolean): string | null {
  if (adding && !NAME.test(draft.name.trim())) return NAME_PROBLEM
  if (draft.scopes.length === 0) return 'Choose at least one thing this person may do.'
  const numbers = [draft.maxVms, draft.maxVcpu, draft.maxRamGb, draft.maxDiskGb, draft.createsPerDay, draft.scopes.includes('gpu') ? draft.gpuMemoryGb : 1]
  return numbers.every(isWhole) ? null : 'The limits must be whole numbers above zero.'
}

/** The quotas of a draft; RAM in MB, and the GPU cap only with the gpu scope. Call only when personProblem is null. */
function quotaBody(draft: PersonDraft): Record<string, number> {
  const quotas: Record<string, number> = {
    max_vms: Number(draft.maxVms),
    max_vcpu: Number(draft.maxVcpu),
    max_ram_mb: Number(draft.maxRamGb) * MB_PER_GB,
    max_disk_gb: Number(draft.maxDiskGb),
    creates_per_day: Number(draft.createsPerDay),
  }
  if (draft.scopes.includes('gpu')) quotas.gpu_memory_gb = Number(draft.gpuMemoryGb)
  return quotas
}

/** POST /api/mcp/people. */
export const personBody = (draft: PersonDraft): PersonBody => ({ name: draft.name.trim(), scopes: inOrder(draft.scopes), quotas: quotaBody(draft) })

/** PATCH /api/mcp/people/{id}: scopes and quotas only. */
export const personPatch = (draft: PersonDraft): Omit<PersonBody, 'name'> => ({ scopes: inOrder(draft.scopes), quotas: quotaBody(draft) })

/** The starting values of Create token: the first person who is not disabled, every scope that person has, the default lifetime. */
export function tokenDraftFor(people: McpPerson[], defaultDays = DEFAULT_EXPIRY_DAYS): TokenDraft {
  const first = people.find((person) => person.disabledAt === null)
  return { name: '', personId: first?.id ?? '', scopes: [...(first?.scopes ?? [])], expiresInDays: defaultDays }
}

/** The first thing wrong with a token draft, or null. The token may only have scopes its person has. */
export function tokenProblem(draft: TokenDraft, person: McpPerson | undefined): string | null {
  if (!person) return 'Choose which person this token is for.'
  if (!NAME.test(draft.name.trim())) return NAME_PROBLEM
  if (draft.scopes.length === 0) return 'Choose at least one thing the token may do.'
  if (!draft.scopes.every((scope) => person.scopes.includes(scope))) return `${person.name} does not have all of those permissions.`
  return !isWhole(draft.expiresInDays) || draft.expiresInDays > MAX_EXPIRY_DAYS ? `The token may last 1 to ${MAX_EXPIRY_DAYS} days.` : null
}

/** POST /api/mcp/tokens. Call only when tokenProblem is null. */
export const tokenBody = (draft: TokenDraft): TokenBody => ({ name: draft.name.trim(), person_id: draft.personId, scopes: inOrder(draft.scopes), expires_in_days: Number(draft.expiresInDays) })

// What the operator types in the Create token window, the checks before it is sent, and the body of the request.
import { DEFAULT_EXPIRY_DAYS, DEFAULT_QUOTAS, DEFAULT_SCOPES, MAX_EXPIRY_DAYS, MCP_SCOPES, type McpInfo, type McpScope } from './mcp.ts'

const MB_PER_GB = 1024
const NAME_LIMIT = 64

export interface TokenDraft {
  name: string
  scopes: McpScope[]
  maxVms: number | null
  maxVcpu: number | null
  maxRamGb: number | null
  maxDiskGb: number | null
  createsPerDay: number | null
  gpuMemoryGb: number | null
  expiresInDays: number | null
  autoApprove: boolean
}

export interface TokenBody {
  name: string
  scopes: McpScope[]
  quotas: Record<string, number>
  expires_in_days: number
  auto_approve: boolean
}

/** The starting values: the parent's defaults when it sent them, else the ones in the spec. Auto-approve is always off. */
export function draftFor(defaults?: McpInfo['defaults']): TokenDraft {
  const quotas = defaults?.quotas ?? DEFAULT_QUOTAS
  return {
    name: '',
    scopes: [...(defaults?.scopes ?? DEFAULT_SCOPES)],
    maxVms: quotas.maxVms,
    maxVcpu: quotas.maxVcpu,
    maxRamGb: Math.round(quotas.maxRamMb / MB_PER_GB),
    maxDiskGb: quotas.maxDiskGb,
    createsPerDay: quotas.createsPerDay,
    gpuMemoryGb: quotas.gpuMemoryGb ?? DEFAULT_QUOTAS.gpuMemoryGb,
    expiresInDays: defaults?.expiryDays ?? DEFAULT_EXPIRY_DAYS,
    autoApprove: false,
  }
}

const isWhole = (value: number | null): value is number => value !== null && Number.isInteger(value) && value >= 1

/** The first thing wrong with the draft, in plain words, or null when it can be sent. */
export function draftProblem(draft: TokenDraft): string | null {
  const name = draft.name.trim()
  if (!name) return 'Give the token a name, so you can tell it apart later.'
  if (name.length > NAME_LIMIT) return `The name may have up to ${NAME_LIMIT} characters.`
  if (draft.scopes.length === 0) return 'Choose at least one thing the token may do.'
  const numbers = [draft.maxVms, draft.maxVcpu, draft.maxRamGb, draft.maxDiskGb, draft.createsPerDay, draft.scopes.includes('gpu') ? draft.gpuMemoryGb : 1]
  if (!numbers.every(isWhole)) return 'The limits must be whole numbers above zero.'
  if (!isWhole(draft.expiresInDays) || draft.expiresInDays > MAX_EXPIRY_DAYS) return `The token may last 1 to ${MAX_EXPIRY_DAYS} days.`
  return null
}

/** The request body. The scopes keep the spec's order; the GPU cap is sent only with the gpu scope. Call only when draftProblem is null. */
export function tokenBody(draft: TokenDraft): TokenBody {
  const quotas: Record<string, number> = {
    max_vms: Number(draft.maxVms),
    max_vcpu: Number(draft.maxVcpu),
    max_ram_mb: Number(draft.maxRamGb) * MB_PER_GB,
    max_disk_gb: Number(draft.maxDiskGb),
    creates_per_day: Number(draft.createsPerDay),
  }
  if (draft.scopes.includes('gpu')) quotas.gpu_memory_gb = Number(draft.gpuMemoryGb)
  return {
    name: draft.name.trim(),
    scopes: MCP_SCOPES.filter((scope) => draft.scopes.includes(scope)),
    quotas,
    expires_in_days: Number(draft.expiresInDays),
    auto_approve: draft.autoApprove,
  }
}

/** Ticks or unticks one scope. */
export const toggleScope = (scopes: McpScope[], scope: McpScope, on: boolean): McpScope[] => [...scopes.filter((entry) => entry !== scope), ...(on ? [scope] : [])]

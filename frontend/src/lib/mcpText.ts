// The words of the AI access section: scopes, limits, expiry, the tools and the two connection lines. Pure, so the wording is tested.
import type { ConfirmCopy } from './confirmCopy.ts'
import type { McpPerson, McpQuotas, McpScope, McpToken } from './mcp.ts'

export interface ScopeText {
  /** The short name on a chip and next to a checkbox. */
  name: McpScope
  /** One plain sentence: what the AI can do with it. */
  explain: string
}

export const SCOPE_TEXT: Record<McpScope, ScopeText> = {
  read: { name: 'read', explain: 'See machines, their free room, and the VMs this person made.' },
  create: { name: 'create', explain: 'Create, start and stop VMs. Only the VMs this person made.' },
  destroy: { name: 'destroy', explain: 'Delete VMs this person made.' },
  gpu: { name: 'gpu', explain: 'Ask for a GPU memory limit on a new VM.' },
  shared: { name: 'shared', explain: 'Use machines that joined through Share a PC.' },
}

/** What each tool does and which scope it needs (mcp/SPEC.md section 4). The panel shows the tools the parent lists, with these words. */
export const TOOL_TEXT: Record<string, { scope: McpScope; explain: string }> = {
  list_machines: { scope: 'read', explain: 'List the machines and how much room they have.' },
  machine_capacity: { scope: 'read', explain: 'Say what a new VM can still get on one machine.' },
  list_vms: { scope: 'read', explain: 'List the VMs this person made.' },
  vm_status: { scope: 'read', explain: 'Show one VM: state, size, address.' },
  create_vm: { scope: 'create', explain: 'Create a VM. A GPU limit needs the gpu scope.' },
  start_vm: { scope: 'create', explain: 'Start a VM this person made.' },
  stop_vm: { scope: 'create', explain: 'Stop a VM this person made.' },
  delete_vm: { scope: 'destroy', explain: 'Delete a VM this person made.' },
  get_request: { scope: 'read', explain: 'Check a create, start, stop or delete that is still running.' },
}

const MB_PER_GB = 1024

function ramText(mb: number): string {
  return mb % MB_PER_GB === 0 ? `${mb / MB_PER_GB} GB RAM` : `${mb} MB RAM`
}

/** The limits of a token in one short line. The GPU cap only shows when the token has the gpu scope. */
export function quotaLine(quotas: McpQuotas, scopes: McpScope[]): string {
  const parts = [`${quotas.maxVms} ${quotas.maxVms === 1 ? 'VM' : 'VMs'}`, `${quotas.maxVcpu} vCPU`, ramText(quotas.maxRamMb), `${quotas.maxDiskGb} GB disk`, `${quotas.createsPerDay} creates/day`]
  if (scopes.includes('gpu') && quotas.gpuMemoryGb !== null) parts.push(`GPU up to ${quotas.gpuMemoryGb} GB`)
  return parts.join(' · ')
}

const SECONDS = 1000
const MINUTE = 60 * SECONDS
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const JUST_NOW_MS = 45 * SECONDS

function span(ms: number): string {
  if (ms >= DAY) return `${Math.round(ms / DAY)} ${Math.round(ms / DAY) === 1 ? 'day' : 'days'}`
  if (ms >= HOUR) return `${Math.round(ms / HOUR)} h`
  return `${Math.max(1, Math.round(ms / MINUTE))} min`
}

/** "just now", "5 min ago", "3 h ago", "2 days ago". A time in the future (clocks differ a little) reads as just now. */
export function agoText(at: number, now: number): string {
  const ms = now - at
  return ms < JUST_NOW_MS ? 'just now' : `${span(ms)} ago`
}

export const lastUsedText = (at: number | null, now: number): string => (at === null ? 'never' : agoText(at, now))

/** When the token stops working, in words: "in 89 days", "in 5 h", "expired", or "revoked". */
export function expiryText(token: Pick<McpToken, 'expiresAt' | 'revokedAt'>, now: number): string {
  if (token.revokedAt !== null) return 'revoked'
  const left = token.expiresAt - now
  return left <= 0 ? 'expired' : `in ${span(left)}`
}

/** True while a token still works. */
export const isLive = (token: Pick<McpToken, 'expiresAt' | 'revokedAt'>, now: number): boolean => token.revokedAt === null && token.expiresAt > now

export const TOKEN_PLACEHOLDER = '<YOUR_TOKEN>'

/** The line to paste in a terminal to connect Claude Code. The token is a placeholder: a real one is shown once, when it is made. */
export const claudeLine = (endpoint: string): string => `claude mcp add --transport http metaservice ${endpoint} --header "Authorization: Bearer ${TOKEN_PLACEHOLDER}"`

/** The JSON for another client that reads an `mcpServers` file. */
export const jsonSnippet = (endpoint: string): string =>
  JSON.stringify({ mcpServers: { metaservice: { type: 'http', url: endpoint, headers: { Authorization: `Bearer ${TOKEN_PLACEHOLDER}` } } } }, null, 2)

export const NOT_AVAILABLE_TEXT = 'AI access is not available on this parent.'
export const NEW_TOKEN_WARNING = 'Copy this token now. It cannot be shown again, and the panel does not keep it. If you lose it, revoke it and make a new one.'
export const revokeCopy = (token: Pick<McpToken, 'name'>): ConfirmCopy => ({
  title: 'Revoke this token?',
  what: `${token.name} stops working at once.`,
  consequence: 'The VMs it made keep running and stay listed as its own. You cannot turn it back on; make a new token if you need one.',
  confirmLabel: 'Revoke token',
  busyLabel: 'Revoking…',
  doneLabel: 'Revoked',
})

export const disableCopy = (person: Pick<McpPerson, 'name'>): ConfirmCopy => ({
  title: 'Disable this person?',
  what: `${person.name} and all their tokens stop working at once.`,
  consequence: 'Their VMs keep running and keep their creator record. You can enable them again.',
  confirmLabel: 'Disable person',
  busyLabel: 'Disabling…',
  doneLabel: 'Disabled',
})

/** How many tokens a person has, in words. */
export const tokensText = (count: number): string => (count === 0 ? 'no tokens' : `${count} ${count === 1 ? 'token' : 'tokens'}`)

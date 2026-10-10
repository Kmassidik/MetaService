/**
 * Sidebar roster: bots and group chats in one list, pinned first, then most
 * recent activity. Pure functions only, so the ordering rules are testable without Svelte.
 */

const TEAM_KIND = 'team'
const RUNNING = 'running'
const BUSY_STATUSES = [RUNNING, 'provisioning']
// A bot still being set up previews its welcome like any chat: the wait stays out of sight.
const PREVIEW_BY_STATUS = { failed: 'Setup needs attention' }
const HIDDEN_PREVIEW = 'Hidden'
const MAX_UNREAD_SHOWN = 9
// Previews are cut from raw replies; markdown markers read as noise in a one-line row.
const MARKDOWN_MARKERS = /[*_`#>~]+/g
export const GROUP_FACES = 2

export const isTeam = agent => agent?.kind === TEAM_KIND

export function matchesQuery(agent, query = '') {
  const needle = query.toLowerCase().trim()
  if (!needle) return true
  const haystack = [agent.name, agent.title, agent.summary, agent.description].filter(Boolean).join(' ')
  return haystack.toLowerCase().includes(needle)
}

/**
 * Milliseconds of the agent's latest activity. A bot that is working right now counts as the most
 * recent, because its reply is about to land. `activityAt` lets the caller pass known message times.
 */
export function activityTime(agent, activityAt = {}, now = Date.now()) {
  if (BUSY_STATUSES.includes(agent.status)) return now
  const stamp = activityAt[agent.id] || agent.createdAt
  const parsed = Date.parse(stamp || '')
  return Number.isNaN(parsed) ? 0 : parsed
}

function compareRosterEntries(a, b) {
  if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
  if (a.time !== b.time) return b.time - a.time
  return a.agent.name.localeCompare(b.agent.name)
}

/** Visible roster: hidden bots excluded, search applied, pinned first, then newest activity. */
export function buildRoster(agents = [], { query = '', activityAt = {}, now = Date.now() } = {}) {
  return agents
    .filter(agent => !agent.hidden && matchesQuery(agent, query))
    .map(agent => ({ agent, pinned: Boolean(agent.pinned), time: activityTime(agent, activityAt, now) }))
    .sort(compareRosterEntries)
    .map(entry => entry.agent)
}

export function hiddenRoster(agents = []) {
  return agents.filter(agent => agent.hidden && !isTeam(agent))
}

/** The faces stacked on a group row: its lead first, then members, deduplicated. */
export function groupFaces(team, agents = []) {
  const ids = [team.leadAgentId, ...(team.memberAgentIds || [])].filter(Boolean)
  const unique = [...new Set(ids)]
  return unique
    .map(id => agents.find(agent => agent.id === id))
    .filter(Boolean)
    .slice(0, GROUP_FACES)
}

export function rowPreview(agent, pending = null) {
  if (agent.hidden) return HIDDEN_PREVIEW
  const statusText = PREVIEW_BY_STATUS[agent.status]
  if (statusText) return statusText
  if (pending?.id === agent.id && pending.text) return pending.text
  return plainPreview(agent.lastMessagePreview)
}

export function plainPreview(text = '') {
  return text.replace(MARKDOWN_MARKERS, '').replace(/\s+/g, ' ').trim()
}

/**
 * The sidebar spinner: a bot that is replying, or one holding a message for its computer. A new bot
 * whose computer is still starting stays calm — its welcome is already there to read.
 */
export function isBusy(agent, pending = null) {
  return agent.status === RUNNING || Boolean(agent.queuedMessage) || pending?.id === agent.id
}

/** Badge text for unread messages; empty when nothing should show (e.g. the open chat). */
export function unreadLabel(agent, selectedId = '') {
  const count = Number(agent.unreadCount || 0)
  if (count <= 0 || agent.id === selectedId) return ''
  return count > MAX_UNREAD_SHOWN ? `${MAX_UNREAD_SHOWN}+` : String(count)
}

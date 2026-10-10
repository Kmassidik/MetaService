/**
 * Pure read-only views over chat state that App.svelte hands to its panels. Kept free of Svelte
 * runes so each rule is unit-testable; `view.svelte.js` wires them into `$derived` values.
 */
import { APPROVAL_PENDING } from '../constants.js'
import { isTeam } from './roster.js'
import { connectedAppList } from '../apps.js'

export const MENTION_BOT_LIMIT = 8
export const MENTION_ITEM_LIMIT = 6
export const SKILL_LIMIT = 8
const ACTIVE_SKILL_STATE = 'active'
// The worker reports `running` while a bot drives the browser and `takeover` while a person does.
const COMPUTER_ON_STATES = new Set(['running', 'takeover'])
const TAKEOVER_STATE = 'takeover'
const SAFE_IMAGE_DATA_URL = /^data:image\/(png|jpeg|webp);base64,/
const ENVIRONMENT_LABELS = {
  ready: 'Ready',
  suspended: 'Suspended',
  provisioning: 'Preparing',
  deleting: 'Deletion queued',
  failed: 'Needs attention',
}
const NO_ENVIRONMENT_LABEL = 'Not created'
const FALLBACK_GREETING = 'there'
const PROVISIONING = 'provisioning'
const ASSISTANT_ROLE = 'assistant'

const needle = query => (query || '').trim().toLowerCase()
const includesNeedle = (text, query) => !query || text.toLowerCase().includes(query)

export const botsOf = agents => agents.filter(agent => !isTeam(agent))
export const teamsOf = agents => agents.filter(isTeam)

/** Top-level transcript: thread replies are not shown inline. */
export function visibleMessages(history = []) {
  return history.filter(message => !message.parentId)
}

/** The New bot welcome's starter ideas while the welcome is still the latest message; else null. */
export function openWelcomeChoices(messages = []) {
  const last = messages.at(-1)
  if (last?.role !== ASSISTANT_ROLE || !last.choices?.length) return null
  return { id: last.id, options: last.choices }
}

/** The owner's message waits for the bot's computer, or is on its way to a bot still being set up. */
export function isAwaitingComputer(active, pendingId = '') {
  if (!active) return false
  return Boolean(active.queuedMessage) || (pendingId === active.id && active.status === PROVISIONING)
}

export function threadRepliesOf(history = []) {
  return history.filter(message => message.parentId)
}

/** Agent ids of a conversation: the group's lead and members, or the bot itself. */
export function conversationMemberIds(active) {
  if (!isTeam(active)) return [active.id]
  return [active.leadAgentId, ...(active.memberAgentIds || [])].filter(Boolean)
}

/** Bots that make up a group chat, for the stacked faces on its name pill. */
export function groupMembers(active, bots = []) {
  if (!isTeam(active)) return []
  return conversationMemberIds(active)
    .map(id => bots.find(bot => bot.id === id))
    .filter(Boolean)
}

export function mentionBots(active, readyBots, query) {
  if (!active) return []
  const q = needle(query)
  const inConversation = new Set(conversationMemberIds(active))
  return readyBots
    .filter(bot => !inConversation.has(bot.id) && includesNeedle(`${bot.name} ${bot.title || ''}`, q))
    .slice(0, MENTION_BOT_LIMIT)
}

export function mentionRoutines(routines, query) {
  const q = needle(query)
  return routines
    .filter(routine => includesNeedle(`${routine.title} ${routine.triggerKind || ''}`, q))
    .slice(0, MENTION_ITEM_LIMIT)
}

export function mentionConnectors(connectors, query) {
  const q = needle(query)
  return connectors
    .filter(connector => !connector.revoked && includesNeedle(`${connector.name}`, q))
    .slice(0, MENTION_ITEM_LIMIT)
}

export function skillMatches(skills, query) {
  const q = needle(query)
  return skills
    .filter(skill => skill.enabled && skill.state === ACTIVE_SKILL_STATE && includesNeedle(skill.name, q))
    .slice(0, SKILL_LIMIT)
}

/** Apps shown on the Connect apps pill: apps signed in on the computer first, then live connectors. */
export function connectedApps(computerApps = [], connectors = [], nameOf = id => id) {
  const signedIn = connectedAppList(computerApps, nameOf)
  const live = connectors
    .filter(item => !item.revoked)
    .map(item => ({ id: item.id, name: item.name }))
  return [...signedIn, ...live]
}

function lastMessageTime(history = []) {
  return history.at(-1)?.createdAt
}

/** Agent id → ISO time of its latest loaded message, so the sidebar can sort by activity. */
export function activityByAgent(histories = {}) {
  const entries = Object.entries(histories)
    .map(([id, history]) => [id, lastMessageTime(history)])
    .filter(([, stamp]) => stamp)
  return Object.fromEntries(entries)
}

/** Only inline base64 images are rendered; anything else could point off-site. */
export function safeComputerImage(computer) {
  const image = computer?.image
  return typeof image === 'string' && SAFE_IMAGE_DATA_URL.test(image) ? image : ''
}

export function isComputerOn(computer) {
  return COMPUTER_ON_STATES.has(computer?.state)
}

export function isTakenOver(computer) {
  return computer?.state === TAKEOVER_STATE
}

export function environmentLabel(environment) {
  if (!environment) return NO_ENVIRONMENT_LABEL
  return ENVIRONMENT_LABELS[environment.state] || environment.state
}

export function firstName(session) {
  return session?.user?.name?.split(' ')[0] || FALLBACK_GREETING
}

/** An approval the owner can still decide: pending, and raised by this run. */
export function approvalAwaitsDecision(approval, run) {
  return Boolean(run) && run.id === approval?.runId && approval.state === APPROVAL_PENDING
}

/** The approvals of one run still waiting on the owner (the in-chat Approve/Deny cards). */
export function pendingApprovals(approvals = []) {
  return approvals.filter(approval => approval.state === APPROVAL_PENDING)
}

/**
 * The newest routine the bot created at or after `since` (an ISO time from the server), or null.
 * Stands in for a "routine created" run event until the server sends one (routine card).
 */
export function routineCreatedSince(routines = [], agentId, since) {
  const from = Date.parse(since)
  if (!agentId || Number.isNaN(from)) return null
  const fresh = routines.filter(routine => routine.agentId === agentId && Date.parse(routine.createdAt) >= from)
  return fresh.sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0] || null
}

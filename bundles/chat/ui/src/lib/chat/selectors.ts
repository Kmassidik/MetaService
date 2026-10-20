/**
 * Pure read-only views over chat state that App.svelte hands to its panels. Kept free of Svelte
 * runes so each rule is unit-testable; `view.svelte.js` wires them into `$derived` values.
 */
import { APPROVAL_PENDING } from '../constants.ts'
import { isTeam } from './roster.ts'
import { connectedAppList } from '../apps.ts'
import type { Dict } from '../check.ts'
import type {
  Agent, AppRecord, Approval, ChatMessage, ComputerInfo, Connector, Environment, Routine, Run, Session, Skill, WelcomeIdea,
} from '../types.ts'

type Member = Pick<Agent, 'id' | 'kind' | 'leadAgentId' | 'memberAgentIds'>

export const MENTION_BOT_LIMIT = 8
export const MENTION_ITEM_LIMIT = 6
export const SKILL_LIMIT = 8
const ACTIVE_SKILL_STATE = 'active'
// The worker reports `running` while a bot drives the browser and `takeover` while a person does.
const COMPUTER_ON_STATES: ReadonlySet<string | undefined> = new Set(['running', 'takeover'])
const TAKEOVER_STATE = 'takeover'
const SAFE_IMAGE_DATA_URL = /^data:image\/(png|jpeg|webp);base64,/
const ENVIRONMENT_LABELS: Readonly<Record<string, string>> = {
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

const needle = (query: string | undefined): string => (query || '').trim().toLowerCase()
const includesNeedle = (text: string, query: string): boolean => !query || text.toLowerCase().includes(query)

export const botsOf = (agents: readonly Agent[]): Agent[] => agents.filter(agent => !isTeam(agent))
export const teamsOf = (agents: readonly Agent[]): Agent[] => agents.filter(isTeam)

/** Top-level transcript: thread replies are not shown inline. */
export function visibleMessages(history: readonly ChatMessage[] = []): ChatMessage[] {
  return history.filter(message => !message.parentId)
}

/** The New bot welcome's starter ideas while the welcome is still the latest message; else null. */
export function openWelcomeChoices(messages: readonly ChatMessage[] = []): { id: string, options: WelcomeIdea[] } | null {
  const last = messages.at(-1)
  if (last?.role !== ASSISTANT_ROLE || !last.choices?.length) return null
  return { id: last.id, options: last.choices }
}

/** The owner's message waits for the bot's computer, or is on its way to a bot still being set up. */
export function isAwaitingComputer(active: Pick<Agent, 'id' | 'queuedMessage' | 'status'> | null | undefined, pendingId = ''): boolean {
  if (!active) return false
  return Boolean(active.queuedMessage) || (pendingId === active.id && active.status === PROVISIONING)
}

export function threadRepliesOf(history: readonly ChatMessage[] = []): ChatMessage[] {
  return history.filter(message => message.parentId)
}

/** Agent ids of a conversation: the group's lead and members, or the bot itself. */
export function conversationMemberIds(active: Member): string[] {
  if (!isTeam(active)) return [active.id]
  return [active.leadAgentId, ...(active.memberAgentIds || [])].filter((id): id is string => Boolean(id))
}

/** Bots that make up a group chat, for the stacked faces on its name pill. */
export function groupMembers(active: Member | undefined, bots: readonly Agent[] = []): Agent[] {
  if (!active) return []
  if (!isTeam(active)) return []
  return conversationMemberIds(active)
    .map(id => bots.find(bot => bot.id === id))
    .filter((bot): bot is Agent => bot !== undefined)
}

export function mentionBots(active: Member | undefined, readyBots: readonly Agent[], query: string): Agent[] {
  if (!active) return []
  const q = needle(query)
  const inConversation = new Set(conversationMemberIds(active))
  return readyBots
    .filter(bot => !inConversation.has(bot.id) && includesNeedle(`${bot.name} ${bot.title || ''}`, q))
    .slice(0, MENTION_BOT_LIMIT)
}

export function mentionRoutines(routines: readonly Routine[], query: string): Routine[] {
  const q = needle(query)
  return routines
    .filter(routine => includesNeedle(`${routine.title} ${routine.triggerKind || ''}`, q))
    .slice(0, MENTION_ITEM_LIMIT)
}

export function mentionConnectors(connectors: readonly Connector[], query: string): Connector[] {
  const q = needle(query)
  return connectors
    .filter(connector => !connector.revoked && includesNeedle(`${connector.name}`, q))
    .slice(0, MENTION_ITEM_LIMIT)
}

export function skillMatches(skills: readonly Skill[], query: string): Skill[] {
  const q = needle(query)
  return skills
    .filter(skill => skill.enabled && skill.state === ACTIVE_SKILL_STATE && includesNeedle(skill.name, q))
    .slice(0, SKILL_LIMIT)
}

/** Apps shown on the Connect apps pill: apps signed in on the computer first, then live connectors. */
export function connectedApps(computerApps: readonly AppRecord[] = [], connectors: readonly Connector[] = [], nameOf: (id: string) => string = id => id): { id: string, name: string }[] {
  const signedIn = connectedAppList(computerApps, nameOf)
  const live = connectors
    .filter(item => !item.revoked)
    .map(item => ({ id: item.id, name: item.name }))
  return [...signedIn, ...live]
}

function lastMessageTime(history: readonly ChatMessage[] = []): string | undefined {
  return history.at(-1)?.createdAt
}

/** Agent id → ISO time of its latest loaded message, so the sidebar can sort by activity. */
export function activityByAgent(histories: Dict<ChatMessage[]> = {}): Dict<string> {
  const stamps: Dict<string> = {}
  for (const [id, history] of Object.entries(histories)) {
    const stamp = lastMessageTime(history)
    if (stamp) stamps[id] = stamp
  }
  return stamps
}

/** Only inline base64 images are rendered; anything else could point off-site. */
export function safeComputerImage(computer: Pick<ComputerInfo, 'image'> | null | undefined): string {
  const image = computer?.image
  return typeof image === 'string' && SAFE_IMAGE_DATA_URL.test(image) ? image : ''
}

export function isComputerOn(computer: Pick<ComputerInfo, 'state'> | null | undefined): boolean {
  return COMPUTER_ON_STATES.has(computer?.state)
}

export function isTakenOver(computer: Pick<ComputerInfo, 'state'> | null | undefined): boolean {
  return computer?.state === TAKEOVER_STATE
}

export function environmentLabel(environment: Environment | null | undefined): string {
  if (!environment) return NO_ENVIRONMENT_LABEL
  return ENVIRONMENT_LABELS[environment.state] || environment.state
}

export function firstName(session: Pick<Session, 'user'> | null | undefined): string {
  return session?.user?.name?.split(' ')[0] || FALLBACK_GREETING
}

/** An approval the owner can still decide: pending, and raised by this run. */
export function approvalAwaitsDecision(approval: Pick<Approval, 'runId' | 'state'> | undefined, run: Run | undefined): boolean {
  return run !== undefined && run.id === approval?.runId && approval.state === APPROVAL_PENDING
}

/** The approvals of one run still waiting on the owner (the in-chat Approve/Deny cards). */
export function pendingApprovals(approvals: readonly Approval[] = []): Approval[] {
  return approvals.filter(approval => approval.state === APPROVAL_PENDING)
}

/**
 * The newest routine the bot created at or after `since` (an ISO time from the server), or null.
 * Stands in for a "routine created" run event until the server sends one (routine card).
 */
export function routineCreatedSince(routines: readonly Routine[] = [], agentId: string, since: string): Routine | null {
  const from = Date.parse(since)
  if (!agentId || Number.isNaN(from)) return null
  const fresh = routines.filter(routine => routine.agentId === agentId && Date.parse(routine.createdAt ?? '') >= from)
  return fresh.sort((a, b) => Date.parse(b.createdAt ?? '') - Date.parse(a.createdAt ?? ''))[0] || null
}

/**
 * One-tap New bot: the bot shows at the top of the sidebar and its chat opens at once (a draft),
 * then the server answers with the real bot and its welcome. Its computer starts in the background.
 */
import { tick } from 'svelte'
import { botLimitReason } from '../constants.ts'
import { type NewBotAnswer, parseNewBot } from '../answers/agents.ts'
import type { Dict } from '../check.ts'
import type { Agent, AvatarChoice, ChatMessage } from '../types.ts'
import { pickNewBotAvatar } from '../avatars.ts'
import { welcomeIdeas } from '../starterIdeas.ts'
import { fail } from '../format.ts'
import { api } from './client.svelte.ts'
import { updateEnvironment } from './environment.svelte.ts'
import { loadAgents } from './agents.svelte.ts'
import { guardUnsaved } from './unsavedGuard.svelte.ts'
import { botsOf } from './selectors.ts'
import { draftBot, replaceDraftBot } from './draftBots.ts'
import { chat, fileSession, agentLimitReached, requireSession, storageBlocked } from './state.svelte.ts'

const NEW_BOT_PATH = '/api/new-bot'
const PROVISIONING = 'provisioning'
// The first roster refresh after create; loadAgents keeps polling while anything is provisioning.
const FIRST_POLL_MS = 1500
// The welcome arrives like a reply: typing dots first, then the greeting and its ideas together.
const WELCOME_TYPING_MS = 900

/** Why New bot can't run right now, or '' when it can. The server re-checks everything. */
function createBlockReason(): string {
  if (agentLimitReached()) return botLimitReason(requireSession().limits.maxAgents)
  if (storageBlocked()) return chat.storage?.creationBlockedReason || chat.storageError
  return ''
}

/** New bot opens a new chat, so unsaved Details edits for the current bot are asked about first. */
export function startNewBot(): Promise<void> | undefined {
  return guardUnsaved(createNewBot)
}

async function createNewBot(): Promise<void> {
  if (chat.saving) return
  const blocked = createBlockReason()
  chat.createError = blocked
  if (blocked) return
  const key = chat.session?.csrf
  const previousId = chat.selectedId
  const draft = showDraftBot()
  chat.saving = true
  try {
    const data = parseNewBot(await api(NEW_BOT_PATH, { method: 'POST', body: JSON.stringify(newBotBody(draft)) }))
    if (fileSession(key)) await adoptNewBot(draft.id, data)
  } catch (error) {
    if (fileSession(key)) dropDraftBot(draft.id, previousId, fail(error))
  } finally {
    if (fileSession(key)) chat.saving = false
  }
}

function newBotBody(draft: AvatarChoice) {
  return { avatarShape: draft.avatarShape, avatarColor: draft.avatarColor, ideas: welcomeIdeas(chat.onboarding?.goal) }
}

function showDraftBot(): Agent {
  const draft = draftBot(pickNewBotAvatar(botsOf(chat.agents)))
  chat.agents = [draft, ...chat.agents]
  chat.histories = { ...chat.histories, [draft.id]: [] }
  chat.selectedId = draft.id
  chat.mobileRail = false
  return draft
}

async function adoptNewBot(draftId: string, data: NewBotAnswer): Promise<void> {
  if ('environment' in data) updateEnvironment(data.environment)
  // A roster refresh that started before the create would not know this bot yet.
  chat.agentsVersion += 1
  chat.agents = replaceDraftBot(chat.agents, draftId, { ...data.agent, lastMessagePreview: '' })
  chat.histories = { ...withoutDraft(chat.histories, draftId), [data.agent.id]: [] }
  revealWelcome(data.agent, data.messages)
  if (chat.selectedId === draftId) chat.selectedId = data.agent.id
  if (data.agent.status === PROVISIONING) pollRoster()
  await tick()
  chat.composer?.focus()
}

function revealWelcome(agent: Agent, messages: ChatMessage[]): void {
  chat.typingWelcomeId = agent.id
  setTimeout(() => showWelcome(agent, messages), WELCOME_TYPING_MS)
}

function showWelcome(agent: Agent, messages: ChatMessage[]): void {
  chat.typingWelcomeId = ''
  chat.histories = { ...chat.histories, [agent.id]: messages }
  chat.agents = chat.agents.map(row => row.id === agent.id ? { ...row, lastMessagePreview: agent.lastMessagePreview } : row)
}

function dropDraftBot(draftId: string, previousId: string, reason: string): void {
  chat.agents = chat.agents.filter(agent => agent.id !== draftId)
  chat.histories = withoutDraft(chat.histories, draftId)
  if (chat.selectedId === draftId) chat.selectedId = stillListed(previousId) || chat.agents[0]?.id || ''
  chat.createError = reason
}

function stillListed(id: string): string {
  return chat.agents.some(agent => agent.id === id) ? id : ''
}

function withoutDraft(histories: Dict<ChatMessage[]>, draftId: string): Dict<ChatMessage[]> {
  const { [draftId]: _draft, ...rest } = histories
  return rest
}

function pollRoster(): void {
  clearTimeout(chat.provisioningPoll)
  chat.provisioningPoll = setTimeout(() => { if (chat.alive && chat.session) loadAgents() }, FIRST_POLL_MS)
}

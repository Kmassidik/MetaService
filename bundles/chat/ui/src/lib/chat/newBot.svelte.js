/**
 * One-tap New bot: the bot shows at the top of the sidebar and its chat opens at once (a draft),
 * then the server answers with the real bot and its welcome. Its computer starts in the background.
 */
import { tick } from 'svelte'
import { botLimitReason } from '../constants.js'
import { pickNewBotAvatar } from '../avatars.js'
import { welcomeIdeas } from '../starterIdeas.js'
import { fail } from '../format.js'
import { api } from './client.svelte.js'
import { updateEnvironment } from './environment.svelte.js'
import { loadAgents } from './agents.svelte.js'
import { guardUnsaved } from './unsavedGuard.svelte.js'
import { botsOf } from './selectors.js'
import { draftBot, replaceDraftBot } from './draftBots.js'
import { chat, fileSession, agentLimitReached, planLimits, storageBlocked } from './state.svelte.js'

const NEW_BOT_PATH = '/api/new-bot'
const PROVISIONING = 'provisioning'
// The first roster refresh after create; loadAgents keeps polling while anything is provisioning.
const FIRST_POLL_MS = 1500
// The welcome arrives like a reply: typing dots first, then the greeting and its ideas together.
const WELCOME_TYPING_MS = 900

/** Why New bot can't run right now, or '' when it can. The server re-checks everything. */
function createBlockReason() {
  if (agentLimitReached()) return botLimitReason(planLimits().maxAgents)
  if (storageBlocked()) return chat.storage?.creationBlockedReason || chat.storageError
  return ''
}

/** New bot opens a new chat, so unsaved Details edits for the current bot are asked about first. */
export function startNewBot() {
  return guardUnsaved(createNewBot)
}

async function createNewBot() {
  if (chat.saving) return
  const blocked = createBlockReason()
  chat.createError = blocked
  if (blocked) return
  const key = chat.session?.csrf
  const previousId = chat.selectedId
  const draft = showDraftBot()
  chat.saving = true
  try {
    const data = await api(NEW_BOT_PATH, { method: 'POST', body: JSON.stringify(newBotBody(draft)) })
    if (fileSession(key)) await adoptNewBot(draft.id, data)
  } catch (error) {
    if (fileSession(key)) dropDraftBot(draft.id, previousId, fail(error))
  } finally {
    if (fileSession(key)) chat.saving = false
  }
}

function newBotBody(draft) {
  return { avatarShape: draft.avatarShape, avatarColor: draft.avatarColor, ideas: welcomeIdeas(chat.onboarding?.goal) }
}

function showDraftBot() {
  const draft = draftBot(pickNewBotAvatar(botsOf(chat.agents)))
  chat.agents = [draft, ...chat.agents]
  chat.histories = { ...chat.histories, [draft.id]: [] }
  chat.selectedId = draft.id
  chat.mobileRail = false
  return draft
}

async function adoptNewBot(draftId, data) {
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

function revealWelcome(agent, messages) {
  chat.typingWelcomeId = agent.id
  setTimeout(() => showWelcome(agent, messages), WELCOME_TYPING_MS)
}

function showWelcome(agent, messages) {
  chat.typingWelcomeId = ''
  chat.histories = { ...chat.histories, [agent.id]: messages }
  chat.agents = chat.agents.map(row => row.id === agent.id ? { ...row, lastMessagePreview: agent.lastMessagePreview } : row)
}

function dropDraftBot(draftId, previousId, reason) {
  chat.agents = chat.agents.filter(agent => agent.id !== draftId)
  chat.histories = withoutDraft(chat.histories, draftId)
  if (chat.selectedId === draftId) chat.selectedId = stillListed(previousId) || chat.agents[0]?.id || ''
  chat.createError = reason
}

function stillListed(id) {
  return chat.agents.some(agent => agent.id === id) ? id : ''
}

function withoutDraft(histories, draftId) {
  const { [draftId]: _draft, ...rest } = histories
  return rest
}

function pollRoster() {
  clearTimeout(chat.provisioningPoll)
  chat.provisioningPoll = setTimeout(() => { if (chat.alive && chat.session) loadAgents() }, FIRST_POLL_MS)
}

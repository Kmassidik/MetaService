/**
 * Messages typed while a bot works: queued on its running task (it runs as the next turn) and shown
 * at once as the owner's bubbles until the chat has them. Pure rules live in ../sendMode.js.
 */
import { fail } from '../format.js'
import { SEND_MODE, followUpRequest, sendMode } from '../sendMode.js'
import { api } from './client.svelte.js'
import { chat, fileSession, runIsActive, selectedAgent, selectedRun } from './state.svelte.js'

const BOT_WORKING = 'running'
const RETRY_HINT = 'Your message is back in the box.'
const LOCAL_ID_PREFIX = 'local-'

// Until the server answers, a bubble needs its own key (randomUUID needs a secure context).
let localCount = 0
const nextLocalId = () => `${LOCAL_ID_PREFIX}${++localCount}`

export function currentSendMode() {
  const run = selectedRun()
  return sendMode({ runActive: runIsActive(run), runState: run?.state, botBusy: selectedAgent()?.status === BOT_WORKING })
}

function setFollowUps(agentId, items) {
  chat.followUps = { ...chat.followUps, [agentId]: items }
}

function followUpsOf(agentId) {
  return chat.followUps[agentId] || []
}

function confirm(agentId, localId, message) {
  setFollowUps(agentId, followUpsOf(agentId).map(item => item.id === localId ? { ...item, id: message.id, confirmed: true } : item))
}

function restoreDraft(agentId, localId, text, error) {
  setFollowUps(agentId, followUpsOf(agentId).filter(item => item.id !== localId))
  chat.drafts = { ...chat.drafts, [agentId]: chat.drafts[agentId] || text }
  chat.runActionErrors = { ...chat.runActionErrors, [agentId]: `${fail(error)} ${RETRY_HINT}` }
}

/** Queue `text` on the selected bot's running task; the bubble shows before the server answers. */
export async function sendFollowUp(text) {
  const agentId = chat.selectedId
  const run = selectedRun()
  if (!run || !text || currentSendMode() !== SEND_MODE.followUp) return
  const key = chat.session.csrf
  const item = { id: nextLocalId(), runId: run.id, text, confirmed: false }
  setFollowUps(agentId, [...followUpsOf(agentId), item])
  chat.drafts = { ...chat.drafts, [agentId]: '' }
  chat.runActionErrors = { ...chat.runActionErrors, [agentId]: '' }
  try {
    const request = followUpRequest(run.id, text)
    const data = await api(request.path, { method: 'POST', body: JSON.stringify(request.body) })
    if (fileSession(key)) confirm(agentId, item.id, data.message)
  } catch (error) {
    if (fileSession(key)) restoreDraft(agentId, item.id, text, error)
  }
}

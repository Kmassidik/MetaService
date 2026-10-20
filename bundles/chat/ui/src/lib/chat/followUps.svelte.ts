/**
 * Messages typed while a bot works: queued on its running task (it runs as the next turn) and shown
 * at once as the owner's bubbles until the chat has them. Pure rules live in ../sendMode.js.
 */
import { parseQueued } from '../answers/agents.ts'
import { fail } from '../format.ts'
import { SEND_MODE, type SendModeId, followUpRequest, sendMode } from '../sendMode.ts'
import { api } from './client.svelte.ts'
import type { FollowUp } from '../types.ts'
import { chat, fileSession, requireSession, runIsActive, selectedAgent, selectedRun } from './state.svelte.ts'

const BOT_WORKING = 'running'
const RETRY_HINT = 'Your message is back in the box.'
const LOCAL_ID_PREFIX = 'local-'

// Until the server answers, a bubble needs its own key (randomUUID needs a secure context).
let localCount = 0
const nextLocalId = (): string => `${LOCAL_ID_PREFIX}${++localCount}`

export function currentSendMode(): SendModeId {
  const run = selectedRun()
  return sendMode({ runActive: runIsActive(run), runState: run?.state, botBusy: selectedAgent()?.status === BOT_WORKING })
}

function setFollowUps(agentId: string, items: FollowUp[]): void {
  chat.followUps = { ...chat.followUps, [agentId]: items }
}

function followUpsOf(agentId: string): FollowUp[] {
  return chat.followUps[agentId] || []
}

function confirm(agentId: string, localId: string, message: { id: string }): void {
  setFollowUps(agentId, followUpsOf(agentId).map(item => item.id === localId ? { ...item, id: message.id, confirmed: true } : item))
}

function restoreDraft(agentId: string, localId: string, text: string, error: unknown): void {
  setFollowUps(agentId, followUpsOf(agentId).filter(item => item.id !== localId))
  chat.drafts = { ...chat.drafts, [agentId]: chat.drafts[agentId] || text }
  chat.runActionErrors = { ...chat.runActionErrors, [agentId]: `${fail(error)} ${RETRY_HINT}` }
}

/** Queue `text` on the selected bot's running task; the bubble shows before the server answers. */
export async function sendFollowUp(text: string): Promise<void> {
  const agentId = chat.selectedId
  const run = selectedRun()
  if (!run || !text || currentSendMode() !== SEND_MODE.followUp) return
  const key = requireSession().csrf
  const item: FollowUp = { id: nextLocalId(), runId: run.id, text, confirmed: false }
  setFollowUps(agentId, [...followUpsOf(agentId), item])
  chat.drafts = { ...chat.drafts, [agentId]: '' }
  chat.runActionErrors = { ...chat.runActionErrors, [agentId]: '' }
  try {
    const request = followUpRequest(run.id, text)
    const data = parseQueued(await api(request.path, { method: 'POST', body: JSON.stringify(request.body) }))
    if (fileSession(key)) confirm(agentId, item.id, data.message)
  } catch (error) {
    if (fileSession(key)) restoreDraft(agentId, item.id, text, error)
  }
}

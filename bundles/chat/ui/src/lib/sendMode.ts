/**
 * What Send does. With no task running it starts a turn; while a bot works it queues a text-only
 * follow-up on that task (it runs as the next turn when the task ends), Grok-style.
 */
import type { ChatMessage, FollowUp, Run } from './types.ts'

export const SEND_MODE = Object.freeze({ turn: 'turn', followUp: 'follow-up', closed: 'closed' })
export type SendModeId = (typeof SEND_MODE)[keyof typeof SEND_MODE]

/** The run-message kind the server delivers after the current task, as its next turn. */
export const FOLLOW_UP_KIND = 'queued'

export const FOLLOW_UP_STATE = Object.freeze({
  sending: 'sending',
  queued: 'queued',
  dropped: 'dropped',
  delivered: 'delivered',
})

export type FollowUpStateId = (typeof FOLLOW_UP_STATE)[keyof typeof FOLLOW_UP_STATE]

/** A follow-up with where it stands. */
export interface WaitingFollowUp extends FollowUp {
  state: FollowUpStateId
}

const CANCELLING = 'cancelling'
// Stopped tasks discard their queued follow-ups; finished or failed ones run them.
const DISCARDING_RUN_STATES: readonly (string | undefined)[] = ['cancelled', 'interrupted']

interface SendModeInputs {
  runActive: boolean
  runState?: string | undefined
  /** The bot says it is working but its task isn't known yet. */
  botBusy: boolean
}

export function sendMode({ runActive, runState, botBusy }: SendModeInputs): SendModeId {
  if (runActive) return runState === CANCELLING ? SEND_MODE.closed : SEND_MODE.followUp
  return botBusy ? SEND_MODE.closed : SEND_MODE.turn
}

/** A turn takes text or files; a follow-up takes text only (files wait until the task ends). */
export function hasSendableInput(mode: SendModeId, { text = '', attachmentCount = 0 }: { text?: string, attachmentCount?: number }): boolean {
  if (mode === SEND_MODE.turn) return Boolean(text || attachmentCount)
  if (mode === SEND_MODE.followUp) return Boolean(text) && attachmentCount === 0
  return false
}

export function followUpRequest(runId: string, text: string): { path: string, body: { text: string, kind: string } } {
  return { path: `/api/runs/${encodeURIComponent(runId)}/messages`, body: { text, kind: FOLLOW_UP_KIND } }
}

const timeOf = (value: string | undefined): number => Date.parse(value ?? '') || 0

// The server writes the follow-up into the chat as the owner's message when it starts its turn.
function deliveredIn(history: readonly ChatMessage[], item: FollowUp, run: Run | undefined): boolean {
  const since = timeOf(run?.createdAt)
  return history.some(message => message.role === 'user' && message.text === item.text && timeOf(message.createdAt) > since)
}

/** Where one follow-up the owner sent stands, from the chat and the task it was queued on. */
export function followUpState(item: FollowUp, history: readonly ChatMessage[] = [], runs: readonly Run[] = []): FollowUpStateId {
  if (!item.confirmed) return FOLLOW_UP_STATE.sending
  const run = runs.find(candidate => candidate.id === item.runId)
  if (deliveredIn(history, item, run)) return FOLLOW_UP_STATE.delivered
  return DISCARDING_RUN_STATES.includes(run?.state) ? FOLLOW_UP_STATE.dropped : FOLLOW_UP_STATE.queued
}

/** The follow-ups still to show as the owner's bubbles, each with its state. */
export function waitingFollowUps(items: readonly FollowUp[] = [], history: readonly ChatMessage[] = [], runs: readonly Run[] = []): WaitingFollowUp[] {
  return items
    .map(item => ({ ...item, state: followUpState(item, history, runs) }))
    .filter(item => item.state !== FOLLOW_UP_STATE.delivered)
}

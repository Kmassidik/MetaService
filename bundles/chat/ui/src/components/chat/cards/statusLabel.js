// The one-line "what is the bot doing" status, replacing the step list.

export const STATUS_TONE = { working: 'working', waiting: 'waiting', problem: 'problem', info: 'info' }

const CANCELLING = 'cancelling'
const AWAITING_APPROVAL = 'awaiting_approval'

function working(name, computerLive) {
  const doing = computerLive ? 'is using the computer' : 'is working'
  return { text: `${name} ${doing}…`, tone: STATUS_TONE.working }
}

function waitingLabel({ run, waitingForAnswer, waitingForInput, approvalPending }) {
  if (waitingForAnswer) return { text: 'Waiting for your answer', tone: STATUS_TONE.waiting }
  if (waitingForInput) return { text: 'Waiting for you', tone: STATUS_TONE.waiting }
  if (approvalPending || run?.state === AWAITING_APPROVAL) return { text: 'Waiting for your approval', tone: STATUS_TONE.waiting }
  return null
}

/**
 * @param {{ name: string, run?: object, runActive: boolean, sending: boolean,
 *   waitingForAnswer: boolean, waitingForInput?: boolean, approvalPending: boolean, computerLive: boolean,
 *   notice?: string }} state
 * @returns {{ text: string, tone: string } | null}
 */
export function statusLabel(state) {
  const waiting = waitingLabel(state)
  if (waiting) return waiting
  if (state.run?.state === CANCELLING) return { text: 'Stopping…', tone: STATUS_TONE.working }
  if (state.runActive || state.sending) return working(state.name, state.computerLive)
  if (state.run?.error) return { text: 'Couldn’t reply — try again', tone: STATUS_TONE.problem }
  if (state.notice) return { text: state.notice, tone: STATUS_TONE.info }
  return null
}

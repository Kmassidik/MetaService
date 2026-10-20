/** Checks for the answers about tasks (runs), their public events and approvals. */
import {
  anything, arrayOf, dictOf, isBoolean, isNumber, isString, objectOf, objectWithOptional, parseAnswer,
} from '../check.ts'
import type { Approval, Ask, AskOption, EventPayload, Run, RunCard, RunEvent } from '../types.ts'

export const isRun = objectWithOptional<Run>(
  {
    id: isString, agentId: isString, state: isString, createdAt: isString, updatedAt: isString,
    firstEventSequence: isNumber, lastEventSequence: isNumber,
  },
  { model: isString, error: isString, attachmentIds: arrayOf(isString) },
)

const isPayload = dictOf(anything)

const isRunEvent = objectWithOptional<RunEvent>(
  { sequence: isNumber, kind: isString, createdAt: isString },
  { runId: isString, payload: isPayload },
)

const isApproval = objectWithOptional<Approval>(
  { id: isString, runId: isString, state: isString, parametersSHA256: isString },
  { tool: isString, action: isString, destination: isString, parametersJSON: isString, expiresAt: isString },
)

interface RunList {
  runs: Run[]
}

interface EventPage {
  events: RunEvent[]
  run: Run
}

interface ApprovalList {
  approvals: Approval[]
}

interface RunAnswer {
  run?: Run
}

const isRunList = objectOf<RunList>({ runs: arrayOf(isRun) })
const isEventPage = objectOf<EventPage>({ events: arrayOf(isRunEvent), run: isRun })
const isApprovalList = objectOf<ApprovalList>({ approvals: arrayOf(isApproval) })
const isRunAnswer = objectWithOptional<RunAnswer>({}, { run: isRun })

export const parseRuns = (answer: unknown): Run[] => parseAnswer(isRunList, answer, 'task list').runs
export const parseEventPage = (answer: unknown): EventPage => parseAnswer(isEventPage, answer, 'task events')
export const parseApprovals = (answer: unknown): Approval[] => parseAnswer(isApprovalList, answer, 'approval list').approvals
export const parseRunAnswer = (answer: unknown): RunAnswer => parseAnswer(isRunAnswer, answer, 'task')

/** A profile change a bot made to itself (a `profile` event). */
export interface ProfileChange {
  agentId: string
  name?: string
  title?: string
  summary?: string
  changed?: string[]
  notice?: string
}

const isAskOption = objectOf<AskOption>({ id: isString, label: isString })
const isAskCandidate = objectWithOptional<Ask>(
  { askId: isString, options: arrayOf(isAskOption), runId: isString, sequence: isNumber },
  { mode: isString, skippable: isBoolean, prompt: isString, hint: isString, helper: isString },
)
const isCardCandidate = objectWithOptional<RunCard>(
  { cardId: isString, kind: isString, runId: isString },
  {
    subject: isString, appName: isString, target: isString, change: isString, url: isString,
    title: isString, reason: isString, name: isString, text: isString, service: isString,
  },
)
const isProfileChange = objectWithOptional<ProfileChange>(
  { agentId: isString },
  { name: isString, title: isString, summary: isString, changed: arrayOf(isString), notice: isString },
)

const MIN_ASK_OPTIONS = 2

/** A payload without its null fields: the server may send `null` for "none". */
function withoutNulls(payload: EventPayload): EventPayload {
  return Object.fromEntries(Object.entries(payload).filter(([, value]) => value !== null))
}

type EventLook = Pick<RunEvent, 'kind' | 'payload'>

/** The question an `ask` event holds, or null when it is not a well-formed question of this run. */
export function askOf(event: EventLook & Pick<RunEvent, 'sequence'>, runId: string): Ask | null {
  if (event.kind !== 'ask' || !event.payload) return null
  const candidate = { ...withoutNulls(event.payload), runId, sequence: event.sequence }
  if (!isAskCandidate(candidate) || !candidate.askId) return null
  return candidate.options.length >= MIN_ASK_OPTIONS ? candidate : null
}

/** The card a `card` event holds, or null when it has no id. */
export function cardOf(event: EventLook, runId: string): RunCard | null {
  if (event.kind !== 'card' || !event.payload) return null
  const candidate = { ...withoutNulls(event.payload), runId }
  return isCardCandidate(candidate) && candidate.cardId ? candidate : null
}

/** The ids of asks the owner already answered (`ask_answered` events). */
export function answeredAskIds(events: readonly EventLook[]): Set<string> {
  const ids = new Set<string>()
  for (const event of events) {
    const askId = event.kind === 'ask_answered' ? event.payload?.askId : undefined
    if (typeof askId === 'string' && askId) ids.add(askId)
  }
  return ids
}

/** The profile change a `profile` event holds, or null. */
export function profileChangeOf(event: EventLook): ProfileChange | null {
  if (event.kind !== 'profile' || !event.payload) return null
  const payload = withoutNulls(event.payload)
  return isProfileChange(payload) && payload.agentId ? payload : null
}

export type { EventPage, EventPayload }

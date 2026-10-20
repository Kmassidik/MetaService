// App tool cards (PRD-integrations): which run cards wait for the owner, and the result cards.
// `app_send` asks for Send / Edit / Cancel on one exact message; `app_result` is a record of what
// the tool did (no answer needed). Pure, so it is unit-tested.
import { type Check, isBoolean, isString, objectWithOptional } from './check.ts'
import type { AppResult, RunCard, RunEvent } from './types.ts'

export const APP_SEND = 'app_send'
export const APP_RESULT = 'app_result'
// Cards that are records, never waiting for the owner.
const RECORD_KINDS = new Set([APP_RESULT])
export const MESSAGE_MAX_CHARS = 2000
const CARD_EVENT = 'card'
const CARD_RESOLVED_EVENT = 'card_resolved'

const DELIVERY_LABELS: Readonly<Record<string, string>> = { sent: 'Sent ✓', delivered: 'Delivered ✓✓', read: 'Read ✓✓' }
const MESSAGE = 'message'
const CHANGE_DONE: Readonly<Record<string, string>> = { create: 'Event created ✓', move: 'Event moved ✓', cancel: 'Event cancelled ✓' }
const CHANGE_ASK: Readonly<Record<string, string>> = { create: 'Create', move: 'Move', cancel: 'Cancel' }

type CardLook = Pick<RunCard, 'appName' | 'target' | 'change' | 'subject'>
type ResultLook = Pick<AppResult, 'ok' | 'target' | 'change' | 'delivery' | 'reason' | 'subject'>
type EventLook = Pick<RunEvent, 'kind' | 'payload'>

interface Wording {
  ask: (card: CardLook) => string
  label: (card: CardLook) => string
  where: (card: CardLook) => string
  done: (result: ResultLook) => string
  title: (result: ResultLook, app: string) => string
  link: string
  editable: boolean
}

const isAppResult: Check<AppResult> = objectWithOptional<AppResult>(
  { kind: isString },
  {
    ok: isBoolean, app: isString, appName: isString, subject: isString, target: isString,
    change: isString, delivery: isString, reason: isString,
  },
)

// How a card reads, by what the app sends (the card's `subject`, from Chat's AppToolCatalog; cards
// from before it are messages). `change` is a calendar card's create / move / cancel.
const MESSAGE_WORDING: Wording = {
  ask: card => `Send on ${card.appName} to ${card.target}?`,
  label: card => `Approve message to ${card.target}`,
  where: card => `From your ${card.appName} · to ${card.target}`,
  done: result => DELIVERY_LABELS[result.delivery ?? ''] || 'Sent',
  title: (result, app) => (result.ok ? `Sent to ${result.target} on ${app}` : `Not sent to ${result.target} on ${app}`),
  link: 'Open chat',
  editable: true,
}

const WORDING: Readonly<Record<string, Wording>> = Object.freeze({
  message: MESSAGE_WORDING,
  email: {
    ask: card => `Send email to ${card.target}?`,
    label: card => `Approve email to ${card.target}`,
    where: card => `From your ${card.appName} · to ${card.target}`,
    done: () => 'Email sent ✓',
    title: (result, app) => (result.ok ? `Emailed ${result.target} from ${app}` : `Email to ${result.target} not sent`),
    link: 'Open email',
    editable: true,
  },
  post: {
    ask: card => `Post on ${card.appName}?`,
    label: card => `Approve post on ${card.appName}`,
    where: card => `From your ${card.appName} · to ${card.target}`,
    done: () => 'Posted ✓',
    title: (result, app) => (result.ok ? `Posted on ${app}` : `Not posted on ${app}`),
    link: 'Open post',
    editable: true,
  },
  event: {
    ask: card => `${CHANGE_ASK[card.change ?? ''] || 'Change'} event on ${card.appName}?`,
    label: card => `Approve calendar change: ${card.target}`,
    where: card => `Your ${card.appName} · ${card.target}`,
    done: result => CHANGE_DONE[result.change ?? ''] || 'Event updated ✓',
    title: (result, app) => (result.ok ? `${result.target} · ${app}` : `${app} not changed: ${result.target}`),
    link: 'Open event',
    // The calendar applies only the exact card: an edited card would change nothing.
    editable: false,
  },
})

const wording = (card: Pick<CardLook, 'subject'>): Wording => WORDING[card.subject ?? MESSAGE] ?? MESSAGE_WORDING

/** The approval card's question, e.g. "Send on WhatsApp to Febi?" or "Move event on Google Calendar?". */
export const approvalTitle = (card: CardLook): string => wording(card).ask(card)
/** The approval card's accessible name. */
export const approvalLabel = (card: CardLook): string => wording(card).label(card)
/** The line under the approval card's text: whose app and who or what it is for. */
export const approvalWhere = (card: CardLook): string => wording(card).where(card)
/** Whether the owner may edit the text before Send (not a calendar card). */
export const approvalEditable = (card: CardLook): boolean => wording(card).editable
/** The result card's link label: "Open chat", "Open email", "Open post" or "Open event". */
export const resultLinkLabel = (result: AppResult): string => wording(result).link

/** Card ids the server already resolved (card_resolved events), e.g. after a reload. */
export function resolvedCardIds(events: readonly EventLook[] = []): Set<string> {
  const ids = new Set<string>()
  for (const event of events) {
    const cardId = event.kind === CARD_RESOLVED_EVENT ? event.payload?.cardId : undefined
    if (typeof cardId === 'string' && cardId) ids.add(cardId)
  }
  return ids
}

/** Whether a published card still waits for the owner. */
export function cardAwaitsOwner(
  payload: Pick<RunCard, 'kind' | 'cardId'>,
  resolvedLocally: Readonly<Record<string, string>>,
  resolvedOnServer: ReadonlySet<string>,
): boolean {
  return !RECORD_KINDS.has(payload.kind) && !resolvedLocally[payload.cardId] && !resolvedOnServer.has(payload.cardId)
}

/** The run's result cards, oldest first. */
export function appResults(events: readonly EventLook[] = []): AppResult[] {
  return events.flatMap(event => (event.kind === CARD_EVENT && isAppResult(event.payload) && event.payload.kind === APP_RESULT ? [event.payload] : []))
}

/** The proof line of a result card: "Delivered ✓✓", "Email sent ✓", "Event moved ✓"…, or the reason it did not go out. */
export function resultLine(result: ResultLook): string {
  if (!result.ok) return result.reason || 'Not sent.'
  return wording(result).done(result)
}

/** The result card's title, e.g. "Sent to Febi on WhatsApp", "Posted on X". */
export function resultTitle(result: ResultLook & Pick<AppResult, 'app' | 'appName'>): string {
  return wording(result).title(result, result.appName || result.app || '')
}

/** The text the Send button sends: the owner's edit when it is non-empty and within the limit. */
export function messageToSend(draft: string, edited: string | null | undefined): { text: string, valid: boolean } {
  if (edited === null || edited === undefined) return { text: draft, valid: Boolean(draft.trim()) }
  return { text: edited, valid: Boolean(edited.trim()) && edited.length <= MESSAGE_MAX_CHARS }
}

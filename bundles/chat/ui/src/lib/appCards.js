// App tool cards (PRD-integrations): which run cards wait for the owner, and the result cards.
// `app_send` asks for Send / Edit / Cancel on one exact message; `app_result` is a record of what
// the tool did (no answer needed). Pure, so it is unit-tested.

export const APP_SEND = 'app_send'
export const APP_RESULT = 'app_result'
// Cards that are records, never waiting for the owner.
const RECORD_KINDS = new Set([APP_RESULT])
export const MESSAGE_MAX_CHARS = 2000

const DELIVERY_LABELS = { sent: 'Sent ✓', delivered: 'Delivered ✓✓', read: 'Read ✓✓' }
const MESSAGE = 'message'
const CHANGE_DONE = { create: 'Event created ✓', move: 'Event moved ✓', cancel: 'Event cancelled ✓' }
const CHANGE_ASK = { create: 'Create', move: 'Move', cancel: 'Cancel' }

// How a card reads, by what the app sends (the card's `subject`, from Chat's AppToolCatalog; cards
// from before it are messages). `change` is a calendar card's create / move / cancel.
const WORDING = Object.freeze({
  message: {
    ask: card => `Send on ${card.appName} to ${card.target}?`,
    label: card => `Approve message to ${card.target}`,
    where: card => `From your ${card.appName} · to ${card.target}`,
    done: result => DELIVERY_LABELS[result.delivery] || 'Sent',
    title: (result, app) => (result.ok ? `Sent to ${result.target} on ${app}` : `Not sent to ${result.target} on ${app}`),
    link: 'Open chat',
    editable: true,
  },
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
    ask: card => `${CHANGE_ASK[card.change] || 'Change'} event on ${card.appName}?`,
    label: card => `Approve calendar change: ${card.target}`,
    where: card => `Your ${card.appName} · ${card.target}`,
    done: result => CHANGE_DONE[result.change] || 'Event updated ✓',
    title: (result, app) => (result.ok ? `${result.target} · ${app}` : `${app} not changed: ${result.target}`),
    link: 'Open event',
    // The calendar applies only the exact card: an edited card would change nothing.
    editable: false,
  },
})

const wording = card => WORDING[card.subject] || WORDING[MESSAGE]

/** The approval card's question, e.g. "Send on WhatsApp to Febi?" or "Move event on Google Calendar?". */
export const approvalTitle = card => wording(card).ask(card)
/** The approval card's accessible name. */
export const approvalLabel = card => wording(card).label(card)
/** The line under the approval card's text: whose app and who or what it is for. */
export const approvalWhere = card => wording(card).where(card)
/** Whether the owner may edit the text before Send (not a calendar card). */
export const approvalEditable = card => wording(card).editable
/** The result card's link label: "Open chat", "Open email", "Open post" or "Open event". */
export const resultLinkLabel = result => wording(result).link

/** Card ids the server already resolved (card_resolved events), e.g. after a reload. */
export function resolvedCardIds(events = []) {
  return new Set(events.filter(event => event.kind === 'card_resolved' && event.payload?.cardId).map(event => event.payload.cardId))
}

/** Whether a published card still waits for the owner. */
export function cardAwaitsOwner(payload, resolvedLocally, resolvedOnServer) {
  return !RECORD_KINDS.has(payload.kind) && !resolvedLocally[payload.cardId] && !resolvedOnServer.has(payload.cardId)
}

/** The run's result cards, oldest first. */
export function appResults(events = []) {
  return events.filter(event => event.kind === 'card' && event.payload?.kind === APP_RESULT).map(event => event.payload)
}

/** The proof line of a result card: "Delivered ✓✓", "Email sent ✓", "Event moved ✓"…, or the reason it did not go out. */
export function resultLine(result) {
  if (!result.ok) return result.reason || 'Not sent.'
  return wording(result).done(result)
}

/** The result card's title, e.g. "Sent to Febi on WhatsApp", "Posted on X". */
export function resultTitle(result) {
  return wording(result).title(result, result.appName || result.app)
}

/** The text the Send button sends: the owner's edit when it is non-empty and within the limit. */
export function messageToSend(draft, edited) {
  if (edited === null || edited === undefined) return { text: draft, valid: Boolean(draft.trim()) }
  return { text: edited, valid: Boolean(edited.trim()) && edited.length <= MESSAGE_MAX_CHARS }
}

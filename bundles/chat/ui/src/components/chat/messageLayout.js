// Pure layout rules for the message list: time dividers and sender grouping.

const MINUTE_MS = 60 * 1000
const DAY_MS = 24 * 60 * MINUTE_MS
/** A new time divider appears after a silence longer than this. */
export const TIME_GAP_MS = 30 * MINUTE_MS

const TIME_FORMAT = { hour: 'numeric', minute: '2-digit' }
const DATE_FORMAT = { weekday: 'short', month: 'short', day: 'numeric' }

function toTime(value) {
  const stamp = new Date(value).valueOf()
  return Number.isNaN(stamp) ? null : stamp
}

function startOfDay(stamp) {
  const date = new Date(stamp)
  date.setHours(0, 0, 0, 0)
  return date.valueOf()
}

/** "Today 2:34 PM", "Yesterday 9:05 AM" or "Mon, Sep 28 2:34 PM". */
export function dividerLabel(value, now = Date.now()) {
  const stamp = toTime(value)
  if (stamp === null) return ''
  const clock = new Date(stamp).toLocaleTimeString([], TIME_FORMAT)
  const daysAgo = Math.round((startOfDay(now) - startOfDay(stamp)) / DAY_MS)
  if (daysAgo === 0) return `Today ${clock}`
  if (daysAgo === 1) return `Yesterday ${clock}`
  return `${new Date(stamp).toLocaleDateString([], DATE_FORMAT)} ${clock}`
}

function needsDivider(previous, message) {
  if (!previous) return true
  const before = toTime(previous.createdAt)
  const after = toTime(message.createdAt)
  if (before === null || after === null) return false
  return after - before > TIME_GAP_MS
}

function sameSpeaker(previous, message) {
  return Boolean(previous) && previous.role === message.role && previous.role !== 'system'
}

/**
 * Annotates each message with `divider` (label or '') and `groupStart`
 * (true when a new speaker begins, or the run is broken by a divider).
 */
export function layoutMessages(messages, now = Date.now()) {
  return messages.map((message, index) => {
    const previous = messages[index - 1]
    const divider = needsDivider(previous, message) ? dividerLabel(message.createdAt, now) : ''
    const groupStart = Boolean(divider) || !sameSpeaker(previous, message)
    return { message, divider, groupStart }
  })
}

// Pure layout rules for the message list: time dividers and sender grouping.
import type { ChatMessage } from '../../lib/types.ts'

/** A message with the layout facts the list draws around it. */
export interface LaidOutMessage {
  message: ChatMessage
  divider: string
  groupStart: boolean
}

const MINUTE_MS = 60 * 1000
const DAY_MS = 24 * 60 * MINUTE_MS
/** A new time divider appears after a silence longer than this. */
export const TIME_GAP_MS = 30 * MINUTE_MS

const TIME_FORMAT: Intl.DateTimeFormatOptions = { hour: 'numeric', minute: '2-digit' }
const DATE_FORMAT: Intl.DateTimeFormatOptions = { weekday: 'short', month: 'short', day: 'numeric' }

function toTime(value: string): number | null {
  const stamp = new Date(value).valueOf()
  return Number.isNaN(stamp) ? null : stamp
}

function startOfDay(stamp: number): number {
  const date = new Date(stamp)
  date.setHours(0, 0, 0, 0)
  return date.valueOf()
}

/** "Today 2:34 PM", "Yesterday 9:05 AM" or "Mon, Sep 28 2:34 PM". */
export function dividerLabel(value: string, now = Date.now()): string {
  const stamp = toTime(value)
  if (stamp === null) return ''
  const clock = new Date(stamp).toLocaleTimeString([], TIME_FORMAT)
  const daysAgo = Math.round((startOfDay(now) - startOfDay(stamp)) / DAY_MS)
  if (daysAgo === 0) return `Today ${clock}`
  if (daysAgo === 1) return `Yesterday ${clock}`
  return `${new Date(stamp).toLocaleDateString([], DATE_FORMAT)} ${clock}`
}

function needsDivider(previous: ChatMessage | undefined, message: ChatMessage): boolean {
  if (!previous) return true
  const before = toTime(previous.createdAt)
  const after = toTime(message.createdAt)
  if (before === null || after === null) return false
  return after - before > TIME_GAP_MS
}

function sameSpeaker(previous: ChatMessage | undefined, message: ChatMessage): boolean {
  return previous !== undefined && previous.role === message.role && previous.role !== 'system'
}

/**
 * Annotates each message with `divider` (label or '') and `groupStart`
 * (true when a new speaker begins, or the run is broken by a divider).
 */
export function layoutMessages(messages: readonly ChatMessage[], now = Date.now()): LaidOutMessage[] {
  return messages.map((message, index) => {
    const previous = messages[index - 1]
    const divider = needsDivider(previous, message) ? dividerLabel(message.createdAt, now) : ''
    const groupStart = Boolean(divider) || !sameSpeaker(previous, message)
    return { message, divider, groupStart }
  })
}

// Reads the answers of GET /api/notifications and POST /api/notifications/read. Nothing here trusts the shape: a field of the wrong type is unknown (null or
// the neutral kind), never 0 or false made up; text has control characters removed and is cut to a length; a row without a usable id is dropped (it could not be
// marked read). A page whose frame is wrong (no list, no counts) throws UnreadableAnswer; it is never shown as an empty list.
import { fields, list, whole } from './mcpParse.ts'
import { isFields, type Fields } from './unreadable.ts'
import { oneLine } from './jobState.ts'

export const KINDS = ['job_succeeded', 'job_failed', 'job_timed_out', 'job_lost_contact'] as const
export type NotificationKind = (typeof KINDS)[number] | 'other'

export const TITLE_MAX_CHARS = 160
export const DETAIL_MAX_CHARS = 400
export const NAME_MAX_CHARS = 80
export const ID_MAX_CHARS = 80

export interface Notification {
  id: number
  kind: NotificationKind
  title: string
  detail: string
  commandId: string | null
  machine: string | null
  workloadId: string | null
  /** ISO time as the parent sent it; null when missing or not a readable date. */
  createdAt: string | null
  /** True only when the parent says when it was read. Anything unreadable counts as unread, so nothing important is hidden. */
  read: boolean
}

export interface NotificationPage {
  notifications: Notification[]
  total: number
  unreadCount: number
  page: number
  pageSize: number
}

export interface MarkResult {
  marked: number
  unreadCount: number
}

const isKind = (value: unknown): value is (typeof KINDS)[number] => KINDS.some((kind) => kind === value)

function textField(source: Fields, key: string, max: number): string | null {
  const value = source[key]
  if (typeof value !== 'string') return null
  return oneLine(value, max) || null
}

function dateField(source: Fields, key: string): string | null {
  const value = source[key]
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return null
  return value
}

/** One notification, or null when the row cannot be used (no whole-number id). */
export function parseNotification(raw: unknown): Notification | null {
  if (!isFields(raw)) return null
  const id = raw.id
  if (typeof id !== 'number' || !Number.isInteger(id) || id < 1) return null
  return {
    id,
    kind: isKind(raw.kind) ? raw.kind : 'other',
    title: textField(raw, 'title', TITLE_MAX_CHARS) ?? '',
    detail: textField(raw, 'detail', DETAIL_MAX_CHARS) ?? '',
    commandId: textField(raw, 'command_id', ID_MAX_CHARS),
    machine: textField(raw, 'machine', NAME_MAX_CHARS),
    workloadId: textField(raw, 'workload_id', NAME_MAX_CHARS),
    createdAt: dateField(raw, 'created_at'),
    read: dateField(raw, 'read_at') !== null,
  }
}

export function parseNotificationPage(raw: unknown): NotificationPage {
  const body = fields(raw, 'the notifications answer')
  const rows = list(body.notifications, 'the notifications')
  return {
    notifications: rows.map(parseNotification).filter((row): row is Notification => row !== null),
    total: whole(body, 'total', 0),
    unreadCount: whole(body, 'unread_count', 0),
    page: whole(body, 'page', 1),
    pageSize: whole(body, 'page_size', 1),
  }
}

export function parseMarkResult(raw: unknown): MarkResult {
  const body = fields(raw, 'the mark-read answer')
  return { marked: whole(body, 'marked', 0), unreadCount: whole(body, 'unread_count', 0) }
}

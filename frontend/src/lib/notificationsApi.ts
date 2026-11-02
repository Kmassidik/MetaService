// The two calls of the bell and the list: GET /api/notifications (one page, newest first) and POST /api/notifications/read. Each answer is read by notificationsParse.ts.
import { getUnchecked, postUnchecked } from './api.ts'
import { parseMarkResult, parseNotificationPage, type MarkResult, type NotificationPage } from './notificationsParse.ts'

export const NOTIFICATIONS_PATH = '/api/notifications'
export const READ_PATH = '/api/notifications/read'
/** The parent takes at most this many ids in one mark-read call, and gives at most this many rows per page. */
export const MAX_IDS = 100

/** The address of one page. Unread only is left out unless asked for. */
export function notificationsPath(page: number, pageSize: number, unreadOnly: boolean): string {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) })
  if (unreadOnly) params.set('unread', 'true')
  return `${NOTIFICATIONS_PATH}?${params}`
}

export async function listNotifications(page: number, pageSize: number, unreadOnly = false): Promise<NotificationPage> {
  return parseNotificationPage(await getUnchecked(notificationsPath(page, pageSize, unreadOnly)))
}

/** The body of a mark-read call: these ids (at most 100), or everything. */
export const markBody = (target: number[] | 'all'): Record<string, unknown> => (target === 'all' ? { all: true } : { ids: target.slice(0, MAX_IDS) })

export async function markRead(target: number[] | 'all'): Promise<MarkResult> {
  return parseMarkResult(await postUnchecked(READ_PATH, markBody(target)))
}

// What the Notifications page keeps while it is open: the rows of the page being shown, how many there are in all, how many are unread, and whether it is loading,
// ready or failed. An answer that arrives after the person asked for another page is dropped. Marking read changes the rows at once and tells the bell.
import { ApiError } from './api.ts'
import { bell } from './notificationsStore.svelte.ts'
import { listNotifications, markRead } from './notificationsApi.ts'
import type { Notification } from './notificationsParse.ts'
import { UnreadableAnswer } from './unreadable.ts'

export type Phase = 'loading' | 'ready' | 'error'

const FAILED_TEXT = 'Notifications could not be loaded.'
const UNREADABLE_TEXT = 'The answer was not in the shape the panel expects.'
const MARK_FAILED_TEXT = 'Could not mark as read.'

function failureText(error: unknown): string {
  if (error instanceof ApiError) return `${FAILED_TEXT} ${error.message}`
  if (error instanceof UnreadableAnswer) return `${FAILED_TEXT} ${UNREADABLE_TEXT}`
  throw error
}

export class NotificationsData {
  rows = $state<Notification[]>([])
  total = $state(0)
  unread = $state(0)
  phase = $state<Phase>('loading')
  error = $state('')
  /** A mark-read that failed; the rows stay as they were. */
  markError = $state('')
  #ask = 0

  async load(page: number, pageSize: number): Promise<void> {
    const ask = ++this.#ask
    try {
      const answer = await listNotifications(page, pageSize)
      if (ask !== this.#ask) return
      this.rows = answer.notifications
      this.total = answer.total
      this.unread = answer.unreadCount
      this.phase = 'ready'
      this.error = ''
      bell.set(answer.unreadCount)
    } catch (error) {
      if (ask !== this.#ask) return
      this.error = failureText(error)
      this.phase = 'error'
    }
  }

  /** Marks one row read. Rows already read are left alone (no call). */
  async markOne(item: Notification): Promise<void> {
    if (item.read) return
    if (!(await this.#mark([item.id]))) return
    this.rows = this.rows.map((row) => (row.id === item.id ? { ...row, read: true } : row))
  }

  /** Marks everything read, on every page, and shows the rows read. */
  async markAll(): Promise<void> {
    if (!(await this.#mark('all'))) return
    this.rows = this.rows.map((row) => ({ ...row, read: true }))
  }

  /** True when the parent took it. */
  async #mark(target: number[] | 'all'): Promise<boolean> {
    try {
      const result = await markRead(target)
      this.unread = result.unreadCount
      this.markError = ''
      bell.set(result.unreadCount)
      return true
    } catch (error) {
      if (!(error instanceof ApiError || error instanceof UnreadableAnswer)) throw error
      this.markError = MARK_FAILED_TEXT
      return false
    }
  }
}

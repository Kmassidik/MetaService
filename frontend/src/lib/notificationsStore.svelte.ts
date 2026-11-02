// The count on the bell, kept while the person moves between pages. App asks it every BELL_POLL_MS while the tab is visible; a failed ask pauses it until the tab is
// shown again or the person opens the list. The list page tells it the new count after every page it loads and every mark-read.
import { listNotifications } from './notificationsApi.ts'
import { shouldPollBell } from './notifications.ts'

class BellStore {
  /** Unread notifications; null until the first answer or while the parent gives none. */
  unread = $state<number | null>(null)
  #paused = false

  async refresh(): Promise<void> {
    try {
      this.unread = (await listNotifications(1, 1)).unreadCount
      this.#paused = false
    } catch {
      this.#paused = true
    }
  }

  /** One tick of the timer. */
  poll(): void {
    if (shouldPollBell({ hidden: document.hidden, paused: this.#paused })) void this.refresh()
  }

  /** The tab came back, or the list was opened: ask again even after a failure. */
  resume(): void {
    this.#paused = false
    if (!document.hidden) void this.refresh()
  }

  set(unread: number): void {
    this.unread = unread
  }

  /** Signed out: forget the count of the last person. */
  clear(): void {
    this.unread = null
    this.#paused = false
  }
}

export const bell = new BellStore()

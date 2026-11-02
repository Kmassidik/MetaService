// The rules of the bell and the notification list that need no browser: the words of each kind, the count on the bell, where a click leads, and when the bell asks again.
import { machineHref, vmHref } from './routes.ts'
import type { Notification, NotificationKind } from './notificationsParse.ts'

/** The bell asks for its count this often while the tab is visible. */
export const BELL_POLL_MS = 30_000
/** More unread than this is shown as "99+" on the bell. */
export const BADGE_MAX = 99
export const NOTIFICATIONS_HREF = '#/notifications'
/** The list opens with this page size (one of the shared sizes: 25, 50, 100; the parent's cap is 100). */
export const NOTIFICATIONS_PAGE_SIZE = 25

export type Tone = 'ok' | 'bad' | 'neutral'

interface KindWords {
  label: string
  tone: Tone
}

const KIND_WORDS: Record<NotificationKind, KindWords> = {
  job_succeeded: { label: 'Finished', tone: 'ok' },
  job_failed: { label: 'Failed', tone: 'bad' },
  job_timed_out: { label: 'Timed out', tone: 'bad' },
  job_lost_contact: { label: 'Lost contact', tone: 'bad' },
  other: { label: 'Notice', tone: 'neutral' },
}

export const NEUTRAL_TITLE = 'A notification the panel does not know'

export const kindWords = (kind: NotificationKind): KindWords => KIND_WORDS[kind]

/** The title to show: the parent's, or a neutral line when it sent none. */
export const titleOf = (item: Notification): string => item.title || NEUTRAL_TITLE

/** The number on the bell: nothing for zero or an unknown count, "99+" for a lot. */
export function badgeText(unread: number | null): string {
  if (unread === null || unread <= 0) return ''
  return unread > BADGE_MAX ? `${BADGE_MAX}+` : String(unread)
}

/** What a screen reader hears for the bell. */
export function bellLabel(unread: number | null): string {
  if (unread === null || unread <= 0) return 'Notifications'
  return `Notifications, ${unread} unread`
}

/** Where a click on a notification leads: the VM, else the machine, else nowhere. */
export function targetHref(item: Notification): string | null {
  if (item.machine === null) return null
  return item.workloadId === null ? machineHref(item.machine) : vmHref(item.machine, item.workloadId)
}

/** What the target is called in the row ("mac-studio" or "mac-studio / vm-0019"). */
export function targetName(item: Notification): string | null {
  if (item.machine === null) return null
  return item.workloadId === null ? item.machine : `${item.machine} / ${item.workloadId}`
}

export interface PollFacts {
  hidden: boolean
  /** The last ask failed; the bell waits until the tab is shown again or the person opens the list. */
  paused: boolean
}

export const shouldPollBell = (facts: PollFacts): boolean => !facts.hidden && !facts.paused

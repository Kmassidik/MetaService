import { expect, test } from 'bun:test'
import { BADGE_MAX, NEUTRAL_TITLE, NOTIFICATIONS_PAGE_SIZE, badgeText, bellLabel, kindWords, shouldPollBell, targetHref, targetName, titleOf } from './notifications.ts'
import { MAX_IDS, markBody, notificationsPath } from './notificationsApi.ts'
import type { Notification } from './notificationsParse.ts'
import { PAGE_SIZES, pageCount, showingText, slicePage } from './paging.ts'
import { pageFor } from './routes.ts'

const note = (extra: Partial<Notification> = {}): Notification => ({ id: 1, kind: 'job_failed', title: 'Delete failed', detail: '', commandId: null, machine: 'rtx', workloadId: 'vm-1', createdAt: '2026-11-03T10:00:00Z', read: false, ...extra })

test('the bell shows nothing for zero or unknown, the number, and 99+ for many', () => {
  expect([null, 0, -3].map(badgeText)).toEqual(['', '', ''])
  expect([1, 42, BADGE_MAX].map(badgeText)).toEqual(['1', '42', '99'])
  expect(badgeText(BADGE_MAX + 1)).toBe('99+')
  expect(bellLabel(5)).toBe('Notifications, 5 unread')
  expect(bellLabel(0)).toBe('Notifications')
})

test('the bell asks only while the tab is visible and not paused after an error', () => {
  expect(shouldPollBell({ hidden: false, paused: false })).toBe(true)
  expect(shouldPollBell({ hidden: true, paused: false })).toBe(false)
  expect(shouldPollBell({ hidden: false, paused: true })).toBe(false)
})

test('a click leads to the VM, else the machine, else nowhere', () => {
  expect(targetHref(note())).toBe('#/machines/details?id=rtx&vm=vm-1')
  expect(targetHref(note({ workloadId: null }))).toBe('#/machines/details?id=rtx')
  expect(targetHref(note({ machine: null, workloadId: 'vm-1' }))).toBeNull()
  expect(targetName(note())).toBe('rtx / vm-1')
  expect(targetName(note({ workloadId: null }))).toBe('rtx')
})

test('each kind has plain words; an unknown kind is neutral with a neutral title when none came', () => {
  expect(kindWords('job_succeeded')).toEqual({ label: 'Finished', tone: 'ok' })
  expect(['job_failed', 'job_timed_out', 'job_lost_contact'].map((kind) => kindWords(kind as Notification['kind']).tone)).toEqual(['bad', 'bad', 'bad'])
  expect(kindWords('other').tone).toBe('neutral')
  expect(titleOf(note({ kind: 'other', title: '' }))).toBe(NEUTRAL_TITLE)
})

test('the list is on the notifications page', () => {
  expect(pageFor('/notifications')).toBe('notifications')
})

test('the requests ask for one page, unread only on demand, and at most 100 ids', () => {
  expect(notificationsPath(3, 25, false)).toBe('/api/notifications?page=3&page_size=25')
  expect(notificationsPath(1, 100, true)).toBe('/api/notifications?page=1&page_size=100&unread=true')
  expect(markBody('all')).toEqual({ all: true })
  expect(markBody([1, 2])).toEqual({ ids: [1, 2] })
  expect((markBody(Array.from({ length: 150 }, (_, index) => index + 1)).ids as number[]).length).toBe(MAX_IDS)
})

test('61 notifications page as 3 pages of 25 with the shared "Showing a to b of N" text', () => {
  const rows = Array.from({ length: 61 }, (_, index) => note({ id: index + 1 }))
  expect(PAGE_SIZES.some((size) => size === NOTIFICATIONS_PAGE_SIZE)).toBe(true)
  expect(pageCount(rows.length, NOTIFICATIONS_PAGE_SIZE)).toBe(3)
  expect(showingText(1, rows.length, NOTIFICATIONS_PAGE_SIZE)).toBe('Showing 1 to 25 of 61')
  expect(showingText(3, rows.length, NOTIFICATIONS_PAGE_SIZE)).toBe('Showing 51 to 61 of 61')
  expect(slicePage(rows, 3, NOTIFICATIONS_PAGE_SIZE).map((item) => item.id)).toEqual([51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61])
})

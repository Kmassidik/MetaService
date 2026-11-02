import { expect, test } from 'bun:test'
import { DETAIL_MAX_CHARS, TITLE_MAX_CHARS, parseMarkResult, parseNotification, parseNotificationPage } from './notificationsParse.ts'
import { UnreadableAnswer } from './unreadable.ts'

const row = (extra: Record<string, unknown> = {}) => ({
  id: 7, kind: 'job_succeeded', title: 'Deleted vm-0019', detail: 'It took 4 minutes.', command_id: 'cmd-1', machine: 'rtx', workload_id: 'vm-0019',
  created_at: '2026-11-03T10:00:00Z', read_at: null, ...extra,
})
const page = (extra: Record<string, unknown> = {}) => ({ notifications: [row()], total: 1, unread_count: 1, page: 1, page_size: 25, ...extra })

test('a good row is read field by field, unread when read_at is null', () => {
  expect(parseNotification(row())).toEqual({ id: 7, kind: 'job_succeeded', title: 'Deleted vm-0019', detail: 'It took 4 minutes.', commandId: 'cmd-1', machine: 'rtx', workloadId: 'vm-0019', createdAt: '2026-11-03T10:00:00Z', read: false })
  expect(parseNotification(row({ read_at: '2026-11-03T10:05:00Z' }))?.read).toBe(true)
})

test('all four kinds are kept; an unknown kind or a wrong type is the neutral kind', () => {
  for (const kind of ['job_succeeded', 'job_failed', 'job_timed_out', 'job_lost_contact']) expect(parseNotification(row({ kind }))?.kind).toBe(kind as never)
  for (const kind of ['job_exploded', 5, null, {}]) expect(parseNotification(row({ kind }))?.kind).toBe('other')
})

test('a row without a whole-number id is dropped, not given id 0', () => {
  for (const id of [0, -1, 1.5, '7', null, undefined, true]) expect(parseNotification(row({ id }))).toBeNull()
  expect(parseNotification('text')).toBeNull()
  expect(parseNotification([])).toBeNull()
})

test('wrong types become unknown, never 0 or false or made-up text', () => {
  const odd = parseNotification(row({ title: 5, detail: {}, command_id: 3, machine: false, workload_id: [], created_at: 12, read_at: 'not a date' }))
  expect(odd).toEqual({ id: 7, kind: 'job_succeeded', title: '', detail: '', commandId: null, machine: null, workloadId: null, createdAt: null, read: false })
})

test('text is cleaned and capped, and markup stays plain text', () => {
  const item = parseNotification(row({ title: `Deleted\u0000 \u001b[31mvm\u001b[0m ${'x'.repeat(1000)}`, detail: `<script>alert(1)</script>\n\n${'y'.repeat(2000)}` }))
  expect(item?.title.includes('\u0000')).toBe(false)
  expect(item?.title.includes('\u001b')).toBe(false)
  expect(Array.from(item?.title ?? '').length).toBe(TITLE_MAX_CHARS)
  expect(Array.from(item?.detail ?? '').length).toBe(DETAIL_MAX_CHARS)
  expect(item?.detail.startsWith('<script>alert(1)</script> ')).toBe(true)
})

test('a page keeps its counts and drops unusable rows', () => {
  const answer = parseNotificationPage(page({ notifications: [row(), row({ id: 'bad' }), row({ id: 8 })], total: 61, unread_count: 12, page: 3, page_size: 25 }))
  expect(answer.notifications.map((item) => item.id)).toEqual([7, 8])
  expect([answer.total, answer.unreadCount, answer.page, answer.pageSize]).toEqual([61, 12, 3, 25])
})

test('a page with the wrong frame is unreadable, not empty', () => {
  for (const bad of [null, 'x', [], {}, page({ notifications: 'no' }), page({ total: '5' }), page({ unread_count: -1 }), page({ page: 0 }), page({ page_size: 1.5 }), page({ total: undefined })]) {
    expect(() => parseNotificationPage(bad)).toThrow(UnreadableAnswer)
  }
})

test('a mark-read answer needs both numbers', () => {
  expect(parseMarkResult({ marked: 3, unread_count: 9 })).toEqual({ marked: 3, unreadCount: 9 })
  expect(() => parseMarkResult({ marked: 3 })).toThrow(UnreadableAnswer)
  expect(() => parseMarkResult(null)).toThrow(UnreadableAnswer)
})

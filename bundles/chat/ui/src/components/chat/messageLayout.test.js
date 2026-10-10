import { describe, expect, it } from 'vitest'
import { TIME_GAP_MS, dividerLabel, layoutMessages } from './messageLayout.js'

const NOW = new Date(2026, 9, 1, 15, 0).valueOf()
const at = minutesAgo => new Date(NOW - minutesAgo * 60 * 1000).toISOString()
const message = (id, role, minutesAgo) => ({ id, role, text: id, createdAt: at(minutesAgo) })

describe('dividerLabel', () => {
  it('says Today for messages from the current day', () => {
    expect(dividerLabel(at(10), NOW)).toMatch(/^Today /)
  })

  it('says Yesterday for messages from the previous day', () => {
    expect(dividerLabel(at(20 * 60), NOW)).toMatch(/^Yesterday /)
  })

  it('returns an empty label for an invalid date', () => {
    expect(dividerLabel('not a date', NOW)).toBe('')
  })
})

describe('layoutMessages', () => {
  it('puts a divider on the first message only when messages are close together', () => {
    const rows = layoutMessages([message('a', 'assistant', 5), message('b', 'assistant', 4)], NOW)
    expect(rows.map(row => Boolean(row.divider))).toEqual([true, false])
  })

  it('adds a divider after a gap longer than 30 minutes', () => {
    const gapMinutes = TIME_GAP_MS / 60000 + 1
    const rows = layoutMessages([message('a', 'user', gapMinutes + 1), message('b', 'user', 1)], NOW)
    expect(rows[1].divider).not.toBe('')
    expect(rows[1].groupStart).toBe(true)
  })

  it('groups consecutive messages from the same speaker', () => {
    const rows = layoutMessages([
      message('a', 'assistant', 3), message('b', 'assistant', 2), message('c', 'user', 1),
    ], NOW)
    expect(rows.map(row => row.groupStart)).toEqual([true, false, true])
  })

  it('never groups system lines', () => {
    const rows = layoutMessages([message('a', 'system', 2), message('b', 'system', 1)], NOW)
    expect(rows[1].groupStart).toBe(true)
  })
})

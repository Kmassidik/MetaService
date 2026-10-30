import { expect, test } from 'bun:test'
import { listChanged, MCP_POLL_MS, shouldPollMcp, signatureOf } from './mcpPoll.ts'

test('the section asks every 5 seconds', () => {
  expect(MCP_POLL_MS).toBe(5000)
})

test('it asks while the tab is shown, also after an error, but not when hidden or not available', () => {
  expect(shouldPollMcp({ hidden: false, unavailable: false })).toBe(true)
  expect(shouldPollMcp({ hidden: true, unavailable: false })).toBe(false)
  expect(shouldPollMcp({ hidden: false, unavailable: true })).toBe(false)
})

test('a list is redrawn only when it changed', () => {
  const shown = signatureOf([{ id: 'r1', state: 'pending_approval' }])
  expect(listChanged(shown, [{ id: 'r1', state: 'pending_approval' }])).toBe(false)
  expect(listChanged(shown, [{ id: 'r1', state: 'denied' }])).toBe(true)
  expect(listChanged(null, [])).toBe(true)
})

import { expect, test } from 'bun:test'
import { listChanged, SHARE_POLL_MS, shouldPoll, signatureOf } from './sharePoll.ts'

test('the page asks every 4 seconds', () => {
  expect(SHARE_POLL_MS).toBe(4000)
})

test('it asks while the tab is shown, also when the hub does not answer, but not when hidden or not set up', () => {
  expect(shouldPoll({ hidden: false, problem: null })).toBe(true)
  expect(shouldPoll({ hidden: false, problem: 'hub_unreachable' })).toBe(true)
  expect(shouldPoll({ hidden: true, problem: null })).toBe(false)
  expect(shouldPoll({ hidden: false, problem: 'not_configured' })).toBe(false)
})

test('a list is redrawn only when it changed', () => {
  const list = [{ id: 'p1', triesLeft: 5 }]
  const shown = signatureOf(list)
  expect(listChanged(shown, [{ id: 'p1', triesLeft: 5 }])).toBe(false)
  expect(listChanged(shown, [{ id: 'p1', triesLeft: 4 }])).toBe(true)
  expect(listChanged(shown, [])).toBe(true)
  expect(listChanged(null, [])).toBe(true)
})

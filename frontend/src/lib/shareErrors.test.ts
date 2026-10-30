import { expect, test } from 'bun:test'
import { describeShareError, HUB_UNREACHABLE_TEXT, isHubRefusal, NOT_CONFIGURED_TEXT, pageProblem, problemText } from './shareErrors.ts'

test('a wrong code says how many tries are left, with the right plural', () => {
  expect(describeShareError(403, { error: 'wrong_code', tries_left: 3 }).text).toBe('That code is wrong. 3 tries left.')
  expect(describeShareError(403, { error: 'wrong_code', tries_left: 1 }).text).toBe('That code is wrong. 1 try left.')
  expect(describeShareError(403, { error: 'wrong_code', tries_left: 0 }).text).toBe('That code is wrong. 0 tries left.')
  expect(describeShareError(403, { error: 'wrong_code' }).text).toBe('That code is wrong.')
  expect(describeShareError(403, { error: 'wrong_code', tries_left: 'many' }).text).toBe('That code is wrong.')
})

test('every error word the hub uses has its own plain sentence', () => {
  const words = ['unauthorized', 'rate_limited', 'name_taken', 'expired', 'not_pending', 'unknown_pending', 'unknown_peer', 'bad_name', 'bad_share', 'share_too_high', 'network_full', 'wireguard_failed', 'locked', 'no_build', 'windows_soon', 'not_configured', 'hub_unreachable']
  const sentences = words.map((word) => describeShareError(409, { error: word }).text)
  expect(new Set(sentences).size).toBe(words.length)
  for (const sentence of sentences) expect(sentence).not.toContain('The hub answered with an error')
  expect(describeShareError(409, { error: 'name_taken' })).toEqual({ code: 'name_taken', text: 'That name is already used. Choose another name.' })
})

test('an unknown word uses the hub reason when there is one, else names the error or the status', () => {
  expect(describeShareError(400, { error: 'unsupported', reason: 'No Windows build.' }).text).toBe('No Windows build.')
  expect(describeShareError(500, { error: 'boom' }).text).toBe('The hub answered with an error (boom).')
  expect(describeShareError(500, null).text).toBe('The hub answered with an error (HTTP 500).')
  expect(describeShareError(500, 'text').text).toBe('The hub answered with an error (HTTP 500).')
})

test('only not_configured and hub_unreachable replace the page', () => {
  expect(pageProblem('not_configured')).toBe('not_configured')
  expect(pageProblem('hub_unreachable')).toBe('hub_unreachable')
  expect(pageProblem('name_taken')).toBeNull()
  expect(pageProblem('')).toBeNull()
  expect(problemText('not_configured')).toBe(NOT_CONFIGURED_TEXT)
  expect(problemText('hub_unreachable')).toBe(HUB_UNREACHABLE_TEXT)
  expect(NOT_CONFIGURED_TEXT).toBe('Share a PC is not set up on this parent.')
})

test('an answer the hub gave on a share route is final; the parent own refusals are not', () => {
  expect(isHubRefusal('/api/join-share/pending/p1/approve', { error: 'wrong_code', tries_left: 2 })).toBe(true)
  expect(isHubRefusal('/api/join-share/pending/p1/approve', { error: { code: 'forbidden', message: 'missing or wrong CSRF token' } })).toBe(false)
  expect(isHubRefusal('/api/join-share/pending/p1/approve', null)).toBe(false)
  expect(isHubRefusal('/api/machines/x/settings', { error: 'wrong_code' })).toBe(false)
})

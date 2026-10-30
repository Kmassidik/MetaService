import { expect, test } from 'bun:test'
import { DEFAULT_QUOTAS } from './mcp.ts'
import { agoText, claudeLine, expiryText, isLive, jsonSnippet, lastUsedText, quotaLine, revokeCopy, SCOPE_TEXT, TOKEN_PLACEHOLDER, TOOL_TEXT } from './mcpText.ts'

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR
const NOW = Date.parse('2026-10-31T12:00:00Z')

test('every scope has a plain explanation and every tool a scope that exists', () => {
  for (const scope of Object.values(SCOPE_TEXT)) expect(scope.explain.length).toBeGreaterThan(10)
  for (const tool of Object.values(TOOL_TEXT)) expect(SCOPE_TEXT[tool.scope]).toBeDefined()
})

test('the limits in one short line', () => {
  expect(quotaLine(DEFAULT_QUOTAS, ['read', 'create'])).toBe('3 VMs · 8 vCPU · 16 GB RAM · 200 GB disk · 10 creates/day')
  expect(quotaLine({ ...DEFAULT_QUOTAS, maxVms: 1, maxRamMb: 1500 }, ['gpu'])).toBe('1 VM · 8 vCPU · 1500 MB RAM · 200 GB disk · 10 creates/day · GPU up to 8 GB')
})

test('how long ago, in words', () => {
  expect(agoText(NOW - 10_000, NOW)).toBe('just now')
  expect(agoText(NOW + 5 * MIN, NOW)).toBe('just now')
  expect(agoText(NOW - 5 * MIN, NOW)).toBe('5 min ago')
  expect(agoText(NOW - 3 * HOUR, NOW)).toBe('3 h ago')
  expect(agoText(NOW - DAY, NOW)).toBe('1 day ago')
  expect(agoText(NOW - 2 * DAY, NOW)).toBe('2 days ago')
  expect(lastUsedText(null, NOW)).toBe('never')
})

test('the expiry text and whether a token still works', () => {
  const live = { expiresAt: NOW + 89 * DAY, revokedAt: null }
  expect(expiryText(live, NOW)).toBe('in 89 days')
  expect(expiryText({ expiresAt: NOW + 5 * HOUR, revokedAt: null }, NOW)).toBe('in 5 h')
  expect(expiryText({ expiresAt: NOW + 20 * MIN, revokedAt: null }, NOW)).toBe('in 20 min')
  expect(expiryText({ expiresAt: NOW - 1, revokedAt: null }, NOW)).toBe('expired')
  expect(expiryText({ expiresAt: NOW + DAY, revokedAt: NOW - 1 }, NOW)).toBe('revoked')
  expect(isLive(live, NOW)).toBe(true)
  expect(isLive({ expiresAt: NOW - 1, revokedAt: null }, NOW)).toBe(false)
  expect(isLive({ expiresAt: NOW + DAY, revokedAt: NOW }, NOW)).toBe(false)
})

test('the connection lines carry a placeholder, never a token', () => {
  const line = claudeLine('https://meta.example/mcp')
  expect(line).toBe('claude mcp add --transport http metaservice https://meta.example/mcp --header "Authorization: Bearer <YOUR_TOKEN>"')
  const json = JSON.parse(jsonSnippet('https://meta.example/mcp'))
  expect(json.mcpServers.metaservice.url).toBe('https://meta.example/mcp')
  expect(json.mcpServers.metaservice.headers.Authorization).toBe(`Bearer ${TOKEN_PLACEHOLDER}`)
  expect(line + jsonSnippet('x')).not.toContain('msk_')
})

test('revoke says what stops and what stays', () => {
  const copy = revokeCopy({ name: 'laptop' })
  expect(copy.what).toContain('laptop')
  expect(copy.consequence).toContain('keep running')
})

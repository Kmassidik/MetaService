import { expect, test } from 'bun:test'
import { sandboxTabFromRoute } from './sandboxTabs.ts'

test('sandbox tabs preserve the live, key and usage addresses', () => {
  expect(sandboxTabFromRoute('/sandboxes')).toBe('live')
  expect(sandboxTabFromRoute('/sandboxes/keys')).toBe('keys')
  expect(sandboxTabFromRoute('/sandboxes/usage')).toBe('usage')
})

test('the old API keys address opens the API keys tab', () => {
  expect(sandboxTabFromRoute('/keys')).toBe('keys')
})

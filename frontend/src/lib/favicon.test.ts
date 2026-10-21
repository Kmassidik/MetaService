import { test, expect } from 'bun:test'
import { readFileSync } from 'node:fs'

const BRAND_GREEN = '#00f56d'
const BRAND_BLACK = '#111'
const OLD_BLUE = '2457d6'

const icon = readFileSync(new URL('../../public/favicon.svg', import.meta.url), 'utf8')

test('the tab icon is the brand green with a near-black mark', () => {
  expect(icon).toContain(`fill="${BRAND_GREEN}"`)
  expect(icon).toContain(`stroke="${BRAND_BLACK}"`)
})

test('the old blue is gone from the tab icon', () => {
  expect(icon.toLowerCase()).not.toContain(OLD_BLUE)
})

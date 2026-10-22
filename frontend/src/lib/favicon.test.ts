import { test, expect } from 'bun:test'
import { readFileSync } from 'node:fs'

const BROWN = '#7A5A3A'
const CREAM = '#F3EBC8'
const MOSS = '#7DB26B'
const AMBER = '#F5B73B'
const DARK = '#1B1B1B'
const WHITE = '#fff'
const OLD_BLUE = '2457d6'
const OLD_GREEN_SQUARE = '#00f56d'

const icon = readFileSync(new URL('../../public/favicon.svg', import.meta.url), 'utf8')

test('the tab icon is one valid SVG on a 32 by 32 box', () => {
  expect(icon.trim()).toMatch(/^<svg [^>]*xmlns="http:\/\/www\.w3\.org\/2000\/svg"[^>]*viewBox="0 0 32 32"[^>]*>[\s\S]*<\/svg>$/)
  expect(icon.match(/<svg/g)).toHaveLength(1)
  expect(icon).not.toMatch(/<script|onload|href=/i)
})

test('the tab icon is the owl head in the brand colours', () => {
  for (const colour of [BROWN, CREAM, MOSS, AMBER, DARK, WHITE]) expect(icon).toContain(`fill="${colour}"`)
})

test('the old blue and the old green square are gone from the tab icon', () => {
  expect(icon.toLowerCase()).not.toContain(OLD_BLUE)
  expect(icon.toLowerCase()).not.toContain(OLD_GREEN_SQUARE)
})

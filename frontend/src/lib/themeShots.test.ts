import { test, expect } from 'bun:test'
import { PAGES, SIZES, THEMES, compareName, shotName } from './themeShots.ts'

test('a picture is called theme-page-size.png', () => {
  expect(shotName('today', 'login', 'desktop')).toBe('today-login-desktop.png')
  expect(shotName('forest-soft', 'vms-tab', 'phone')).toBe('forest-soft-vms-tab-phone.png')
})

test('the comparison of a page is called compare-page.png', () => {
  expect(compareName('machines')).toBe('compare-machines.png')
})

test('every theme and page has its own name, and today is the one with no attribute', () => {
  expect(new Set(THEMES.map((theme) => theme.id)).size).toBe(THEMES.length)
  expect(new Set(PAGES.map((page) => page.id)).size).toBe(PAGES.length)
  expect(THEMES.filter((theme) => theme.attribute === '').map((theme) => theme.id)).toEqual(['today'])
})

test('the two sizes are a 1280 by 800 desktop and a 400 pixel phone', () => {
  expect(SIZES.desktop).toEqual({ width: 1280, height: 800 })
  expect(SIZES.phone.width).toBe(400)
})

import { test, expect } from 'bun:test'
import { PAGES, SIZES, shotName } from './shotNames.ts'

test('a picture is called page-size.png', () => {
  expect(shotName('login', 'desktop')).toBe('login-desktop.png')
  expect(shotName('vms-tab', 'phone')).toBe('vms-tab-phone.png')
})

test('every page has its own name', () => {
  expect(new Set(PAGES).size).toBe(PAGES.length)
})

test('the two sizes are a 1280 by 800 desktop and a 400 pixel phone', () => {
  expect(SIZES.desktop).toEqual({ width: 1280, height: 800 })
  expect(SIZES.phone.width).toBe(400)
})

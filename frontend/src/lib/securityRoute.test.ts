import { expect, test } from 'bun:test'
import { parseSecurityView, securityHref } from './securityRoute.ts'

test('the bare address opens on 7 days, all machines, all types, no sample data', () => {
  expect(parseSecurityView('/security')).toEqual({ range: '7d', machine: '', type: '', preview: false })
})

test('the address keeps the range, machine, type and the preview switch', () => {
  expect(parseSecurityView('/security?range=90d&machine=rtx-pc&type=blocked&preview=1')).toEqual({ range: '90d', machine: 'rtx-pc', type: 'blocked', preview: true })
})

test('values the page does not know are ignored', () => {
  expect(parseSecurityView('/security?range=5y&machine=../x&type=nope&preview=yes')).toEqual({ range: '7d', machine: '', type: '', preview: false })
})

test('preview is on only when the address asks for it exactly', () => {
  for (const route of ['/security', '/security?preview=0', '/security?preview=true', '/security?preview=']) expect(parseSecurityView(route).preview, route).toBe(false)
})

test('an address is made from a choice and leaves the defaults out', () => {
  expect(securityHref()).toBe('#/security')
  expect(securityHref({ range: '30d', preview: true })).toBe('#/security?range=30d&preview=1')
  const view = parseSecurityView('/security?range=24h&machine=dgx-spark&type=login')
  expect(parseSecurityView(securityHref(view).slice(1))).toEqual(view)
})

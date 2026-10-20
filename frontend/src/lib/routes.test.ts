import { test, expect } from 'bun:test'
import { machineFromRoute, machineHref, machinesView, pageFor, vmFromRoute, vmHref } from './routes.ts'

test('each address leads to its page', () => {
  expect(['/', '/machines', '/machines/find', '/usage', '/health', '/settings'].map(pageFor)).toEqual(['overview', 'machines', 'machines', 'usage', 'health', 'settings'])
})

test('older addresses and unknown ones still land somewhere sensible', () => {
  expect(['/deployments', '/scan', '/activity', '/bundle', '/ai', '/nope'].map(pageFor)).toEqual(['machines', 'machines', 'health', 'settings', 'settings', 'overview'])
})

test('a machine\'s page is /machines/details?id=<machine>, and only that address names a machine', () => {
  expect(machineFromRoute('/machines/details?id=mac-mini')).toBe('mac-mini')
  expect(pageFor('/machines/details?id=mac-mini')).toBe('machines')
  expect(machineHref('mac-mini')).toBe('#/machines/details?id=mac-mini')
  for (const route of ['/machines', '/machines/details', '/machines/details?id=', '/machines/details?id=Bad Name', '/machines/details?id=-x', '/machines/find?id=mac-mini', '/machines/mac-mini', '/usage?id=mac-mini']) expect(machineFromRoute(route)).toBe(null)
})

test('the Machines page shows its list or Find machines by address', () => {
  expect(['/machines', '/machines/find', '/machines/find?x=1', '/machines/connect', '/machines/details?id=mac-mini'].map(machinesView)).toEqual(['list', 'find', 'find', 'list', 'list'])
})

test('a VM\'s page adds &vm=<workload> to its machine\'s address, and only a valid pair names a VM', () => {
  expect(vmHref('mac-mini', 'w-1')).toBe('#/machines/details?id=mac-mini&vm=w-1')
  expect(vmFromRoute('/machines/details?id=mac-mini&vm=w-1')).toBe('w-1')
  expect(machineFromRoute('/machines/details?id=mac-mini&vm=w-1')).toBe('mac-mini')
  for (const route of ['/machines/details?id=mac-mini', '/machines/details?id=mac-mini&vm=', '/machines/details?id=mac-mini&vm=a b', '/machines/details?id=mac-mini&vm=../x', '/machines/details?vm=w-1', '/machines/find?id=mac-mini&vm=w-1']) expect(vmFromRoute(route), route).toBeNull()
})

import { test, expect } from 'bun:test'
import { createVmHref, createVmOpen, machineFromRoute, machineHref, machinesView, machineTabFromRoute, pageFor, shownAddress, vmFromRoute, vmHref, vmsHref, vmsMachineFromRoute } from './routes.ts'

test('a machine address can name a tab (&tab=); old names and missing names land on a new tab', () => {
  expect(machineTabFromRoute('/machines/details?id=mac-mini&tab=vms')).toBe('vms')
  expect(machineTabFromRoute('/machines/details?id=mac-mini&tab=Overview')).toBe('environment')
  expect(machineTabFromRoute('/machines/details?id=mac-mini&tab=deployments')).toBe('vms')
  expect(machineTabFromRoute('/machines/details?id=mac-mini')).toBe('live')
  expect(machineTabFromRoute('/machines/details?id=mac-mini&tab=nope')).toBe('live')
  expect(machineTabFromRoute('/machines')).toBe('live')
})

test('each address leads to its page', () => {
  expect(['/', '/machines', '/machines/find', '/usage', '/health', '/settings'].map(pageFor)).toEqual(['overview', 'machines', 'machines', 'usage', 'health', 'settings'])
})

test('older addresses still lead to their new pages', () => {
  expect(['/deployments', '/scan', '/activity', '/bundle', '/ai'].map(pageFor)).toEqual(['machines', 'machines', 'health', 'settings', 'settings'])
})

test('the empty address is Overview, and the pages with a detail or a window still lead to their page', () => {
  expect(['', '/', '/?x=1', '/machines/details', '/machines/details?id=xyz', '/vms/create', '/machines/find', '/usage', '/health', '/settings'].map(pageFor)).toEqual(['overview', 'overview', 'overview', 'machines', 'machines', 'vms', 'machines', 'usage', 'health', 'settings'])
})

test('a trailing slash and a query string do not change the page', () => {
  expect(['/machines/', '/vms/', '/vms//', '/health/?a=1', '//'].map(pageFor)).toEqual(['machines', 'vms', 'vms', 'health', 'overview'])
})

test('an address the panel does not know leads to the Page not found screen', () => {
  for (const route of ['/nope', '/healthsasdfasdf', '/machines/xyz/abc', '/Machines', '/vms/other', '/machines/details/x', '/<img src=x onerror=alert(1)>']) expect(pageFor(route), route).toBe('notfound')
})

test('the Page not found screen shows the typed address as text: decoded, without the query, cut when long', () => {
  expect(shownAddress('/nope?x=1')).toBe('/nope')
  expect(shownAddress('/%3Cimg%20src=x%3E')).toBe('/<img src=x>')
  expect(shownAddress('/%E0%A4%A')).toBe('/%E0%A4%A')
  expect(shownAddress(`/${'a'.repeat(200)}`)).toBe(`/${'a'.repeat(79)}…`)
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

test('the VMs pages are /vms (all VMs) and /vms/create, and both belong to the vms page', () => {
  expect(['/vms', '/vms/create', '/vms?machine=mac-mini', '/vms/create?machine=mac-mini'].map(pageFor)).toEqual(['vms', 'vms', 'vms', 'vms'])
})

test('the Create VM window is in the address of the old Create VM links only', () => {
  expect(['/vms/create', '/vms/create?machine=x'].map(createVmOpen)).toEqual([true, true])
  for (const route of ['/vms', '/vms?machine=x', '/vms/other', '/', '/machines/details?id=a', '/machines/create']) expect(createVmOpen(route), route).toBe(false)
})

test('the machine kept in the address of the VMs pages is read only when it is a valid id', () => {
  expect(vmsMachineFromRoute('/vms?machine=mac-mini')).toBe('mac-mini')
  expect(vmsMachineFromRoute('/vms/create?machine=mac-mini')).toBe('mac-mini')
  for (const route of ['/vms', '/vms?machine=', '/vms?machine=Bad Name', '/vms?machine=-x', '/vms?machine=../x', '/machines?machine=mac-mini']) expect(vmsMachineFromRoute(route), route).toBeNull()
})

test('the VMs addresses are built with the machine only when there is one', () => {
  expect(vmsHref(null)).toBe('#/vms')
  expect(vmsHref('mac-mini')).toBe('#/vms?machine=mac-mini')
  expect(createVmHref(null)).toBe('#/vms/create')
  expect(createVmHref('mac-mini')).toBe('#/vms/create?machine=mac-mini')
})

test('Share a PC has its own address, with or without a trailing slash', () => {
  expect(['/share', '/share/', '/share?x=1'].map(pageFor)).toEqual(['share', 'share', 'share'])
  expect(pageFor('/share/other')).toBe('notfound')
})

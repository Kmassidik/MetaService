import test from 'node:test'
import assert from 'node:assert/strict'
import { machineFromRoute, machineHref, machinesView, pageFor } from './routes.ts'

test('each address leads to its page', () => {
  assert.deepEqual(['/', '/machines', '/machines/find', '/machines/connect', '/usage', '/health', '/settings'].map(pageFor), ['overview', 'machines', 'machines', 'machines', 'usage', 'health', 'settings'])
})

test('older addresses and unknown ones still land somewhere sensible', () => {
  assert.deepEqual(['/deployments', '/scan', '/activity', '/bundle', '/ai', '/nope'].map(pageFor), ['machines', 'machines', 'health', 'settings', 'settings', 'overview'])
})

test('a machine\'s page is /machines/details?id=<machine>, and only that address names a machine', () => {
  assert.equal(machineFromRoute('/machines/details?id=mac-mini'), 'mac-mini')
  assert.equal(pageFor('/machines/details?id=mac-mini'), 'machines')
  assert.equal(machineHref('mac-mini'), '#/machines/details?id=mac-mini')
  for (const route of ['/machines', '/machines/details', '/machines/details?id=', '/machines/details?id=Bad Name', '/machines/details?id=-x', '/machines/find?id=mac-mini', '/machines/mac-mini', '/usage?id=mac-mini']) assert.equal(machineFromRoute(route), null, route)
})

test('the Machines page shows its list, Find machines or the connected computers by address', () => {
  assert.deepEqual(['/machines', '/machines/find', '/machines/connect', '/machines/connect?x=1', '/machines/details?id=mac-mini'].map(machinesView), ['list', 'find', 'connect', 'connect', 'list'])
})

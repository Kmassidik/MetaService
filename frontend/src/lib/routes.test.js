import test from 'node:test'
import assert from 'node:assert/strict'
import { machineFromRoute, pageFor } from './routes.js'

test('each address leads to its page', () => {
  assert.deepEqual(['/', '/machines', '/machines/find', '/deployments', '/usage', '/health', '/settings'].map(pageFor), ['overview', 'machines', 'machines', 'deployments', 'usage', 'health', 'settings'])
})

test('older addresses and unknown ones still land somewhere sensible', () => {
  assert.deepEqual(['/scan', '/activity', '/bundle', '/ai', '/nope'].map(pageFor), ['machines', 'health', 'settings', 'settings', 'overview'])
})

test('a machine\'s deployment page is found from its address, and only from that', () => {
  assert.equal(machineFromRoute('/deployments/mac-mini'), 'mac-mini')
  assert.equal(pageFor('/deployments/mac-mini'), 'deployments')
  for (const route of ['/deployments', '/deployments/', '/deployments/Bad Name', '/deployments/a/b', '/machines/mac-mini', '/deployments/-x']) assert.equal(machineFromRoute(route), null, route)
})

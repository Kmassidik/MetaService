import test from 'node:test'
import assert from 'node:assert/strict'
import { allVms, attentionItems, overviewCounts, usageName, usageTotals } from './overview.js'

const machines = [
  { id: 'a', name: 'a', state: 'online', problems: [], workloads: [{ id: 'w1', state: 'running' }, { id: 'w2', state: 'stopped' }] },
  { id: 'b', name: 'b', state: 'offline', problems: [], workloads: [] },
  { id: 'c', name: 'c', state: 'online', problems: [{ code: 'container_tool_missing', message: 'No tool.', fix: 'Install it.' }], workloads: [{ id: 'w3', state: 'running' }] },
]

test('every VM comes with its machine', () => {
  assert.deepEqual(allVms(machines).map(({ machine, workload }) => `${machine.id}/${workload.id}`), ['a/w1', 'a/w2', 'c/w3'])
  assert.deepEqual(allVms([]), [])
})

test('the overview counts machines, VMs and what needs attention', () => {
  assert.deepEqual(overviewCounts(machines), { machines: 3, online: 2, vms: 3, running: 2, needAttention: 2 })
  assert.deepEqual(overviewCounts([]), { machines: 0, online: 0, vms: 0, running: 0, needAttention: 0 })
})

test('an offline machine and a machine problem each become one plain item', () => {
  const items = attentionItems(machines)
  assert.deepEqual(items.map((item) => [item.machine, item.kind]), [['b', 'offline'], ['c', 'problem']])
  assert.equal(items[1].fix, 'Install it.')
  assert.deepEqual(attentionItems([]), [])
})

test('usage adds up and names the VM when there is one', () => {
  const rows = [{ machine: 'a', workload: null, requests: 2, prompt_tokens: 10, completion_tokens: 5 }, { machine: 'a', workload: 'w1', requests: 1, prompt_tokens: 3, completion_tokens: 4 }]
  assert.deepEqual(usageTotals(rows), { requests: 3, promptTokens: 13, completionTokens: 9 })
  assert.deepEqual(usageTotals([]), { requests: 0, promptTokens: 0, completionTokens: 0 })
  assert.deepEqual(rows.map(usageName), ['a', 'a / w1'])
})

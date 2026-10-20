import { test, expect } from 'bun:test'
import { allVms, attentionItems, overviewCounts, usageName, usageTotals } from './overview.ts'
import { machine, workload } from './testing.ts'

const machines = [
  machine({ name: 'a', workloads: [workload({ id: 'w1', state: 'running' }), workload({ id: 'w2', state: 'stopped' })] }),
  machine({ name: 'b', state: 'offline' }),
  machine({ name: 'c', problems: [{ code: 'container_tool_missing', message: 'No tool.', fix: 'Install it.' }], workloads: [workload({ id: 'w3', state: 'running' })] }),
]

test('every VM comes with its machine', () => {
  expect(allVms(machines).map(({ machine, workload }) => `${machine.name}/${workload.id}`)).toEqual(['a/w1', 'a/w2', 'c/w3'])
  expect(allVms([])).toEqual([])
})

test('the overview counts machines, VMs and what needs attention', () => {
  expect(overviewCounts(machines)).toEqual({ machines: 3, online: 2, vms: 3, running: 2, needAttention: 2 })
  expect(overviewCounts([])).toEqual({ machines: 0, online: 0, vms: 0, running: 0, needAttention: 0 })
})

test('an offline machine and a machine problem each become one plain item', () => {
  const items = attentionItems(machines)
  expect(items.map((item) => [item.machine, item.kind])).toEqual([['b', 'offline'], ['c', 'problem']])
  expect(items[1]?.fix).toBe('Install it.')
  expect(attentionItems([])).toEqual([])
})

test('usage adds up and names the VM when there is one', () => {
  const rows = [{ machine: 'a', workload: null, requests: 2, prompt_tokens: 10, completion_tokens: 5 }, { machine: 'a', workload: 'w1', requests: 1, prompt_tokens: 3, completion_tokens: 4 }]
  expect(usageTotals(rows)).toEqual({ requests: 3, promptTokens: 13, completionTokens: 9 })
  expect(usageTotals([])).toEqual({ requests: 0, promptTokens: 0, completionTokens: 0 })
  expect(rows.map(usageName)).toEqual(['a', 'a / w1'])
})

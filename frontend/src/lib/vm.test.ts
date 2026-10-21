import { test, expect } from 'bun:test'
import { findServer, findWorkload, headerAction, monitoringMessage, specsText, tabLabel, vmFacts, VM_TABS } from './vm.ts'
import { machine as aMachine, workload } from './testing.ts'

const box = workload({ id: 'w1', name: 'build-box', state: 'running', cpu: 2, ram_mb: 4096, disk_gb: 40, address: '10.0.0.5', bundle_version: '0.4.0' })
const machine = aMachine({ id: 'mac-mini', name: 'Mac mini', workloads: [box, workload({ id: 'w2', name: 'old', state: 'stopped' })] })

test('the tabs are the MAAS ones, in the MAAS order, with a big first letter', () => {
  expect(VM_TABS.map(tabLabel)).toEqual(['Overview', 'Monitoring', 'Access', 'Danger'])
})

test('a VM is found by its id on its machine, and a wrong id finds nothing', () => {
  expect(findWorkload(machine, 'w2')?.name).toBe('old')
  expect(findWorkload(machine, 'nope')).toBeUndefined()
  expect(findServer(machine, 'w1')).toMatchObject({ display: 'build-box', status: 'running', cls: 'run' })
  expect(findServer(machine, 'nope')).toBeUndefined()
})

test('the header offers Start to a stopped VM, Stop to a running one, nothing while it is being made', () => {
  expect(['stopped', 'running', 'creating', 'starting', 'failed'].map(headerAction)).toEqual(['start', 'stop', null, null, null])
})

test('specs read like MAAS: vCPU, memory, disk', () => {
  expect(specsText(box)).toBe('2 vCPU · 4 GB · 40 GB')
})

test('the Overview rows come from the VM and its machine; nothing is invented', () => {
  const facts = vmFacts(machine, box, '0.4.0')
  expect(facts.map((fact) => fact.label)).toEqual(['ID', 'Status', 'Ruvio', 'Runtime', 'Specs', 'Address', 'Machine'])
  expect(facts.find((fact) => fact.label === 'Status')?.value).toBeNull()
  expect(facts.find((fact) => fact.label === 'Ruvio')?.value).toBe('chat 0.4.0')
  expect(facts.find((fact) => fact.label === 'Address')?.value).toBe('10.0.0.5')
})

test('a VM with no chat and no address says so in words', () => {
  const facts = vmFacts(machine, workload({ address: null }), undefined)
  expect([facts[2]?.value, facts[5]?.value]).toEqual(['not installed', '— none yet —'])
})

test('Monitoring says why there are no numbers', () => {
  expect(monitoringMessage('stopped')).toBe('● stopped — no live metrics')
  expect(monitoringMessage('running')).toBe('no live metrics reported yet')
})

import { test, expect } from 'bun:test'
import { machinesMenu, vmsMenu } from './sidebar.ts'

const vmsMarked = (route: string) => vmsMenu(route).filter((item) => item.on).map((item) => item.label)

test('the VMs dropdown has two items, All VMs then Create VM, and no machine names', () => {
  expect(vmsMenu('/vms').map((item) => [item.label, item.href])).toEqual([['All VMs', '#/vms'], ['Create VM', '#/vms/create']])
})

test('the VMs page being looked at is marked, also with a machine in the address', () => {
  expect(vmsMarked('/vms')).toEqual(['All VMs'])
  expect(vmsMarked('/vms?machine=mac-mini')).toEqual(['All VMs'])
  expect(vmsMarked('/vms/create')).toEqual(['Create VM'])
  expect(vmsMarked('/vms/create?machine=mac-mini')).toEqual(['Create VM'])
})

test('on any other page nothing in the VMs dropdown is marked, and the VMs pages mark nothing in the Machines dropdown', () => {
  for (const route of ['/', '/usage', '/health', '/settings', '/machines', '/machines/find', '/machines/details?id=a&vm=w-1']) expect(vmsMarked(route), route).toEqual([])
  expect(machinesMenu('/vms').filter((item) => item.on)).toEqual([])
  expect(machinesMenu('/vms/create').filter((item) => item.on)).toEqual([])
})

const marked = (route: string) => machinesMenu(route).filter((item) => item.on).map((item) => item.label)

test('the dropdown has two items: the machine list, then Find machines (the machines themselves are on the list page)', () => {
  expect(machinesMenu('/machines').map((item) => [item.label, item.href])).toEqual([['Machine list', '#/machines'], ['Find machines', '#/machines/find']])
})

test('the page being looked at is marked', () => {
  expect(marked('/machines')).toEqual(['Machine list'])
  expect(marked('/machines/find')).toEqual(['Find machines'])
  expect(marked('/deployments')).toEqual(['Machine list'])
})

test('a machine\'s own page and its VM pages belong to the list, so the list stays marked', () => {
  expect(marked('/machines/details?id=rtx-pc')).toEqual(['Machine list'])
  expect(marked('/machines/details?id=rtx-pc&vm=w-1')).toEqual(['Machine list'])
})

test('on any other page of the panel nothing in the dropdown is marked', () => {
  for (const route of ['/', '/usage', '/health', '/settings']) expect(marked(route), route).toEqual([])
})

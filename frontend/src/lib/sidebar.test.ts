import { test, expect } from 'bun:test'
import { machinesMenu, settingsMenu } from './sidebar.ts'

test('the VMs pages mark nothing in the Machines dropdown', () => {
  for (const route of ['/vms', '/vms?machine=mac-mini', '/vms/create']) expect(machinesMenu(route).filter((item) => item.on), route).toEqual([])
})

const marked = (route: string) => machinesMenu(route).filter((item) => item.on).map((item) => item.label)

test('the dropdown has three items: the machine list, Find machines, then Share a PC (the machines themselves are on the list page)', () => {
  expect(machinesMenu('/machines').map((item) => [item.label, item.href])).toEqual([['Machine list', '#/machines'], ['Find machines', '#/machines/find'], ['Share a PC', '#/share']])
})

test('the page being looked at is marked', () => {
  expect(marked('/machines')).toEqual(['Machine list'])
  expect(marked('/machines/find')).toEqual(['Find machines'])
  expect(marked('/share')).toEqual(['Share a PC'])
  expect(marked('/deployments')).toEqual(['Machine list'])
})

test('a machine\'s own page and its VM pages belong to the list, so the list stays marked', () => {
  expect(marked('/machines/details?id=rtx-pc')).toEqual(['Machine list'])
  expect(marked('/machines/details?id=rtx-pc&vm=w-1')).toEqual(['Machine list'])
})

test('on any other page of the panel nothing in the dropdown is marked', () => {
  for (const route of ['/', '/usage', '/health', '/settings']) expect(marked(route), route).toEqual([])
})

test('the Settings dropdown has General and AI access (MCP), and marks the page being looked at', () => {
  expect(settingsMenu('/settings').map((item) => [item.label, item.href, item.on])).toEqual([['General', '#/settings', true], ['AI access (MCP)', '#/mcp', false]])
  expect(settingsMenu('/mcp').filter((item) => item.on).map((item) => item.label)).toEqual(['AI access (MCP)'])
  expect(settingsMenu('/machines').filter((item) => item.on)).toEqual([])
})

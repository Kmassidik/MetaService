import { test, expect } from 'bun:test'
import { machine } from './testing.ts'
import { machinesMenu } from './sidebar.ts'

const fleet = [machine({ id: 'mac-studio', name: 'Mac Studio' }), machine({ id: 'rtx-pc', name: 'RTX PC' })]
const marked = (route: string) => machinesMenu(route, fleet).filter((item) => item.on).map((item) => item.label)

test('the dropdown lists the machine list, every machine, then Find machines', () => {
  expect(machinesMenu('/machines', fleet).map((item) => [item.label, item.href])).toEqual([
    ['Machine list', '#/machines'], ['Mac Studio', '#/machines/details?id=mac-studio'], ['RTX PC', '#/machines/details?id=rtx-pc'], ['Find machines', '#/machines/find']])
})

test('with no machines the dropdown still has the list and Find machines', () => {
  expect(machinesMenu('/machines', []).map((item) => item.label)).toEqual(['Machine list', 'Find machines'])
})

test('exactly one item is marked: the page the person is on', () => {
  expect(marked('/machines')).toEqual(['Machine list'])
  expect(marked('/machines/find')).toEqual(['Find machines'])
  expect(marked('/machines/details?id=rtx-pc')).toEqual(['RTX PC'])
  expect(marked('/machines/details?id=rtx-pc&vm=w-1')).toEqual(['RTX PC'])
  expect(marked('/deployments')).toEqual(['Machine list'])
})

test('a machine page that is not one of the machines marks nothing', () => {
  expect(marked('/machines/details?id=gone')).toEqual([])
})

test('on any other page of the panel nothing in the dropdown is marked', () => {
  for (const route of ['/', '/usage', '/health', '/settings']) expect(marked(route), route).toEqual([])
})

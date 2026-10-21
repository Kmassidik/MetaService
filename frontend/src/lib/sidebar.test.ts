import { test, expect } from 'bun:test'
import { machinesMenu } from './sidebar.ts'

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

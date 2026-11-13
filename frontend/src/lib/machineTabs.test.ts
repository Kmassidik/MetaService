import { test, expect } from 'bun:test'
import { DEFAULT_TAB, machineTabs, nextTab, pollsLive, tabFromName } from './machineTabs.ts'

test('the tabs are Live, Network, Compute, Storage, Environment, Activity, in that order', () => {
  expect(machineTabs().map((tab) => tab.label)).toEqual(['Live', 'Network', 'Compute', 'Storage', 'Environment', 'Activity'])
  expect(machineTabs().map((tab) => tab.id)).toEqual(['live', 'network', 'vms', 'storage', 'environment', 'activity'])
})

test('the Network tab is found by its name, and its arrow keys sit next to Live', () => {
  expect(tabFromName('Network')).toBe('network')
  expect(nextTab('live', 'ArrowRight')).toBe('network')
  expect(nextTab('network', 'ArrowRight')).toBe('vms')
})

test('old tab names land on a sensible new tab, in any letter case', () => {
  expect(tabFromName('overview')).toBe('environment')
  expect(tabFromName('Deployments')).toBe('vms')
  expect(tabFromName('vms')).toBe('vms')
  expect(tabFromName('compute')).toBe('vms')
  expect(tabFromName('ACTIVITY')).toBe('activity')
  expect(tabFromName('live')).toBe('live')
  expect(tabFromName('Storage')).toBe('storage')
})

test('no name, or a name nobody knows, opens Live', () => {
  expect(tabFromName(null)).toBe(DEFAULT_TAB)
  expect(tabFromName('')).toBe('live')
  expect(tabFromName('nope')).toBe('live')
})

test('arrow keys move between tabs and wrap; Home and End jump; other keys do nothing', () => {
  expect(nextTab('activity', 'ArrowRight')).toBe('live')
  expect(nextTab('live', 'ArrowLeft')).toBe('activity')
  expect(nextTab('vms', 'Home')).toBe('live')
  expect(nextTab('vms', 'End')).toBe('activity')
  expect(nextTab('vms', 'Enter')).toBeNull()
})

test('the live numbers are asked for only while Live is shown', () => {
  expect(pollsLive('live')).toBe(true)
  expect((['network', 'vms', 'environment', 'activity'] as const).map(pollsLive)).toEqual([false, false, false, false])
})

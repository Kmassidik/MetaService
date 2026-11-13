import { expect, test } from 'bun:test'
import { addedName, rowStatus, withKnownMachines } from './scanRows.ts'
import { machine } from './testing.ts'
import type { Device } from './types.ts'


test('a row the scan already knew as a machine keeps that name', () => {
  expect(addedName({ ip: '192.168.0.50', machine: 'rtx' }, [])).toBe('rtx')
})

test('a row whose address became a machine after the scan shows as added at once', () => {
  expect(addedName({ ip: '192.168.0.50' }, [machine({ id: 'rtx5090', name: 'rtx5090', ip: '192.168.0.50' })])).toBe('rtx5090')
  expect(addedName({ ip: '192.168.0.50', machine: null }, [machine({ id: 'rtx5090', name: 'rtx5090', ip: '192.168.0.50' })])).toBe('rtx5090')
})

test('a row nobody has added stays open for adding', () => {
  expect(addedName({ ip: '192.168.0.50' }, [machine({ id: 'mini', name: 'mini', ip: '192.168.0.40' }), machine({ id: 'noip', name: 'noip' })])).toBeNull()
})

const mini = { ip: '192.168.0.40' }
const notRouter = { gateway: false }

test('the router is not a machine to add', () => {
  expect(rowStatus({ ip: '192.168.0.1' }, [], { gateway: true })).toEqual({ kind: 'router' })
})

test('a device that is not added yet can be added, including the computer the parent runs on (its own label is shown beside Add)', () => {
  expect(rowStatus(mini, [], notRouter)).toEqual({ kind: 'add' })
})

test('a device that is added shows its name and no Add button', () => {
  expect(rowStatus(mini, [machine({ id: 'lucas-mac-mini', name: 'lucas-mac-mini', ip: '192.168.0.40' })], notRouter)).toEqual({ kind: 'added', name: 'lucas-mac-mini' })
})

test('a device whose Agent already answers is told so, and an added one wins over that', () => {
  expect(rowStatus({ ip: '192.168.0.60', agent_port_open: true }, [], notRouter)).toEqual({ kind: 'agent' })
  expect(rowStatus({ ip: '192.168.0.60', agent_port_open: true }, [machine({ id: 'x', name: 'x', ip: '192.168.0.60' })], notRouter)).toEqual({ kind: 'added', name: 'x' })
})

const device = (ip: string, extra: Partial<Device> = {}): Device => ({ id: `scan-${ip}`, ip, ...extra })

test('the scan rows and every registered machine the scan missed show, sorted by address', () => {
  const rows = withKnownMachines([device('192.168.0.1', { hostname: 'router' })], [
    machine({ id: 'a', name: 'alpha', ip: '192.168.0.10' }),
    machine({ id: 'b', name: 'beta', ip: '192.168.0.30' }),
    machine({ id: 'c', name: 'gamma', ip: '192.168.0.50' }),
  ])
  expect(rows.map((row) => row.ip)).toEqual(['192.168.0.1', '192.168.0.10', '192.168.0.30', '192.168.0.50'])
  expect(rows.slice(1).map((row) => rowStatus(row, [], notRouter))).toEqual([
    { kind: 'added', name: 'alpha' },
    { kind: 'added', name: 'beta' },
    { kind: 'added', name: 'gamma' },
  ])
})

test('a machine whose address the scan already lists is not shown twice', () => {
  const rows = withKnownMachines([device('192.168.0.40', { hostname: 'mini' })], [machine({ id: 'mini', name: 'mini', ip: '192.168.0.40' })])
  expect(rows).toHaveLength(1)
  expect(rows[0]?.hostname).toBe('mini')
})

test('a machine without an address is skipped', () => {
  expect(withKnownMachines([], [machine({ id: 'noip', name: 'noip' }), machine({ id: 'empty', name: 'empty', ip: '' })])).toEqual([])
})

test('an empty scan still shows the registered machines', () => {
  const rows = withKnownMachines([], [machine({ id: 'a', name: 'alpha', ip: '192.168.0.10' }), machine({ id: 'b', name: 'beta', ip: '192.168.0.30' })])
  expect(rows.map((row) => row.ip)).toEqual(['192.168.0.10', '192.168.0.30'])
})

test('addresses sort by their numbers, so .9 comes before .10', () => {
  const rows = withKnownMachines([device('192.168.0.10'), device('192.168.0.9')], [])
  expect(rows.map((row) => row.ip)).toEqual(['192.168.0.9', '192.168.0.10'])
})

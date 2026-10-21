import { expect, test } from 'bun:test'
import { addedName } from './scanRows.ts'
import { machine } from './testing.ts'


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

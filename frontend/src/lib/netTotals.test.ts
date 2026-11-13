import { expect, test } from 'bun:test'
import { totalsOf } from './netTotals.ts'
import { parseUsage } from './usageParse.ts'

const usage = (range: string, rows: unknown[]) => parseUsage({ range, since: 0, machines: rows, total: { in_bytes: 0, out_bytes: 0 } })
const row = (machineId: string, inBytes: number, outBytes: number) => ({ machine_id: machineId, name: machineId, in_bytes: inBytes, out_bytes: outBytes, in_peak_bps: 0, out_peak_bps: 0 })

test('the machine row is picked by its id, from both answers', () => {
  const today = usage('today', [row('mini', 10, 4), row('studio', 99, 99)])
  const month = usage('month', [row('studio', 5, 5), row('mini', 1000, 200)])
  expect(totalsOf(today, month, 'mini')).toEqual({ downToday: 10, upToday: 4, downMonth: 1000, upMonth: 200 })
})

test('a machine with no row in either answer has no totals', () => {
  const today = usage('today', [row('studio', 1, 1)])
  const month = usage('month', [row('mini', 1, 1)])
  expect(totalsOf(today, month, 'mini')).toBeNull()
})

test('a machine with a row in only one answer has no totals either', () => {
  expect(totalsOf(usage('today', [row('mini', 1, 1)]), usage('month', []), 'mini')).toBeNull()
})

// The four totals of one machine on the Network tab (downloaded and uploaded today and this month), picked out of the all-machines usage answers. Pure.
import type { MachineUsage, UsageReply } from './usageParse.ts'

export interface MachineTotals {
  downToday: number
  upToday: number
  downMonth: number
  upMonth: number
}

/** This machine's row in one usage answer, or null when the answer has none for it. */
function rowOf(reply: UsageReply, machineId: string): MachineUsage | null {
  return reply.machines.find((row) => row.machineId === machineId) ?? null
}

/** The four totals of a machine, or null when either answer has no row for it (the helper has not reported yet). */
export function totalsOf(today: UsageReply, month: UsageReply, machineId: string): MachineTotals | null {
  const day = rowOf(today, machineId)
  const monthRow = rowOf(month, machineId)
  if (day === null || monthRow === null) return null
  return { downToday: day.inBytes, upToday: day.outBytes, downMonth: monthRow.inBytes, upMonth: monthRow.outBytes }
}

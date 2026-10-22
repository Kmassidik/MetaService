// Checks the answer of GET /api/machines/{id}/stats/history. A shape that is wrong throws UnreadableAnswer; the optional numbers are left out when absent or of the wrong kind.
import { UnreadableAnswer } from './machineDetail.ts'
import { breakdown } from './statsExtrasParse.ts'
import { historyGpus } from './statsGpuParse.ts'
import type { StatsHistoryPoint, StatsHistoryReply } from './types.ts'

type Rec = Record<string, unknown>

const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)
const finiteNumber = (value: unknown): number | undefined => (typeof value === 'number' && Number.isFinite(value) ? value : undefined)
const LOAD_VALUES = 3

function required(source: Rec, key: string): number {
  const value = finiteNumber(source[key])
  if (value === undefined) throw new UnreadableAnswer(`${key} is not a number`)
  return value
}

function nullable(source: Rec, key: string): number | null {
  const value = source[key]
  return value === null || value === undefined ? null : required(source, key)
}

function load(value: unknown): [number, number, number] | undefined {
  if (!Array.isArray(value) || value.length !== LOAD_VALUES) return undefined
  const [one, five, fifteen] = value.map(finiteNumber)
  return one === undefined || five === undefined || fifteen === undefined ? undefined : [one, five, fifteen]
}

function pointOf(source: Rec): StatsHistoryPoint {
  const states = breakdown(source.cpu_breakdown)
  const loads = load(source.load)
  const read = finiteNumber(source.disk_read)
  const write = finiteNumber(source.disk_write)
  const drops = finiteNumber(source.net_drops)
  const processes = finiteNumber(source.processes_count)
  const gpus = historyGpus(source.gpus)
  return {
    t: required(source, 't'), cpu_percent: required(source, 'cpu_percent'),
    mem_used: required(source, 'mem_used'), mem_cached: required(source, 'mem_cached'), mem_total: required(source, 'mem_total'),
    swap_used: required(source, 'swap_used'), swap_total: required(source, 'swap_total'),
    net_in_bps: nullable(source, 'net_in_bps'), net_out_bps: nullable(source, 'net_out_bps'),
    ...(states === undefined ? {} : { cpu_breakdown: states }),
    ...(loads === undefined ? {} : { load: loads }),
    ...(read === undefined ? {} : { disk_read: read }),
    ...(write === undefined ? {} : { disk_write: write }),
    ...(drops === undefined ? {} : { net_drops: drops }),
    ...(processes === undefined ? {} : { processes_count: processes }),
    ...(gpus === undefined ? {} : { gpus }),
  }
}

export function parseHistoryReply(data: unknown): StatsHistoryReply {
  if (!isRec(data)) throw new UnreadableAnswer('the history is not an object')
  const points = data.points
  if (!Array.isArray(points)) throw new UnreadableAnswer('points is not a list')
  return {
    interval_seconds: required(data, 'interval_seconds'),
    points: points.map((item) => {
      if (!isRec(item)) throw new UnreadableAnswer('a history point is not an object')
      return pointOf(item)
    }),
  }
}

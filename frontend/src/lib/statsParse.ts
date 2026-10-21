// Checks the answer of GET /api/machines/{id}/stats before the page trusts it. A shape that is wrong throws UnreadableAnswer.
import { UnreadableAnswer } from './machineDetail.ts'
import type { MachineStats, MachineStatsReply, StatsCpu, StatsDisk, StatsGpu, StatsMemory, StatsNetwork, StatsProcess } from './types.ts'

type Rec = Record<string, unknown>

const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)

function rec(value: unknown, what: string): Rec {
  if (!isRec(value)) throw new UnreadableAnswer(`${what} is not an object`)
  return value
}

function num(source: Rec, key: string): number {
  const value = source[key]
  if (typeof value === 'number' && Number.isFinite(value)) return value
  throw new UnreadableAnswer(`${key} is not a number`)
}

function finite(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  throw new UnreadableAnswer('a core percent is not a number')
}

function numOrNull(source: Rec, key: string): number | null {
  const value = source[key]
  return value === null || value === undefined ? null : num(source, key)
}

function str(source: Rec, key: string): string {
  const value = source[key]
  if (typeof value === 'string') return value
  throw new UnreadableAnswer(`${key} is not text`)
}

function strOrNull(source: Rec, key: string): string | null {
  const value = source[key]
  return value === null || value === undefined ? null : str(source, key)
}

function list(source: Rec, key: string): unknown[] {
  const value = source[key]
  if (Array.isArray(value)) return value
  throw new UnreadableAnswer(`${key} is not a list`)
}

function cpu(source: Rec): StatsCpu {
  const load = rec(source.load, 'load')
  const cores = source.cores_percent
  return {
    core_count: num(source, 'core_count'),
    total_percent: numOrNull(source, 'total_percent'),
    cores_percent: cores === null || cores === undefined ? null : list(source, 'cores_percent').map(finite),
    load: { one: numOrNull(load, 'one'), five: numOrNull(load, 'five'), fifteen: numOrNull(load, 'fifteen') },
  }
}

function memory(source: Rec): StatsMemory {
  return {
    total_bytes: num(source, 'total_bytes'), used_bytes: num(source, 'used_bytes'), cached_bytes: num(source, 'cached_bytes'), free_bytes: num(source, 'free_bytes'),
    swap_total_bytes: num(source, 'swap_total_bytes'), swap_used_bytes: num(source, 'swap_used_bytes'),
  }
}

const disk = (source: Rec): StatsDisk => ({
  mount: str(source, 'mount'), name: str(source, 'name'), fs: str(source, 'fs'),
  total_bytes: num(source, 'total_bytes'), used_bytes: num(source, 'used_bytes'), free_bytes: num(source, 'free_bytes'),
})

const network = (source: Rec): StatsNetwork => ({
  received_total_bytes: num(source, 'received_total_bytes'), sent_total_bytes: num(source, 'sent_total_bytes'),
  received_bytes_per_second: numOrNull(source, 'received_bytes_per_second'), sent_bytes_per_second: numOrNull(source, 'sent_bytes_per_second'),
})

const gpu = (source: Rec): StatsGpu => ({
  name: str(source, 'name'), utilization_percent: numOrNull(source, 'utilization_percent'), memory_used_bytes: numOrNull(source, 'memory_used_bytes'),
  memory_total_bytes: numOrNull(source, 'memory_total_bytes'), temperature_celsius: numOrNull(source, 'temperature_celsius'),
})

const processOf = (source: Rec): StatsProcess => ({
  pid: num(source, 'pid'), name: str(source, 'name'), user: str(source, 'user'), cpu_percent: numOrNull(source, 'cpu_percent'), memory_bytes: num(source, 'memory_bytes'),
})

function parseStats(source: Rec): MachineStats {
  const measuring = source.measuring
  if (typeof measuring !== 'boolean') throw new UnreadableAnswer('measuring is not true or false')
  return {
    taken_at: str(source, 'taken_at'), measuring, uptime_seconds: num(source, 'uptime_seconds'),
    cpu: cpu(rec(source.cpu, 'cpu')), memory: memory(rec(source.memory, 'memory')),
    disks: list(source, 'disks').map((item) => disk(rec(item, 'disk'))),
    network: network(rec(source.network, 'network')),
    gpus: source.gpus === undefined ? [] : list(source, 'gpus').map((item) => gpu(rec(item, 'gpu'))),
    processes: list(source, 'processes').map((item) => processOf(rec(item, 'process'))),
  }
}

/** The reply of the stats route, or an UnreadableAnswer naming what was wrong. */
export function parseStatsReply(data: unknown): MachineStatsReply {
  const source = rec(data, 'the reply')
  const state = source.state
  if (state !== 'online' && state !== 'offline' && state !== 'old_helper') throw new UnreadableAnswer('state is not known')
  const stats = source.stats === null || source.stats === undefined ? null : parseStats(rec(source.stats, 'stats'))
  return { state, last_seen: strOrNull(source, 'last_seen'), fetched_at: strOrNull(source, 'fetched_at'), stats }
}

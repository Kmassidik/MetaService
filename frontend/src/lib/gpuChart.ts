// What the GPU charts draw: one line per GPU for use, memory, temperature and power. Pure functions, no DOM. A GPU that gave no number for a chart is not listed in it,
// and a chart nobody has numbers for is null (the card is not drawn), so there is never a flat line of zeros.
import { niceBytesTicks, niceTicks } from './charts.ts'
import type { ChartColour, ChartModel, DashStyle, SeriesSpec } from './chartSeries.ts'
import { column, type LiveGpu, type LivePoint } from './liveSeries.ts'
import { formatBytes } from './stats.ts'
import type { StatsGpu } from './types.ts'

const TICK_COUNT = 4
const USE_FLOOR_PERCENT = 10
const TEMPERATURE_FLOOR_CELSIUS = 60
const POWER_FLOOR_WATTS = 50
const SHORT_NAME_LIMIT = 16
const ELLIPSIS = '…'

/** One colour and one line pattern per GPU number, so lines differ without colour too. */
const LINE_LOOKS: readonly { colour: ChartColour; dash: DashStyle }[] = [
  { colour: 'blue', dash: 'solid' }, { colour: 'orange', dash: 'dashed' }, { colour: 'green', dash: 'dotted' }, { colour: 'purple', dash: 'solid' },
  { colour: 'teal', dash: 'dashed' }, { colour: 'navy', dash: 'dotted' }, { colour: 'olive', dash: 'solid' }, { colour: 'red', dash: 'dashed' },
]

/** What the lines are named after and, for memory, how big each GPU's memory is. */
export interface GpuInfo { index: number; name: string; totalBytes: number | null }

export const gpuInfos = (gpus: readonly StatsGpu[]): GpuInfo[] => gpus.map((gpu, index) => ({ index, name: gpu.name, totalBytes: gpu.memory_total_bytes }))

const MAKER_WORDS = /\b(NVIDIA|GeForce|AMD|Radeon|Intel|Apple|Corporation|\(R\)|\(TM\)|GPU)\b/gi

/** "NVIDIA GeForce RTX 5090" -> "RTX 5090". Falls back to the whole name, cut when long. */
export function shortGpuName(name: string): string {
  const stripped = name.replace(MAKER_WORDS, ' ').replace(/\s+/g, ' ').trim()
  const short = stripped === '' ? name.trim() : stripped
  return short.length > SHORT_NAME_LIMIT ? `${short.slice(0, SHORT_NAME_LIMIT - 1)}${ELLIPSIS}` : short
}

/** "GPU 0 · RTX 5090" on a machine with several GPUs, "GPU · RTX 5090" on one. */
export const gpuLineName = (info: GpuInfo, many: boolean): string => `${many ? `GPU ${info.index}` : 'GPU'} · ${shortGpuName(info.name)}`

const percent = (value: number): string => `${value.toFixed(1)}%`
const wholePercent = (value: number): string => `${Math.round(value)}%`
const degrees = (value: number): string => `${value.toFixed(1)} °C`
const wholeDegrees = (value: number): string => `${Math.round(value)} °C`
const watts = (value: number): string => `${value.toFixed(1)} W`
const wholeWatts = (value: number): string => `${Math.round(value)} W`

type Pick = (gpu: LiveGpu) => number | null

function valuesOf(points: readonly LivePoint[], index: number, pick: Pick): (number | null)[] {
  return column(points, (point) => {
    const gpu = point.gpus.find((one) => one.index === index)
    return gpu === undefined ? null : pick(gpu)
  })
}

function lines(points: readonly LivePoint[], infos: readonly GpuInfo[], pick: Pick, format: (value: number) => string): SeriesSpec[] {
  const many = infos.length > 1
  return infos.flatMap((info): SeriesSpec[] => {
    const values = valuesOf(points, info.index, pick)
    if (values.every((value) => value === null)) return []
    const look = LINE_LOOKS[info.index % LINE_LOOKS.length] ?? { colour: 'blue', dash: 'solid' }
    return [{ key: `gpu-${info.index}`, name: gpuLineName(info, many), colour: look.colour, dash: look.dash, values, format, drawn: true }]
  })
}

const topOf = (spec: readonly SeriesSpec[]): number => Math.max(0, ...spec.flatMap((one) => one.values.filter((value): value is number => value !== null)))

function fitted(points: readonly LivePoint[], series: SeriesSpec[], floor: number, axisLabel: (value: number) => string): ChartModel | null {
  if (series.length === 0) return null
  const ticks = niceTicks(Math.max(floor, topOf(series)), TICK_COUNT)
  return { times: points.map((point) => point.t), series, stacked: false, ceiling: ticks[ticks.length - 1] ?? floor, ticks, axisLabel }
}

/** Use of each GPU, in percent. */
export function gpuUseChart(points: readonly LivePoint[], infos: readonly GpuInfo[]): ChartModel | null {
  return fitted(points, lines(points, infos, (gpu) => gpu.use, percent), USE_FLOOR_PERCENT, wholePercent)
}

/** Memory in use per GPU. The axis ends at the biggest known total, or fits what was seen when no total is known. */
export function gpuMemoryChart(points: readonly LivePoint[], infos: readonly GpuInfo[]): ChartModel | null {
  const series = lines(points, infos, (gpu) => gpu.memory, formatBytes)
  if (series.length === 0) return null
  const total = Math.max(0, ...infos.map((info) => info.totalBytes ?? 0))
  const ceiling = Math.max(total, topOf(series))
  const ticks = total > 0 && total >= topOf(series) ? Array.from({ length: TICK_COUNT + 1 }, (_, step) => (total * step) / TICK_COUNT) : niceBytesTicks(ceiling, TICK_COUNT).ticks
  return { times: points.map((point) => point.t), series, stacked: false, ceiling: ticks[ticks.length - 1] ?? ceiling, ticks, axisLabel: formatBytes }
}

/** Temperature of each GPU, in degrees Celsius. */
export function gpuTemperatureChart(points: readonly LivePoint[], infos: readonly GpuInfo[]): ChartModel | null {
  return fitted(points, lines(points, infos, (gpu) => gpu.temperature, degrees), TEMPERATURE_FLOOR_CELSIUS, wholeDegrees)
}

/** Power draw of each GPU, in watts: its own chart, never on the temperature axis. */
export function gpuPowerChart(points: readonly LivePoint[], infos: readonly GpuInfo[]): ChartModel | null {
  return fitted(points, lines(points, infos, (gpu) => gpu.power, watts), POWER_FLOOR_WATTS, wholeWatts)
}

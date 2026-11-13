// Reads the answers of GET /api/network/usage and GET /api/network/usage/daily, and formats the numbers of the Traffic block. Nothing here trusts the
// shape: a field of the wrong type, or a negative or NaN number, becomes 0; text loses its control characters and is cut short; the lists are capped.
// The parsers never throw. Pure: no DOM, so it is easy to test.

export const USAGE_RANGES = ['today', 'month', '30d'] as const
export type UsageRange = (typeof USAGE_RANGES)[number]
export const DAY_COUNTS = [7, 30] as const
export type DayCount = (typeof DAY_COUNTS)[number]

/** The most machines kept from one answer. */
export const MAX_MACHINES = 256
/** The most days kept from one answer. */
export const MAX_DAYS = 31
/** The longest name or range text kept; anything longer is cut. */
export const MAX_TEXT = 100
/** One day in seconds: the step between two day starts. */
export const DAY_SECONDS = 86_400

const DECIMAL_STEP = 1000
const BYTE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB'] as const
const GIGABYTE_INDEX = 3
const DECIMALS_BELOW_GIGABYTE = 0
const DECIMALS_FROM_GIGABYTE = 1
const BITS_PER_BYTE = 8
const KILOBITS_PER_MEGABIT = 1000
const MEGABIT = 1_000_000
const RATE_DECIMALS = 1
const PERCENT = 100
const PERCENT_DECIMALS = 1
const CONTROL_MAX = 31
const DELETE_CHAR = 127
const C1_MIN = 128
const C1_MAX = 159

export interface UsageFigures {
  inBytes: number
  outBytes: number
  inPeakBps: number
  outPeakBps: number
}

export interface MachineUsage extends UsageFigures {
  machineId: string
  name: string
}

export interface UsageReply {
  range: string
  since: number
  machines: MachineUsage[]
  totalIn: number
  totalOut: number
}

export interface UsageDay extends UsageFigures {
  dayStart: number
}

type Fields = Record<string, unknown>

const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)

/** A finite number from zero up, or 0 when the value is anything else. */
function amount(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0
}

/** True for the characters a name must not carry: the C0 controls, DEL and the C1 controls. */
function isControlCharacter(character: string): boolean {
  const code = character.charCodeAt(0)
  return code <= CONTROL_MAX || code === DELETE_CHAR || (code >= C1_MIN && code <= C1_MAX)
}

/** Text with its control characters removed and cut to MAX_TEXT characters; anything that is not text is empty. */
function text(value: unknown): string {
  if (typeof value !== 'string') return ''
  return Array.from(value).filter((character) => !isControlCharacter(character)).slice(0, MAX_TEXT).join('')
}

/** The byte and rate figures of one row, every number checked. */
function figuresOf(source: Fields): UsageFigures {
  return {
    inBytes: amount(source.in_bytes),
    outBytes: amount(source.out_bytes),
    inPeakBps: amount(source.in_peak_bps),
    outPeakBps: amount(source.out_peak_bps),
  }
}

/** One machine's row. */
function machineOf(source: Fields): MachineUsage {
  return { machineId: text(source.machine_id), name: text(source.name), ...figuresOf(source) }
}

/** One day's row. */
function dayOf(source: Fields): UsageDay {
  return { dayStart: amount(source.day_start), ...figuresOf(source) }
}

/** The usage answer for one range, every field checked. Rows that are not objects are left out. */
export function parseUsage(raw: unknown): UsageReply {
  const source = isFields(raw) ? raw : {}
  const rows = Array.isArray(source.machines) ? source.machines : []
  const total = isFields(source.total) ? source.total : {}
  return {
    range: text(source.range),
    since: amount(source.since),
    machines: rows.filter(isFields).slice(0, MAX_MACHINES).map(machineOf),
    totalIn: amount(total.in_bytes),
    totalOut: amount(total.out_bytes),
  }
}

/** The daily answer: one entry per day that has data, every field checked. Rows that are not objects are left out. */
export function parseUsageDaily(raw: unknown): UsageDay[] {
  const source = isFields(raw) ? raw : {}
  const rows = Array.isArray(source.days) ? source.days : []
  return rows.filter(isFields).slice(0, MAX_DAYS).map(dayOf)
}

/** Digits after the decimal point: none below a gigabyte, one from a gigabyte up. */
function decimalsOf(unit: number): number {
  return unit >= GIGABYTE_INDEX ? DECIMALS_FROM_GIGABYTE : DECIMALS_BELOW_GIGABYTE
}

/** The unit that fits a byte count after rounding, with the value in that unit. A value that rounds up to 1000 moves to the next unit. */
function scaleBytes(bytes: number): { value: number; unit: number } {
  let value = bytes
  let unit = 0
  while (unit < BYTE_UNITS.length - 1 && Number(value.toFixed(decimalsOf(unit))) >= DECIMAL_STEP) {
    value /= DECIMAL_STEP
    unit += 1
  }
  return { value, unit }
}

/** A byte count in decimal units (1 KB = 1000 B): "0 B", "999 B", "1 KB", "12 MB", "1.2 GB". */
export function formatBytes(bytes: number): string {
  const { value, unit } = scaleBytes(Math.round(amount(bytes)))
  return `${value.toFixed(decimalsOf(unit))} ${BYTE_UNITS[unit]}`
}

/** A rate in bytes per second, shown in bits: "12.3 Mbit/s" from a megabit up, "512 kbit/s" below that. */
export function formatRate(bytesPerSecond: number): string {
  const bits = amount(bytesPerSecond) * BITS_PER_BYTE
  const kilobits = Math.round(bits / KILOBITS_PER_MEGABIT)
  if (kilobits < KILOBITS_PER_MEGABIT) return `${kilobits} kbit/s`
  return `${(bits / MEGABIT).toFixed(RATE_DECIMALS)} Mbit/s`
}

/** The share of a whole as a percent with one decimal ("12.5 %"), or "0 %" when the whole is 0. */
export function formatShare(part: number, whole: number): string {
  if (amount(whole) === 0) return '0 %'
  return `${((amount(part) / whole) * PERCENT).toFixed(PERCENT_DECIMALS)} %`
}

/** Exactly `count` days, one per DAY_SECONDS step, ending at today's start. Days with no data are zeros. Oldest first. */
export function fillDays(days: UsageDay[], count: number, todayStartEpoch: number): UsageDay[] {
  const filled = Array.from({ length: count }, (_, index) => ({
    dayStart: todayStartEpoch - (count - 1 - index) * DAY_SECONDS,
    inBytes: 0,
    outBytes: 0,
    inPeakBps: 0,
    outPeakBps: 0,
  }))
  for (const day of days) {
    const slot = count - 1 + Math.floor((day.dayStart - todayStartEpoch) / DAY_SECONDS)
    const current = filled[slot]
    if (current === undefined) continue
    filled[slot] = { ...day, dayStart: current.dayStart }
  }
  return filled
}

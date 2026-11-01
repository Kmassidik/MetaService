// The one place the Security page turns a timestamp into text. Times are shown in the viewer's own time zone (with the zone's short name) or in UTC; the zone is
// passed in, never read from the clock or the browser in here, so a test and a picture are the same everywhere. Nothing here throws: a date that cannot be
// read is the text "unknown", a zone the browser does not know is shown as UTC (and says UTC).
export const TIME_MODES = ['local', 'utc'] as const
export type TimeMode = (typeof TIME_MODES)[number]
export const TIME_MODE_LABELS: Record<TimeMode, string> = { local: 'Local', utc: 'UTC' }
export const UTC_ZONE = 'UTC'
export const UNKNOWN_TIME = 'unknown'
const LOCALE = 'en-US'

const formatters = new Map<string, Intl.DateTimeFormat>()

function build(zone: string): Intl.DateTimeFormat | null {
  try {
    return new Intl.DateTimeFormat(LOCALE, {
      timeZone: zone, timeZoneName: 'short', hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
    })
  } catch (error) {
    if (error instanceof RangeError) return null
    throw error
  }
}

/** A formatter for this zone; the UTC one when the browser does not know the zone. */
function formatterFor(zone: string): Intl.DateTimeFormat {
  const known = formatters.get(zone)
  if (known !== undefined) return known
  const made = build(zone) ?? build(UTC_ZONE)
  if (made === null) throw new Error('the browser cannot format UTC times')
  formatters.set(zone, made)
  return made
}

type Parts = Record<string, string>

function partsOf(ms: number, zone: string): Parts {
  const parts: Parts = {}
  for (const part of formatterFor(zone).formatToParts(new Date(ms))) parts[part.type] = part.value
  return parts
}

function parsed(iso: string | null | undefined): number | null {
  const ms = iso === null || iso === undefined ? Number.NaN : Date.parse(iso)
  return Number.isNaN(ms) ? null : ms
}

/** "2026-11-01 15:47 GMT+7": the time in `zone` with the zone's short name; "unknown" when the date cannot be read. */
export function formatTime(iso: string | null | undefined, zone: string): string {
  const ms = parsed(iso)
  if (ms === null) return UNKNOWN_TIME
  const parts = partsOf(ms, zone)
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute} ${parts.timeZoneName}`
}

/** The zone's short name at a moment ("GMT+7", "EST", "UTC"); it changes with daylight saving, so it is asked for a moment. */
export function zoneName(zone: string, at: number): string {
  return partsOf(Number.isNaN(at) ? 0 : at, zone).timeZoneName ?? UTC_ZONE
}

/** The tooltip of a time: the UTC time first, then the viewer's local time (left out when it is the same). */
export function timeTitle(iso: string | null | undefined, localZone: string): string {
  const utc = formatTime(iso, UTC_ZONE)
  const local = formatTime(iso, localZone)
  return utc === UNKNOWN_TIME || local === utc ? utc : `${utc} (${local})`
}

/** The viewer's own zone as the browser reports it; UTC when it does not say. */
export const browserZone = (): string => new Intl.DateTimeFormat().resolvedOptions().timeZone || UTC_ZONE

/** Everything a component needs to draw a time, for one choice of Local or UTC. */
export interface TimeFormat {
  mode: TimeMode
  /** The zone times are drawn in. */
  zone: string
  /** The short zone name for the column header, e.g. "GMT+7". */
  label: string
  show: (iso: string | null | undefined) => string
  title: (iso: string | null | undefined) => string
}

export function makeTimeFormat(mode: TimeMode, localZone: string, at: number): TimeFormat {
  const zone = mode === 'utc' ? UTC_ZONE : localZone
  return { mode, zone, label: zoneName(zone, at), show: (iso) => formatTime(iso, zone), title: (iso) => timeTitle(iso, localZone) }
}

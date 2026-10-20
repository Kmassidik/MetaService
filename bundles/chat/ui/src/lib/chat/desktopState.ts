// What the big view knows about a computer's desktop stream, merged poll by poll. Pure, so it is
// unit-tested apart from the Svelte state.
import { isRecord } from '../check.ts'
import { errorStatus } from '../errors.ts'
import type { Desktop, DesktopMode } from '../types.ts'

const OWNER_BUSY = 409
const KNOWN_MODES: ReadonlySet<unknown> = new Set(['stream', 'browser'])
const isDesktopMode = (value: unknown): value is DesktopMode => KNOWN_MODES.has(value)
const textOf = (value: unknown): string => (typeof value === 'string' ? value : '')

/** No desktop known yet: the view falls back to the browser's screenshots. */
export const NO_DESKTOP: Desktop = Object.freeze({ state: 'unavailable', mode: 'browser', wsPath: '', message: '' })

function desktopOf(data: Record<string, unknown>): Record<string, unknown> {
  return isRecord(data.desktop) ? data.desktop : data
}

function socketPath(desktop: Record<string, unknown>, known: Desktop): string {
  return textOf(desktop.wsPath) || known.wsPath
}

/**
 * The desktop after a successful poll. A reply without a socket path (a raw desktop_ensure result)
 * keeps the path already known, so a working stream is never torn down by it (bug-log #37).
 */
export function nextDesktop(previous: Desktop | undefined, data: unknown): Desktop {
  const known = previous || NO_DESKTOP
  if (!isRecord(data)) return known
  const desktop = desktopOf(data)
  return {
    state: textOf(desktop.state) || known.state,
    mode: isDesktopMode(desktop.mode) ? desktop.mode : known.mode,
    wsPath: socketPath(desktop, known),
    message: textOf(desktop.message),
  }
}

/**
 * The desktop after a failed poll: the owner was busy (409) or this host has no desktop yet. The
 * last known desktop stays, so one busy poll never drops a live stream to a snapshot (bug-log #37).
 */
export function keptDesktop(previous: Desktop | undefined): Desktop {
  return previous || NO_DESKTOP
}

/** Another computer call held the owner for a moment; the next poll simply tries again. */
export function isOwnerBusy(error: unknown): boolean {
  return errorStatus(error) === OWNER_BUSY
}

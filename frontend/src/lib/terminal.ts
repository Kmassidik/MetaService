// The rules of the web terminal that need no browser: the address of the socket, the resize message, the words of the status line,
// when to fit the screen again, and how to read the ticket the parent hands out. The window itself is components/Terminal.svelte.

export type TerminalState = 'connecting' | 'connected' | 'disconnected' | 'error'
export type TerminalEvent = 'connect' | 'open' | 'error' | 'close'

/** Colour class of the status dot: green when connected, red when dead, plain otherwise. */
export type StatusTone = '' | 'ok' | 'no'

export interface Ticket {
  ticket: string
  expiresIn: number
}

export interface Box {
  width: number
  height: number
}

export interface Location {
  protocol: string
  host: string
}

/** The parent accepts 1..500 columns and 1..300 rows; anything else closes the socket with 1008. */
export const MAX_COLS = 500
export const MAX_ROWS = 300

/** WebSocket ready states, as the browser numbers them. */
export const SOCKET_CONNECTING = 0
export const SOCKET_OPEN = 1

const STATUS_WORDS: Record<TerminalState, string> = {
  connecting: 'connecting…',
  connected: 'connected',
  disconnected: 'disconnected',
  error: 'error',
}

const clamp = (value: number, max: number): number => Math.min(max, Math.max(1, Math.round(value)))

/** `wss://host/api/terminal/<ticket>` on an https page, `ws://` on http. The ticket is the only secret in it and works once. */
export function terminalSocketUrl(where: Location, ticket: string): string {
  const scheme = where.protocol === 'https:' ? 'wss' : 'ws'
  return `${scheme}://${where.host}/api/terminal/${encodeURIComponent(ticket)}`
}

/** The text frame that tells the helper the screen size. */
export const resizeMessage = (cols: number, rows: number): string => JSON.stringify({ resize: [clamp(cols, MAX_COLS), clamp(rows, MAX_ROWS)] })

/** What happens to the status when something happens to the socket. A close is final whatever came before it. */
export function nextState(state: TerminalState, event: TerminalEvent): TerminalState {
  if (event === 'connect') return 'connecting'
  if (event === 'close') return 'disconnected'
  if (event === 'error') return 'error'
  return state === 'connecting' ? 'connected' : state
}

/** The words after the dot, with the reason the parent gave when it closed the socket (or why no ticket was given). */
export function statusText(state: TerminalState, reason = ''): string {
  const words = STATUS_WORDS[state]
  return isDead(state) && reason ? `${words} · ${reason}` : words
}

export function statusTone(state: TerminalState): StatusTone {
  if (state === 'connected') return 'ok'
  return state === 'disconnected' || state === 'error' ? 'no' : ''
}

/** Reconnect is offered once the socket is gone. */
export const isDead = (state: TerminalState): boolean => state === 'disconnected' || state === 'error'

/** True while a socket is opening or open: a second Reconnect then must not start another. */
export const isLive = (readyState: number): boolean => readyState === SOCKET_CONNECTING || readyState === SOCKET_OPEN

/** The observed box, rounded to whole pixels. */
export const roundBox = (box: Box): Box => ({ width: Math.round(box.width), height: Math.round(box.height) })

/** Fit again only when the box really changed: fitting itself nudges the layout, which would fire the observer again without end. */
export const shouldRefit = (last: Box, next: Box): boolean => last.width !== next.width || last.height !== next.height

function isFields(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/** The parent's answer to the ticket request, or undefined when it is not `{ticket, expires_in}` with a non-empty ticket and a positive whole number of seconds. */
export function parseTicket(body: unknown): Ticket | undefined {
  if (!isFields(body)) return undefined
  const { ticket, expires_in: expiresIn } = body
  if (typeof ticket !== 'string' || ticket === '') return undefined
  if (typeof expiresIn !== 'number' || !Number.isInteger(expiresIn) || expiresIn <= 0) return undefined
  return { ticket, expiresIn }
}

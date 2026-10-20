// Pure helpers for the screen viewer: where a pointer is on the picture, and which Mac key a browser key is.
import type { ScreenInput } from './types.ts'

/** The Agent reads positions in ten-thousandths of the screen's width and height. */
export const POSITION_SCALE = 10_000
/** The most events sent in one call (the Agent refuses more). */
export const MAX_EVENTS = 64
/** The Agent reads scroll steps from -50 to 50. */
const MAX_SCROLL = 50
const WHEEL_PIXELS_PER_STEP = 40

/** macOS virtual key codes, by the browser's `KeyboardEvent.code` (a position on the keyboard, not a letter). */
const MAC_KEYS: Record<string, number> = {
  KeyA: 0, KeyS: 1, KeyD: 2, KeyF: 3, KeyH: 4, KeyG: 5, KeyZ: 6, KeyX: 7, KeyC: 8, KeyV: 9, KeyB: 11, KeyQ: 12, KeyW: 13, KeyE: 14, KeyR: 15, KeyY: 16, KeyT: 17,
  Digit1: 18, Digit2: 19, Digit3: 20, Digit4: 21, Digit6: 22, Digit5: 23, Equal: 24, Digit9: 25, Digit7: 26, Minus: 27, Digit8: 28, Digit0: 29, BracketRight: 30,
  KeyO: 31, KeyU: 32, BracketLeft: 33, KeyI: 34, KeyP: 35, Enter: 36, KeyL: 37, KeyJ: 38, Quote: 39, KeyK: 40, Semicolon: 41, Backslash: 42, Comma: 43, Slash: 44,
  KeyN: 45, KeyM: 46, Period: 47, Tab: 48, Space: 49, Backquote: 50, Backspace: 51, Escape: 53, MetaRight: 54, MetaLeft: 55, ShiftLeft: 56, CapsLock: 57, AltLeft: 58,
  ControlLeft: 59, ShiftRight: 60, AltRight: 61, ControlRight: 62, F5: 96, F6: 97, F7: 98, F3: 99, F8: 100, F9: 101, F11: 103, F10: 109, F12: 111, Home: 115,
  PageUp: 116, Delete: 117, F4: 118, End: 119, F2: 120, PageDown: 121, F1: 122, ArrowLeft: 123, ArrowRight: 124, ArrowDown: 125, ArrowUp: 126,
}

export function macKeyCode(code: string): number | null {
  return MAC_KEYS[code] ?? null
}

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value))

/** A pointer position inside the picture's box, as the Agent's ten-thousandths. Outside the box it sticks to the edge. */
export function pointerPosition(clientX: number, clientY: number, box: { left: number; top: number; width: number; height: number }): { x: number; y: number } {
  if (box.width <= 0 || box.height <= 0) return { x: 0, y: 0 }
  const x = clamp((clientX - box.left) / box.width, 0, 1)
  const y = clamp((clientY - box.top) / box.height, 0, 1)
  return { x: Math.round(x * POSITION_SCALE), y: Math.round(y * POSITION_SCALE) }
}

/** The browser's wheel movement as scroll steps (the browser's down is positive, the Mac's line scroll down is negative). */
export function scrollSteps(deltaX: number, deltaY: number): { dx: number; dy: number } {
  const steps = (pixels: number) => clamp(Math.round(-pixels / WHEEL_PIXELS_PER_STEP), -MAX_SCROLL, MAX_SCROLL) || 0
  return { dx: steps(deltaX), dy: steps(deltaY) }
}

export function buttonName(button: number): 'left' | 'middle' | 'right' {
  if (button === 1) return 'middle'
  return button === 2 ? 'right' : 'left'
}

/** Keeps only the last pointer move of a batch (older moves add nothing) and cuts the batch to what one call may carry. */
export function batch(events: ScreenInput[]): ScreenInput[] {
  const lastMove = events.map((event) => event.type).lastIndexOf('move')
  const kept = events.filter((event, index) => event.type !== 'move' || index === lastMove)
  return kept.slice(0, MAX_EVENTS)
}

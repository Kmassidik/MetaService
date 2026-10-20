/** Moving between the pictures of one message in the full-screen viewer. Stops at the ends. */

/** A horizontal swipe shorter than this is a tap or a wobble, not a page turn. */
export const SWIPE_MIN_PX = 48

const KEY_STEPS: Readonly<Record<string, number>> = Object.freeze({ ArrowLeft: -1, ArrowRight: 1 })

export function clampIndex(index: number, count: number): number {
  if (count <= 0) return 0
  return Math.min(Math.max(index, 0), count - 1)
}

export function stepIndex(index: number, delta: number, count: number): number {
  return clampIndex(index + delta, count)
}

/** -1 (previous), 1 (next) or 0 for a key press. */
export function keyStep(key: string): number {
  return KEY_STEPS[key] ?? 0
}

/** A swipe left shows the next picture, right the previous; mostly-vertical drags do nothing. */
export function swipeStep(dx: number, dy: number): number {
  if (Math.abs(dx) < SWIPE_MIN_PX || Math.abs(dx) <= Math.abs(dy)) return 0
  return dx < 0 ? 1 : -1
}

export function counterLabel(index: number, count: number): string {
  return `${index + 1} of ${count}`
}

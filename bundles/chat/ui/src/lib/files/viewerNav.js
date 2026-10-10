/** Moving between the pictures of one message in the full-screen viewer. Stops at the ends. */

/** A horizontal swipe shorter than this is a tap or a wobble, not a page turn. */
export const SWIPE_MIN_PX = 48

const KEY_STEPS = Object.freeze({ ArrowLeft: -1, ArrowRight: 1 })

export function clampIndex(index, count) {
  if (count <= 0) return 0
  return Math.min(Math.max(index, 0), count - 1)
}

export function stepIndex(index, delta, count) {
  return clampIndex(index + delta, count)
}

/** -1 (previous), 1 (next) or 0 for a key press. */
export function keyStep(key) {
  return KEY_STEPS[key] ?? 0
}

/** A swipe left shows the next picture, right the previous; mostly-vertical drags do nothing. */
export function swipeStep(dx, dy) {
  if (Math.abs(dx) < SWIPE_MIN_PX || Math.abs(dx) <= Math.abs(dy)) return 0
  return dx < 0 ? 1 : -1
}

export function counterLabel(index, count) {
  return `${index + 1} of ${count}`
}

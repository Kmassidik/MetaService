// The numbers of the progress ring (a circle drawn with a dashed stroke). Pure.
export const RING_SIZE = 92
export const RING_RADIUS = 38
export const RING_STROKE = 9

/** How much of the circle is filled for `done` of `total`, and the length of the whole circle. Never more than the circle, and an empty ring has none. */
export function ringArc(done: number, total: number): { filled: number; circle: number } {
  const circle = 2 * Math.PI * RING_RADIUS
  const share = total > 0 ? Math.min(1, done / total) : 0
  return { filled: circle * share, circle }
}

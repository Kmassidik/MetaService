// Turns probe points into the drawing of a small sparkline: one polyline per run of answered probes (a failed probe breaks the run) and an x position
// for each failed probe, drawn as a tick. Pure: no DOM, so it is easy to test.
import type { LatencyPoint } from './latencyParse.ts'

export const SPARK_WIDTH = 120
export const SPARK_HEIGHT = 28
const SPARK_PADDING = 2
/** The highest value on the scale is at least this, so a machine that is always near 0 ms still draws a flat line at the bottom. */
const MIN_SCALE_MS = 1

export interface Spark {
  /** One "x,y x,y ..." list per run of answered probes, ready for a polyline's points. */
  lines: string[]
  /** The x position of each failed probe. */
  failedX: number[]
}

/** The horizontal position of the probe at `index` of `total`, spread across the width. */
function xOf(index: number, total: number): number {
  if (total <= 1) return SPARK_WIDTH / 2
  return (index / (total - 1)) * SPARK_WIDTH
}

/** The vertical position of a value, where the highest value sits at the top padding and zero at the bottom. */
function yOf(ms: number, top: number): number {
  const usable = SPARK_HEIGHT - SPARK_PADDING * 2
  return SPARK_HEIGHT - SPARK_PADDING - (ms / top) * usable
}

/** The lines and failure ticks of one sparkline. */
export function sparkline(points: LatencyPoint[]): Spark {
  const top = Math.max(MIN_SCALE_MS, ...points.map((point) => point.ms ?? 0))
  const runs: string[][] = []
  const failedX: number[] = []
  let run: string[] = []
  points.forEach((point, index) => {
    const x = xOf(index, points.length)
    if (point.ms === null) {
      failedX.push(x)
      if (run.length > 0) runs.push(run)
      run = []
      return
    }
    run.push(`${x.toFixed(1)},${yOf(point.ms, top).toFixed(1)}`)
  })
  if (run.length > 0) runs.push(run)
  return { lines: runs.map((finished) => finished.join(' ')), failedX }
}

// What a panel of the Network tab shows: loading, could not load, no readings yet, the chart, or the chart with the last numbers kept after a failed update. Pure.

export type PanelStatus = 'loading' | 'failed' | 'empty' | 'stale' | 'ready'

/** `count` is how many readings the panel has, or null when nothing has been read yet. */
export function panelStatusOf(count: number | null, failed: boolean): PanelStatus {
  if (count === null) return failed ? 'failed' : 'loading'
  if (count === 0) return failed ? 'failed' : 'empty'
  return failed ? 'stale' : 'ready'
}

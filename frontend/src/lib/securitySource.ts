// Chooses where the Security page gets its data. The real parent is the default; the sample data is loaded (as a separate chunk) only when the address asks for
// the preview. The real data path (securityApi.ts) never imports the sample.
import { realSource, type SecuritySource } from './securityApi.ts'
import type { MachineInfo } from './securityView.ts'

export interface LoadedSource {
  source: SecuritySource
  /** The sample's own machines in preview; null for the real page, which lists the machines the panel knows. */
  machines: MachineInfo[] | null
}

export async function loadSource(preview: boolean, now: number): Promise<LoadedSource> {
  if (!preview) return { source: realSource, machines: null }
  const { mockPreview } = await import('./securityMockSource.ts')
  const sample = mockPreview(now)
  return { source: sample.source, machines: sample.machines.map(({ id, name, state, os }) => ({ id, name, state, os })) }
}

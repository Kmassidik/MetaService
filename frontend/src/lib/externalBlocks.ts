// What the Building draws for the services that were on the machine before MetaService: one block each, running ones first. Pure, no DOM.
import type { LogoName } from './logos.ts'
import type { ExternalRuntime, ExternalService, ExternalServiceState } from './types.ts'

export type BlockTone = 'run' | 'stop' | 'unknown'

export interface ExternalBlock {
  id: string
  name: string
  tone: BlockTone
  /** What the machine said: running, stopped or unknown. */
  state: ExternalServiceState
  /** "container" or "vm". */
  kind: ExternalService['kind']
  /** The image it was made from, when the machine says. */
  image: string | null
  /** The runtime in one word: "docker", "incus", "apple". */
  tag: string
  /** The runtime's logo, for the runtimes that have one bundled. */
  logo: LogoName | null
  /** The hover and screen-reader text: the whole sentence about the block. */
  title: string
}

/** Only Docker has a logo bundled; the others show their name. */
const RUNTIME_LOGOS: Partial<Record<ExternalRuntime, LogoName>> = { docker: 'docker' }
const TONES: Record<ExternalServiceState, BlockTone> = { running: 'run', stopped: 'stop', unknown: 'unknown' }
const TONE_ORDER: Record<BlockTone, number> = { run: 0, unknown: 1, stop: 2 }

function blockOf(service: ExternalService): ExternalBlock {
  return {
    id: service.id,
    name: service.name,
    tone: TONES[service.state],
    state: service.state,
    kind: service.kind,
    image: service.image,
    tag: service.runtime,
    logo: RUNTIME_LOGOS[service.runtime] ?? null,
    title: `${service.name}: external ${service.runtime} ${service.kind}, ${service.state}. Click for details.`,
  }
}

/** Running first, then the ones the machine could not read, then stopped; each group by name. */
export function externalBlocks(services: readonly ExternalService[]): ExternalBlock[] {
  return services.map(blockOf).sort((a, b) => TONE_ORDER[a.tone] - TONE_ORDER[b.tone] || a.name.localeCompare(b.name))
}

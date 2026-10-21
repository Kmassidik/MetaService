// The owl pictures and how big each is drawn. One name per place the panel shows an owl.
import emptyMachines from '../assets/owl/owl-empty-machines.webp'
import emptyVms from '../assets/owl/owl-empty-vms.webp'
import notFound from '../assets/owl/owl-404.webp'
import offline from '../assets/owl/owl-offline.webp'
import busy from '../assets/owl/owl-busy.webp'
import done from '../assets/owl/owl-done.webp'
import loading from '../assets/owl/owl-loading.webp'
import hero from '../assets/owl/owl-hero.webp'

export type OwlName = 'hero' | 'emptyMachines' | 'emptyVms' | 'offline' | 'busy' | 'done' | 'notFound' | 'loading'

export interface Owl {
  src: string
  /** The width and height it is drawn at, in px. */
  size: number
}

const HERO_PX = 200
const EMPTY_PX = 160
const OFFLINE_PX = 104
const DONE_PX = 120
const LOADING_PX = 80
const BUSY_PX = 56

const OWLS: Record<OwlName, Owl> = {
  hero: { src: hero, size: HERO_PX },
  emptyMachines: { src: emptyMachines, size: EMPTY_PX },
  emptyVms: { src: emptyVms, size: EMPTY_PX },
  offline: { src: offline, size: OFFLINE_PX },
  busy: { src: busy, size: BUSY_PX },
  done: { src: done, size: DONE_PX },
  notFound: { src: notFound, size: EMPTY_PX },
  loading: { src: loading, size: LOADING_PX },
}

export const OWL_NAMES: OwlName[] = ['hero', 'emptyMachines', 'emptyVms', 'offline', 'busy', 'done', 'notFound', 'loading']

export function owlFor(name: OwlName): Owl {
  return OWLS[name]
}

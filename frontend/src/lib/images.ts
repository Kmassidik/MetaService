// The Image choice of the Create VM window: the parent's answer for one machine (GET /api/machines/{id}/images) checked before the page trusts it, the options the select shows, and what is sent.
// Pure functions, no DOM, no network. The page only ever sends a catalog id; it never types or sends an image name.
import { UnreadableAnswer } from './machineDetail.ts'

export const STOCK_IMAGE = 'blank'
export const STOCK_TITLE = 'Ubuntu Server 24.04 LTS'
export const STOCK_DESCRIPTION = 'Plain Ubuntu with the usual server tools. Nothing else.'

export type ImageState = 'ready' | 'planned'
export type ImageHelper = 'answered' | 'old_helper' | 'unreachable'

const STATES: readonly ImageState[] = ['ready', 'planned']
const HELPERS: readonly ImageHelper[] = ['answered', 'old_helper', 'unreachable']

export interface MachineImage {
  id: string
  title: string
  description: string
  state: ImageState
  /** Prepared on this machine. */
  ready: boolean
  /** Can be picked now. */
  available: boolean
  /** Why it cannot be picked (or has to be prepared first); null when there is nothing to say. */
  reason: string | null
}

export interface MachineImages {
  helper: ImageHelper
  images: MachineImage[]
}

/** One image of the catalog, ready for the dropdown rows. */
export interface ImageOption {
  id: string
  title: string
  disabled: boolean
  /** True while the image is only planned (not built yet), as opposed to waiting to be prepared on this machine. */
  planned: boolean
  /** What the image is, shown under its row while it can be picked. */
  description: string
  reason: string | null
}

type Rec = Record<string, unknown>

const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)

function oneOf<T extends string>(allowed: readonly T[], value: unknown, what: string): T {
  const found = allowed.find((item) => item === value)
  if (found === undefined) throw new UnreadableAnswer(`${what} is not one of the promised words`)
  return found
}

function text(source: Rec, key: string): string {
  const value = source[key]
  if (typeof value === 'string' && value !== '') return value
  throw new UnreadableAnswer(`${key} is not text`)
}

function flag(source: Rec, key: string): boolean {
  const value = source[key]
  if (typeof value === 'boolean') return value
  throw new UnreadableAnswer(`${key} is not true or false`)
}

function reasonOf(source: Rec): string | null {
  const value = source.reason
  if (value === null || typeof value === 'string') return value
  throw new UnreadableAnswer('reason is not text')
}

function image(value: unknown): MachineImage {
  if (!isRec(value)) throw new UnreadableAnswer('an image is not an object')
  const state = oneOf(STATES, value.state, 'state')
  const available = flag(value, 'available')
  if (available && state !== 'ready') throw new UnreadableAnswer('an image that is only planned cannot be available')
  return { id: text(value, 'id'), title: text(value, 'title'), description: text(value, 'description'), state, ready: flag(value, 'ready'), available, reason: reasonOf(value) }
}

/** Reads the parent's answer. Anything that is not the promised shape throws UnreadableAnswer. */
export function parseMachineImages(raw: unknown): MachineImages {
  if (!isRec(raw)) throw new UnreadableAnswer('the images answer is not an object')
  if (!Array.isArray(raw.images)) throw new UnreadableAnswer('images is not a list')
  const images = raw.images.map(image)
  if (new Set(images.map((entry) => entry.id)).size !== images.length) throw new UnreadableAnswer('an image is listed twice')
  return { helper: oneOf(HELPERS, raw.helper, 'helper'), images }
}

const STOCK_OPTION: ImageOption = { id: STOCK_IMAGE, title: STOCK_TITLE, disabled: false, planned: false, description: STOCK_DESCRIPTION, reason: null }

const option = (entry: MachineImage): ImageOption => ({
  id: entry.id,
  title: entry.title,
  disabled: !entry.available,
  planned: entry.state === 'planned',
  description: entry.description,
  reason: entry.reason,
})

/** What the dropdowns are made from. Before the answer arrives, or when it cannot be read, only the stock image (it works on every machine). */
export const imageOptions = (answer: MachineImages | null): ImageOption[] => (answer === null ? [STOCK_OPTION] : answer.images.map(option))

/** The image to keep after the list changed (another machine, a new answer): the current one when it can still be picked, else the stock image. */
export function imageAfterChange(options: ImageOption[], current: string): string {
  return options.some((entry) => entry.id === current && !entry.disabled) ? current : STOCK_IMAGE
}

/** The `bundle` for the create request: left out for the stock image, so the request is exactly what it was before images existed. */
export const imageBundle = (chosen: string | undefined): string | undefined => (chosen === undefined || chosen === '' || chosen === STOCK_IMAGE ? undefined : chosen)

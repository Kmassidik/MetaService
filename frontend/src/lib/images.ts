// The Image choice of the Create VM window: the parent's answer for one machine (GET /api/machines/{id}/images) checked before the page trusts it, the options the select shows, and what is sent.
// Pure functions, no DOM, no network. The page only ever sends a catalog id; it never types or sends an image name.
import { UnreadableAnswer } from './machineDetail.ts'

export const STOCK_IMAGE = 'blank'
const STOCK_TITLE = 'Blank (plain Ubuntu)'
const STOCK_DESCRIPTION = 'Ubuntu 24.04 with the usual server tools. Nothing else.'
const NOT_YET = 'not available yet'

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

/** One line of the select. */
export interface ImageOption {
  id: string
  title: string
  /** What the select shows: the title, and "(not available yet)" when it cannot be picked. */
  label: string
  disabled: boolean
  /** Shown under the select while this one is picked. */
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

const STOCK_OPTION: ImageOption = { id: STOCK_IMAGE, title: STOCK_TITLE, label: STOCK_TITLE, disabled: false, description: STOCK_DESCRIPTION, reason: null }

const option = (entry: MachineImage): ImageOption => ({
  id: entry.id,
  title: entry.title,
  label: entry.available ? entry.title : `${entry.title} (${NOT_YET})`,
  disabled: !entry.available,
  description: entry.description,
  reason: entry.reason,
})

/** What the select lists. Before the answer arrives, or when it cannot be read, only Blank (it works on every machine). */
export const imageOptions = (answer: MachineImages | null): ImageOption[] => (answer === null ? [STOCK_OPTION] : answer.images.map(option))

/** One line for each image that cannot be picked: its name and why. */
export function imageNotes(options: ImageOption[]): string[] {
  return options.filter((entry) => entry.disabled && entry.reason !== null).map((entry) => `${entry.title} - ${entry.reason}`)
}

/** The image to keep after the list changed (another machine, a new answer): the current one when it can still be picked, else Blank. */
export function imageAfterChange(options: ImageOption[], current: string): string {
  return options.some((entry) => entry.id === current && !entry.disabled) ? current : STOCK_IMAGE
}

/** The `bundle` for the create request: left out for Blank, so the request is exactly what it was before images existed. */
export const imageBundle = (chosen: string | undefined): string | undefined => (chosen === undefined || chosen === '' || chosen === STOCK_IMAGE ? undefined : chosen)

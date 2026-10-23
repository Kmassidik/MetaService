// The words of the Create VM window's selects: what each line of the size and runtime selects says, the runtime dropdown's rows, the one-line explanation under it, and the letter of a row's badge.
// Pure functions, no DOM, no network. The facts (what fits, what is allowed) come from vmSize.ts and createVm.ts; this only writes them out.
import { CONTAINER_DESCRIPTION, VM_DESCRIPTION, type RuntimeCard } from './createVm.ts'
import type { RichCard } from './imageChoices.ts'
import { MAC_OS } from './gpuChoice.ts'
import { MEDIUM_SIZE, SIZE_PRESETS, type SizeCard } from './vmSize.ts'

/** One line of a native select. */
export interface SelectOption {
  value: string
  label: string
  disabled: boolean
}

const RECOMMENDED = ' (Recommended)'
const CUSTOM_LINE = 'Custom — Configure specs manually...'
const MAC_CAPTION = "On a Mac both run inside Apple's own small VM."

/** " (reason)", or nothing. */
const inBrackets = (reason: string | null): string => (reason === null ? '' : ` (${reason})`)

/** "Medium — 2 vCPU · 4GB RAM · 40GB Disk (Recommended)"; a size that does not fit has its reason in brackets after it. */
function sizeLine(card: SizeCard): string {
  const preset = SIZE_PRESETS.find((entry) => entry.key === card.key)
  if (!preset) return CUSTOM_LINE
  const recommended = preset.key === MEDIUM_SIZE.key ? RECOMMENDED : ''
  return `${preset.label} — ${preset.cpu} vCPU · ${preset.ramGb}GB RAM · ${preset.diskGb}GB Disk${recommended}${inBrackets(card.reason)}`
}

export const sizeOptions = (cards: SizeCard[]): SelectOption[] => cards.map((card) => ({ value: card.key, label: sizeLine(card), disabled: card.disabled }))

/** The rows of the runtime dropdown: each kind with what it is; the one the machine cannot run says why instead, greyed out. */
export const runtimeRows = (cards: RuntimeCard[]): RichCard[] =>
  cards.map((card) => ({ id: card.kind, title: card.label, caption: card.reason ?? card.description, disabled: card.disabled, tag: card.disabled ? null : card.tag, glyph: card.kind === 'vm' ? 'vm' : 'container' }))

/** The short plain line under the runtime select: what the chosen kind is, and on a Mac that both run in Apple's own small VM. */
export function runtimeCaption(kind: string, os: string | undefined): string {
  const what = kind === 'vm' ? VM_DESCRIPTION : CONTAINER_DESCRIPTION
  return os === MAC_OS ? `${what} ${MAC_CAPTION}` : what
}

/** What a row's square shows: its logo when it has one, else the first letter of its name. */
export type BadgeFace = { kind: 'logo'; src: string } | { kind: 'letter'; text: string }

export const badgeFace = (title: string, logo: string | undefined): BadgeFace => (logo ? { kind: 'logo', src: logo } : { kind: 'letter', text: title.charAt(0).toUpperCase() })

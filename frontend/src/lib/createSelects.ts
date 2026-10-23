// The words of the Create VM window's selects: what each line of the size and runtime selects says, the one-line explanation under the runtime select, and the letter of an image's badge.
// Pure functions, no DOM, no network. The facts (what fits, what is allowed) come from vmSize.ts and createVm.ts; this only writes them out.
import type { RuntimeCard } from './createVm.ts'
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
const CONTAINER_CAPTION = "Shares the machine's core: starts in seconds, uses little memory."
const VM_CAPTION = 'A whole separate computer with its own core: stronger wall, slower start.'
const MAC_CAPTION = "On a Mac both run inside Apple's own small VM."

/** " (reason)", or nothing; `lowerFirst` makes "This machine runs…" read as part of a line. */
function inBrackets(reason: string | null, lowerFirst: boolean): string {
  if (reason === null) return ''
  return ` (${lowerFirst ? reason.charAt(0).toLowerCase() + reason.slice(1) : reason})`
}

/** "Medium — 2 vCPU · 4GB RAM · 40GB Disk (Recommended)"; a size that does not fit has its reason in brackets after it. */
function sizeLine(card: SizeCard): string {
  const preset = SIZE_PRESETS.find((entry) => entry.key === card.key)
  if (!preset) return CUSTOM_LINE
  const recommended = preset.key === MEDIUM_SIZE.key ? RECOMMENDED : ''
  return `${preset.label} — ${preset.cpu} vCPU · ${preset.ramGb}GB RAM · ${preset.diskGb}GB Disk${recommended}${inBrackets(card.reason, false)}`
}

export const sizeOptions = (cards: SizeCard[]): SelectOption[] => cards.map((card) => ({ value: card.key, label: sizeLine(card), disabled: card.disabled }))

/** "Container — fast stop & wake"; the one the machine cannot run says why in brackets. */
export const runtimeOptions = (cards: RuntimeCard[]): SelectOption[] =>
  cards.map((card) => ({ value: card.kind, label: `${card.label} — ${card.caption}${inBrackets(card.reason, true)}`, disabled: card.disabled }))

/** The short plain line under the runtime select: what the chosen kind is, and on a Mac that both run in Apple's own small VM. */
export function runtimeCaption(kind: string, os: string | undefined): string {
  const what = kind === 'vm' ? VM_CAPTION : CONTAINER_CAPTION
  return os === MAC_OS ? `${what} ${MAC_CAPTION}` : what
}

/** What an image's square shows: its logo when it has one, else the first letter of its name. */
export type BadgeFace = { kind: 'logo'; src: string } | { kind: 'letter'; text: string }

export const badgeFace = (title: string, logo: string | undefined): BadgeFace => (logo ? { kind: 'logo', src: logo } : { kind: 'letter', text: title.charAt(0).toUpperCase() })

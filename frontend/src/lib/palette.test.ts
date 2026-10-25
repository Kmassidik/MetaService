// The panel's palette must meet WCAG AA for every pair it draws. If a pair fails, change the token in src/palette.css, never this list.
import { test, expect } from 'bun:test'
import { readFileSync } from 'node:fs'
import { AA_LARGE_TEXT_AND_MARKS, AA_TEXT, contrastRatio } from './contrast.ts'
import { readTokens, resolveTokens, type Tokens } from './paletteTokens.ts'


const css = readFileSync(new URL('../palette.css', import.meta.url), 'utf8')
const tokens = resolveTokens(readTokens(css))

/** One thing the panel draws: a token as the colour of something, on a token as the background of it. */
type Pair = readonly [foreground: string, background: string, minimum: number, what: string]

const NEON = ['#00f56d', '#00c24e', '#9ee8bd', '#053', '#043', '0,245,109']
const FLOORS = ['--page-bg', '--surface', '--surface-2'] as const
const MUTED = ['--m40', '--m50', '--m60', '--m70'] as const

const textOnFloors: Pair[] = FLOORS.map((floor) => ['--text', floor, AA_TEXT, `text on ${floor}`])
const mutedOnFloors: Pair[] = MUTED.flatMap((step) => FLOORS.map((floor): Pair => [step, floor, AA_TEXT, `${step} on ${floor}`]))

const CHART_COLOURS: readonly string[] = ['green', 'red', 'purple', 'orange', 'olive', 'ink', 'teal', 'blue', 'navy']
/** Two series colours closer than this (straight distance in red, green, blue) are too alike to tell apart on a chart. */
const MIN_COLOUR_DISTANCE = 60

const chartOnCards: Pair[] = CHART_COLOURS.flatMap((name): Pair[] => ['--surface', '--surface-2'].map((floor): Pair => [`--chart-${name}`, floor, AA_LARGE_TEXT_AND_MARKS, `chart colour ${name} on ${floor}`]))

const STORE_KINDS: readonly string[] = ['code', 'agent', 'toolchain', 'synced', 'git', 'media', 'documents', 'cache', 'vms', 'other']
const storeTiles: Pair[] = STORE_KINDS.flatMap((kind): Pair[] => [
  ['--text', `--store-${kind}`, AA_TEXT, `a name on a ${kind} tile of the Storage tab`],
  ['--m60', `--store-${kind}`, AA_TEXT, `a size on a ${kind} tile of the Storage tab`],
  [`--store-${kind}-mark`, '--surface', AA_LARGE_TEXT_AND_MARKS, `the ${kind} swatch of the Storage legend`],
])

const PAIRS: readonly Pair[] = [
  ...storeTiles,
  ['--text', '--store-hidden', AA_TEXT, 'the name on the hidden tile of the Storage tab'],
  ...chartOnCards,
  ...textOnFloors,
  ...mutedOnFloors,
  ['--text', '--accent', AA_TEXT, 'text on a moss fill (selected tab, apartment, step number)'],
  ['--accent-text', '--accent', AA_TEXT, 'text on the primary button'],
  ['--announce-text', '--announce-bg', AA_TEXT, 'announcement bar'],
  ['--inverse-text', '--inverse-bg', AA_TEXT, 'text on a dark block'],
  ['--inverse-text-soft', '--inverse-bg', AA_TEXT, 'soft text on a dark block'],
  ['--inverse-text-mid', '--inverse-bg', AA_TEXT, 'mid text on the machine roof'],
  ['--inverse-text-dim', '--inverse-2', AA_TEXT, 'dim label on the GPU floor'],
  ['--inverse-text-soft', '--inverse-bg', AA_TEXT, 'GPU floor text'],
  ['--accent', '--inverse-bg', AA_TEXT, 'GPU badge and the terminal status in the accent colour'],
  ['--ok', '--ok-bg', AA_TEXT, 'ok tag'],
  ['--ok', '--surface', AA_TEXT, 'ok text on a card'],
  ['--ok', '--surface-2', AA_TEXT, 'ok text on the grey fill'],
  ['--ok-note-text', '--ok-note-bg', AA_TEXT, 'ok note text'],
  ['--ok-note-title', '--ok-note-bg', AA_TEXT, 'ok note title'],
  ['--warn', '--warn-bg', AA_TEXT, 'warning tag and banner'],
  ['--warn', '--surface', AA_TEXT, 'warning text on a card'],
  ['--warn-note-title', '--warn-note-bg', AA_TEXT, 'warning note title'],
  ['--m70', '--warn-note-bg', AA_TEXT, 'warning note text'],
  ['--danger', '--surface', AA_TEXT, 'danger text on a card'],
  ['--danger', '--danger-bg', AA_TEXT, 'danger text on its tint'],
  ['--danger-bright', '--surface', AA_TEXT, 'hint that something is wrong'],
  ['--danger-ink', '--danger-bg', AA_TEXT, 'error box text'],
  ['--danger-note-text', '--danger-note-bg', AA_TEXT, 'failure note text'],
  ['--danger', '--danger-note-bg', AA_TEXT, 'failure tag'],
  ['--inverse-text', '--danger', AA_TEXT, 'text on the red Delete button'],
  ['--inverse-text', '--danger-d', AA_TEXT, 'text on the red Delete button when pointed at'],
  ['--off', '--surface', AA_TEXT, 'stopped tag'],
  ['--accent-text', '--accent', AA_TEXT, 'the highlighted word on the sign-in panel'],
  ['--focus', '--page-bg', AA_LARGE_TEXT_AND_MARKS, 'focus ring on the page'],
  ['--focus', '--surface', AA_LARGE_TEXT_AND_MARKS, 'focus ring on a card'],
  ['--focus', '--surface-2', AA_LARGE_TEXT_AND_MARKS, 'focus ring on the grey fill'],
  ['--accent-mark', '--page-bg', AA_LARGE_TEXT_AND_MARKS, 'focus ring and tab underline in the accent colour on the page'],
  ['--accent-mark', '--surface', AA_LARGE_TEXT_AND_MARKS, 'bar fill and focus ring in the accent colour on a card'],
  ['--accent-mark', '--surface-2', AA_LARGE_TEXT_AND_MARKS, 'bar fill on its track'],
  ['--accent-d', '--surface', AA_LARGE_TEXT_AND_MARKS, 'graph line on a card'],
  ['--warn-line', '--surface-2', AA_LARGE_TEXT_AND_MARKS, 'amber bar fill on its track'],
  ['--warn-line', '--surface', AA_LARGE_TEXT_AND_MARKS, 'amber outline on a card'],
  ['--line-strong', '--surface', AA_LARGE_TEXT_AND_MARKS, 'outline of a window or a selected choice'],
  ['--danger', '--surface-2', AA_LARGE_TEXT_AND_MARKS, 'red bar fill on its track'],
  ['--m50', '--surface', AA_TEXT, 'the label of the "Why it stopped" block'],
  ['--m70', '--surface', AA_TEXT, 'the "Why it stopped" text and its folded steps'],
  ['--text', '--surface', AA_TEXT, 'the terminal notice'],
  ['--m70', '--surface-2', AA_TEXT, 'the hint under the Image select'],
  ['--term-text', '--term-bg', AA_TEXT, 'terminal text'],
  ['--term-button-text', '--term-bar', AA_TEXT, 'terminal button'],
  ['--term-bad', '--term-bar', AA_TEXT, 'terminal status when it failed'],
]

function colourOf(tokens: Tokens, name: string): string {
  const value = tokens[name]
  if (value === undefined) throw new Error(`the token ${name} is not set`)
  return value
}

test('every text and mark pair meets WCAG AA', () => {
  const failures = PAIRS.flatMap(([foreground, background, minimum, what]) => {
    const ratio = contrastRatio(colourOf(tokens, foreground), colourOf(tokens, background))
    return ratio >= minimum ? [] : [`${what}: ${foreground} on ${background} is ${ratio.toFixed(2)}, needs ${minimum}`]
  })
  expect(failures).toEqual([])
})

test('the old neon green is gone', () => {
  const left = Object.entries(tokens).filter(([, value]) => NEON.some((neon) => value.includes(neon)))
  expect(left).toEqual([])
})

test('the muted steps get stronger from m40 to m70', () => {
  const ratios = MUTED.map((step) => contrastRatio(colourOf(tokens, step), colourOf(tokens, '--surface')))
  expect(ratios).toEqual([...ratios].sort((a, b) => a - b))
})

test('the accent is the owl moss green and the announcement bar uses it', () => {
  expect(tokens['--accent']).toBe('#7db26b')
  expect(tokens['--announce-bg']).toBe(tokens['--accent'])
})

test('the check can fail: a weak muted colour on the card colour is below AA', () => {
  expect(contrastRatio('#a09080', colourOf(tokens, '--surface'))).toBeLessThan(AA_TEXT)
})

test('every light surface is near white, so the owl pictures (multiplied onto them) show no box', () => {
  for (const floor of ['--page-bg', '--surface', '--surface-2']) expect(contrastRatio(colourOf(tokens, floor), '#ffffff')).toBeLessThan(1.1)
})

function channels(hex: string): [number, number, number] {
  const value = hex.replace('#', '')
  const channel = (at: number): number => Number.parseInt(value.slice(at, at + 2), 16)
  return [channel(0), channel(2), channel(4)]
}

test('every chart colour is a token, and no two chart colours are alike', () => {
  const colours = CHART_COLOURS.map((name) => ({ name, hex: colourOf(tokens, `--chart-${name}`) }))
  const alike = colours.flatMap(({ name: first, hex: a }, index) => colours.slice(index + 1).flatMap(({ name: second, hex: b }) => {
    const [ar, ag, ab] = channels(a)
    const [br, bg, bb] = channels(b)
    const distance = Math.hypot(ar - br, ag - bg, ab - bb)
    return distance >= MIN_COLOUR_DISTANCE ? [] : [`${first} and ${second} are ${distance.toFixed(0)} apart`]
  }))
  expect(alike).toEqual([])
})

test('the chart colours named in the code are the ones in the palette', () => {
  expect(Object.keys(tokens).filter((name) => name.startsWith('--chart-')).sort()).toEqual(CHART_COLOURS.map((name) => `--chart-${name}`).sort())
})

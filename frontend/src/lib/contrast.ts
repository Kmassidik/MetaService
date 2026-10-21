// WCAG contrast of two colours, so the colour sets of the panel can be checked by a test. Pure: no DOM, no files.

/** The smallest contrast of normal text (WCAG AA). */
export const AA_TEXT = 4.5
/** The smallest contrast of large text and of marks such as focus rings and bar fills (WCAG AA). */
export const AA_LARGE_TEXT_AND_MARKS = 3

const BYTE = 255
const HEX = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i
const FUNCTIONAL = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d*\.?\d+)\s*)?\)$/i
const LINEAR_KNEE = 0.03928
const LUMA = { red: 0.2126, green: 0.7152, blue: 0.0722 }
const FLARE = 0.05

export interface Rgba {
  r: number
  g: number
  b: number
  a: number
}

function fromHex(digits: string): Rgba {
  const full = digits.length === 3 ? [...digits].map((digit) => digit + digit).join('') : digits
  const value = Number.parseInt(full, 16)
  return { r: Math.floor(value / 65536) % 256, g: Math.floor(value / 256) % 256, b: value % 256, a: 1 }
}

/** Reads `#rgb`, `#rrggbb`, `rgb(r,g,b)` and `rgba(r,g,b,a)`. Anything else is an error, so a typo in a colour set is never skipped. */
export function parseColor(text: string): Rgba {
  const value = text.trim()
  const hex = HEX.exec(value)?.[1]
  if (hex !== undefined) return fromHex(hex)
  const parts = FUNCTIONAL.exec(value)
  if (parts === null) throw new Error(`"${text}" is not a colour it can read`)
  return { r: Number(parts[1]), g: Number(parts[2]), b: Number(parts[3]), a: parts[4] === undefined ? 1 : Number(parts[4]) }
}

/** What a see-through colour looks like on top of a solid one. */
function laidOver(top: Rgba, bottom: Rgba): Rgba {
  const mix = (above: number, below: number) => above * top.a + below * (1 - top.a)
  return { r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b), a: 1 }
}

function linear(channel: number): number {
  const share = channel / BYTE
  return share <= LINEAR_KNEE ? share / 12.92 : ((share + 0.055) / 1.055) ** 2.4
}

function luminance(color: Rgba): number {
  return LUMA.red * linear(color.r) + LUMA.green * linear(color.g) + LUMA.blue * linear(color.b)
}

/** The contrast ratio, 1 to 21. A see-through foreground is laid over the background first. */
export function contrastRatio(foreground: string, background: string): number {
  const base = parseColor(background)
  const light = luminance(laidOver(parseColor(foreground), base))
  const other = luminance(base)
  return (Math.max(light, other) + FLARE) / (Math.min(light, other) + FLARE)
}

export function meetsContrast(foreground: string, background: string, minimum: number): boolean {
  return contrastRatio(foreground, background) >= minimum
}

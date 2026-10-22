// The name the panel gives a VM when the person leaves the name empty: "vm-" and four lowercase hex characters, never one the machine already has.
// The random source is handed in so a test can fix it.

export const GENERATED_PREFIX = 'vm-'
/** Stands in for the name while the form is checked and the box is still empty (a real one is made when the order is sent). */
export const EXAMPLE_GENERATED_NAME = `${GENERATED_PREFIX}0000`
const HEX_DIGITS = '0123456789abcdef'
const FIRST_LENGTH = 4
/** After this many taken names of one length, one more character is added (the names of one length run out at 16 ** length). */
const TRIES_PER_LENGTH = 50

const hexOf = (random: () => number, length: number): string =>
  Array.from({ length }, () => HEX_DIGITS.charAt(Math.floor(random() * HEX_DIGITS.length) % HEX_DIGITS.length)).join('')

/** A free name: regenerated until it is not in `taken`. */
export function generateVmName(random: () => number, taken: ReadonlySet<string>): string {
  for (let length = FIRST_LENGTH; ; length++) {
    for (let attempt = 0; attempt < TRIES_PER_LENGTH; attempt++) {
      const name = `${GENERATED_PREFIX}${hexOf(random, length)}`
      if (!taken.has(name)) return name
    }
  }
}

/** The name to send: what was typed, or a generated one when the box is empty. */
export const nameToSend = (typed: string, random: () => number, taken: ReadonlySet<string>): string => (typed === '' ? generateVmName(random, taken) : typed)

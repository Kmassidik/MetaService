// The name of a machine's CPU ("AMD EPYC 7763 64-Core Processor", "Apple M4") as the panel shows it. The parent already cleans it; this is the same cleaning again,
// so a name that is odd for any reason is still safe and short on screen. The result is plain text: it is only ever put in as text, never as HTML.
import { HOST_MODEL } from './cpuOptions.ts'

export const MAX_CPU_MODEL_CHARS = 120
const LINE_BREAKS = /[\t\n\r]/g
const HIDDEN_CHARACTERS = /[\p{Cc}\p{Cf}]/gu
const BLANKS = /\s+/g

/** The name with control characters removed, runs of blanks made one and the rest cut to 120 characters; null when the machine gives none or nothing is left. */
export function cpuModelText(name: string | null | undefined): string | null {
  if (typeof name !== 'string') return null
  const tidy = name.replace(LINE_BREAKS, ' ').replace(HIDDEN_CHARACTERS, '').replace(BLANKS, ' ').trim()
  const cut = Array.from(tidy).slice(0, MAX_CPU_MODEL_CHARS).join('').trim()
  return cut === '' ? null : cut
}

/** What a CPU type row says. The host row names the machine's CPU when the machine gives one: "host (AMD Ryzen 9 5950X)"; every other model is as it is. */
export function cpuTypeLabel(model: string, hostName: string | null | undefined): string {
  const name = model === HOST_MODEL ? cpuModelText(hostName) : null
  return name === null ? model : `${model} (${name})`
}

// The security baseline in "Add a machine", seen before anything is installed: one row per check, the red line when no key is installed, and the hardening
// commands. The rows are the ones of the Security page (securityRules.ts); only the words for "not known" differ, because there is no helper yet. Pure functions.
import { baselineRows } from './securityRules.ts'
import type { BaselineRow } from './securityRules.ts'
import type { VerifySecurity } from './types.ts'

/** The helper is not installed yet, so "starts after reboot" is not asked. */
const NOT_ASKED = 'starts_after_reboot'
export const UNKNOWN_HERE = 'Could not be read from here.'
export const NO_KEY_LINE = 'No SSH key is installed for this user: do not turn off password login yet'
export const INSTALL_ANYWAY = 'You can install now and harden afterwards: the Security page keeps showing these rows.'
export const BASELINE_TITLE = 'Security baseline'
export const HARDEN_TITLE = 'Harden this machine (needs sudo, you run it)'
export const SAFETY_LINES: readonly string[] = [
  'Keep a second SSH window open while you do this.',
  'The change undoes itself after 5 minutes unless you confirm it.',
  'Nothing is run for you: you read the script and run it yourself.',
]
export const HARDEN_FOLDER = 'scripts/harden'

const SCRIPT_OF = { mac: 'harden-mac.sh', linux: 'harden-linux.sh' } as const

export interface HardenStep {
  /** What it does, in a few words. */
  label: string
  command: string
}

/** One row per check, in the Security page's order, without the check that needs the helper. An unknown check says so in this step's own words. */
export function verifyRows(security: VerifySecurity): BaselineRow[] {
  const rows = baselineRows({ ...security, starts_after_reboot: null })
  return rows.filter((row) => row.id !== NOT_ASKED).map((row) => (row.short === 'unknown' ? { ...row, line: UNKNOWN_HERE } : row))
}

export const warningTotal = (rows: BaselineRow[]): number => rows.filter((row) => row.state === 'warning').length

/** True only when the machine said there is no key: an unknown answer is not a fact to show in red. */
export const lacksKey = (security: VerifySecurity): boolean => security.has_key_login === false

/** The commands for the computer's system (a Mac, or anything else, which gets the Linux script), in the order they are run. */
export function hardenSteps(os: string): HardenStep[] {
  const script = os === 'Darwin' ? SCRIPT_OF.mac : SCRIPT_OF.linux
  return [
    { label: 'Look first (changes nothing)', command: `./${script} check` },
    { label: 'Apply it (after a key login worked from a second window)', command: `sudo ./${script} apply --confirm-key-login` },
    { label: 'Confirm within 5 minutes, or it undoes itself', command: `sudo ./${script} confirm` },
  ]
}

/** The line before the commands: where the scripts are and how they get to the machine. */
export const hardenIntro = `The scripts are in the ${HARDEN_FOLDER}/ folder of MetaService. Copy that folder to the machine, then run these there, in this order:`

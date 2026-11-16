// Removing a machine that joined through Share a PC. The panel can also clean the computer itself: it asks the machine's own helper, with the sudo password typed once, to stop its
// helper and WireGuard, remove its boot entries and delete its join folder. The order matters: the clean-up comes first, so a wrong password stops here with the machine still
// listed (nothing was changed, the person can try again); only after it worked is the machine taken out of the shared network and the list.
import { ApiError, machineLeave, removeMachine, shareRemovePeer } from './api.ts'
import { SHARED_PREFIX } from './networkTag.ts'

/** True for a machine that joined through Share a PC (its address is on the shared network). */
export const isSharedMachine = (machine: { ip?: string }): boolean => machine.ip?.startsWith(SHARED_PREFIX) === true

export interface SharedRemoval {
  /** The machine's id (the same word as the peer's name). */
  id: string
  /** Clean the computer too; false only forgets it here. */
  clean: boolean
  /** The computer's sudo password; read once and not kept. */
  sudoPassword: string
}

/** True when the clean-up may start: not asked for, or a password is there. */
export const cleanReady = (clean: boolean, password: string): boolean => !clean || password !== ''

const NOT_FOUND = 404

/** Anything that is already gone is not an error here: the point is that it is gone. */
async function ignoreGone(step: () => Promise<unknown>): Promise<void> {
  try {
    await step()
  } catch (failure) {
    if (!(failure instanceof ApiError) || failure.status !== NOT_FOUND) throw failure
  }
}

/** A helper built before the clean-up existed answers 404 (`old_helper`), and a computer that never joined through the script says `not_joined`: neither can clean itself. */
const CANNOT_CLEAN_CODES: ReadonlySet<string> = new Set(['old_helper', 'not_joined'])

export const isCannotClean = (failure: unknown): boolean => failure instanceof ApiError && CANNOT_CLEAN_CODES.has(failure.code)

/** What the person is told when the machine was removed but the computer itself could not be cleaned. */
export const notCleanedNote = (name: string): string =>
  `${name} was removed here, but its computer was not cleaned: its helper is too old to clean itself. Join again with the web command from Share a PC and answer y to "Leave that join first": that cleans the old join.`

export interface RemovalResult {
  /** True when the computer itself was cleaned. */
  cleaned: boolean
  /** What to tell the person when it was not (and they asked for it to be), else null. */
  note: string | null
}

/**
 * Cleans the computer when asked, then frees its address and removes the machine. A wrong password is thrown with nothing changed. A helper too old to clean itself is not a dead end:
 * the machine is removed anyway, and the result says the computer was not cleaned and how to finish.
 */
export async function removeSharedMachine(removal: SharedRemoval): Promise<RemovalResult> {
  let cleaned = removal.clean
  if (removal.clean) {
    try {
      await machineLeave(removal.id, removal.sudoPassword)
    } catch (failure) {
      if (!isCannotClean(failure)) throw failure
      cleaned = false
    }
  }
  await ignoreGone(() => shareRemovePeer(removal.id))
  await ignoreGone(() => removeMachine(removal.id))
  return { cleaned, note: removal.clean && !cleaned ? notCleanedNote(removal.id) : null }
}

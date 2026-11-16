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

/** Cleans the computer when asked (a refusal is thrown, nothing else was touched), then frees its address and removes the machine. */
export async function removeSharedMachine(removal: SharedRemoval): Promise<void> {
  if (removal.clean) await machineLeave(removal.id, removal.sudoPassword)
  await ignoreGone(() => shareRemovePeer(removal.id))
  await ignoreGone(() => removeMachine(removal.id))
}

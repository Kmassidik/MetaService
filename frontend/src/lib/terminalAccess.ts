// Who may open the web terminal of a VM, in one place, so every Terminal button agrees with the parent (which answers 409 not_supported / not_running, 502 unreachable).
import { RUNNING_STATE, STOPPED_STATE } from './vm.ts'
import type { Machine, Workload } from './types.ts'

/** Mac helpers older than the `terminal` capability already serve a console, so a Mac is allowed by its system. */
export const OLD_HELPER_CONSOLE_OS = 'macos'
const LINUX_OS = 'linux'
const VM_KIND = 'vm'

export type TerminalAccess = { allowed: true } | { allowed: false; text: string; title: string }

const UPDATE_HELPER: TerminalAccess = { allowed: false, text: 'Update the helper to use the terminal', title: 'Update the helper on this machine to use the terminal.' }
const CONTAINERS_ONLY: TerminalAccess = { allowed: false, text: 'Containers only for now', title: 'The terminal works in containers for now. A VM on a Linux machine has not been tried yet.' }
const OFFLINE: TerminalAccess = { allowed: false, text: 'Machine is offline', title: 'The machine is offline, so its VM cannot be reached.' }
const STOPPED: TerminalAccess = { allowed: false, text: 'VM is stopped', title: 'The terminal opens when the VM is running. Start the VM first.' }
const NOT_RUNNING: TerminalAccess = { allowed: false, text: 'VM is not running', title: 'The terminal opens when the VM is running.' }

type TerminalMachine = Pick<Machine, 'os' | 'state'> & { capabilities?: Pick<NonNullable<Machine['capabilities']>, 'terminal'> }

/** The machine says it serves a console, or it is a Mac with an older helper. */
export const machineHasConsole = (machine: TerminalMachine): boolean => machine.capabilities?.terminal === true || machine.os === OLD_HELPER_CONSOLE_OS

/** Whether the Terminal button of this VM works, and if not, why in plain words (the same checks the parent makes, in the same order). */
export function terminalAccess(machine: TerminalMachine, workload: Pick<Workload, 'state' | 'kind'>): TerminalAccess {
  if (!machineHasConsole(machine)) return UPDATE_HELPER
  if (machine.os === LINUX_OS && workload.kind === VM_KIND) return CONTAINERS_ONLY
  if (machine.state === 'offline') return OFFLINE
  if (workload.state === STOPPED_STATE) return STOPPED
  return workload.state === RUNNING_STATE ? { allowed: true } : NOT_RUNNING
}

/** The name in the terminal window's title. */
export const consoleTitle = (workload: Pick<Workload, 'id' | 'name'>): string => workload.name || workload.id

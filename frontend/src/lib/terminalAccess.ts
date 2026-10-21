// Who may open the web terminal of a VM, in one place, so every Terminal button agrees with the parent (which answers 409 not_supported / not_running, 502 unreachable).
import { RUNNING_STATE, STOPPED_STATE } from './vm.ts'
import type { Machine, Workload } from './types.ts'

/** The only system with a console for now (the macOS helper). */
export const CONSOLE_OS = 'macos'

export type TerminalAccess = { allowed: true } | { allowed: false; text: string; title: string }

const NOT_MAC: TerminalAccess = { allowed: false, text: 'Mac machines only for now', title: 'The console is only available on Mac machines for now.' }
const OFFLINE: TerminalAccess = { allowed: false, text: 'Machine is offline', title: 'The machine is offline, so its VM cannot be reached.' }
const STOPPED: TerminalAccess = { allowed: false, text: 'VM is stopped', title: 'The terminal opens when the VM is running. Start the VM first.' }
const NOT_RUNNING: TerminalAccess = { allowed: false, text: 'VM is not running', title: 'The terminal opens when the VM is running.' }

/** Whether the Terminal button of this VM works, and if not, why in plain words (the same checks the parent makes, in the same order). */
export function terminalAccess(machine: Pick<Machine, 'os' | 'state'>, workload: Pick<Workload, 'state'>): TerminalAccess {
  if (machine.os !== CONSOLE_OS) return NOT_MAC
  if (machine.state === 'offline') return OFFLINE
  if (workload.state === STOPPED_STATE) return STOPPED
  return workload.state === RUNNING_STATE ? { allowed: true } : NOT_RUNNING
}

/** The name in the terminal window's title. */
export const consoleTitle = (workload: Pick<Workload, 'id' | 'name'>): string => workload.name || workload.id

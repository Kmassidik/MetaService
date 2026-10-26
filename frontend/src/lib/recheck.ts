// "Check again" for a machine that is already added: what it starts from and which problems it can help with, as plain functions so they are easy to test.
// No DOM, no network.
import { emptyConnectForm } from './remote.ts'
import type { ConnectForm, Problem, RemoteMachineInfo } from './types.ts'

/**
 * The form of a re-check, from what the parent recorded when the machine was added: where it is, its SSH port and the user it logs in as.
 * The person only types the password, which is never prefilled or kept.
 */
export function recheckForm(info: RemoteMachineInfo): ConnectForm {
  return { ...emptyConnectForm(info.host), port: String(info.ssh_port), user: info.ssh_user, machineId: info.machine }
}

/**
 * Why this machine cannot be checked again, in plain words, or null when it can. A machine the parent did not add over SSH has no saved address and login,
 * so there is nothing to check it with; that is said instead of opening an empty check.
 */
export function recheckProblem(info: RemoteMachineInfo | null): string | null {
  if (info) return null
  return 'MetaService did not add this machine over SSH, so it has no saved address and login to check it with. Only a machine added from another computer can be checked again.'
}

/**
 * The helper problems the check itself covers: its own rows read the same things, and its "Install it for me" offers are the fixes it knows.
 * A code that is not here gets no action at all, never a button that does nothing. `bridge_blocked_by_firewall` is one of those: the firewall is
 * part of that computer's own setup, which the check does not read or change.
 */
const CHECKED_CODES: ReadonlySet<string> = new Set([
  /** Apple's container service is not answering: the VM-tool row, and a fresh look at that Mac. */
  'container_service_stopped',
  /** Apple's container tool is missing: the VM-tool row, with its own step to install it. */
  'container_tool_missing',
  /** Incus is missing or the login cannot use it: the VM-tool row, and the packages the check can install. */
  'incus_unreachable',
])

/** True when "Check again" is the useful action for this problem. */
export const problemHasCheck = (problem: Pick<Problem, 'code'>): boolean => CHECKED_CODES.has(problem.code)

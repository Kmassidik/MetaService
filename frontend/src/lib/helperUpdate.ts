// What the machine page says about the helper program on a machine and the "Update helper" button. Pure functions, no DOM, no network.
// Text that comes from the parent (a reason, a result sentence) is only ever returned as text.
import { isFields, optionalText, UnreadableAnswer } from './unreadable.ts'
import type { HelperUpdateInfo, HelperUpdateResult, Machine } from './types.ts'

const SHORT_BUILD_LENGTH = 8
const NOT_REPORTED = 'not reported'
const OFFLINE_NOTE = 'The machine is offline.'
const RESULT_NAMES: ReadonlyArray<HelperUpdateResult['result']> = ['updated', 'rolled_back', 'failed']

export const UPDATING_TEXT = 'Updating…'
export const UPDATE_EXPLANATION = 'Replaces the MetaService program on this computer with the newest one. Your VMs keep running.'
export const UPDATE_BUTTON = 'Update helper'

/** The first characters of a build, enough to tell two apart; "not reported" when the helper did not say. */
export const shortBuild = (build: string | null | undefined): string => (build ? build.slice(0, SHORT_BUILD_LENGTH) : NOT_REPORTED)

export type HelperStatus = 'up_to_date' | 'available' | 'unknown' | 'cannot'

export interface HelperView {
  build: string
  status: HelperStatus
  label: string
  canUpdate: boolean
  /** A plain line under the status: why there is no button, when there is not. */
  note: string | null
}

function statusOf(machine: Pick<Machine, 'agent_build' | 'update'>): { status: HelperStatus; label: string } {
  const update = machine.update
  if (!update) return { status: 'unknown', label: 'Unknown' }
  if (!update.available && update.reason) return { status: 'cannot', label: 'Cannot be updated from here' }
  if (!machine.agent_build) return { status: 'unknown', label: 'Unknown (old helper)' }
  return update.available ? { status: 'available', label: 'Update available' } : { status: 'up_to_date', label: 'Up to date' }
}

/** The Helper row of the Environment tab. The button works only when the parent has a different build for this machine and the machine answers. */
export function helperView(machine: Pick<Machine, 'agent_build' | 'update' | 'state'>): HelperView {
  const { status, label } = statusOf(machine)
  const online = machine.state !== 'offline'
  const offers = machine.update?.available === true
  return {
    build: shortBuild(machine.agent_build),
    status,
    label,
    canUpdate: offers && online,
    note: machine.update?.reason ?? (offers && !online ? OFFLINE_NOTE : null),
  }
}

/** The small tag on a machine card of the Machines list. */
export const listTag = (machine: Pick<Machine, 'update'>): string | null => (machine.update?.available ? 'Update available' : null)

/** The `update` part of a machine answer: nothing when the parent sent none, an UnreadableAnswer when it is not shaped right. */
export function parseHelperUpdate(data: unknown): HelperUpdateInfo | undefined {
  if (data === undefined) return undefined
  if (!isFields(data) || typeof data.available !== 'boolean') throw new UnreadableAnswer('update is not readable')
  return { available: data.available, current_build: optionalText(data, 'current_build'), newest_build: optionalText(data, 'newest_build'), reason: optionalText(data, 'reason') }
}

/** The answer of the update route. */
export function parseUpdateResult(data: unknown): HelperUpdateResult {
  if (!isFields(data) || typeof data.message !== 'string') throw new UnreadableAnswer('the update answer is not readable')
  const result = RESULT_NAMES.find((name) => name === data.result)
  if (!result) throw new UnreadableAnswer('the update answer has an unknown result')
  return { result, message: data.message }
}

export type Tone = 'ok' | 'warn' | 'bad'

export interface OutcomeView {
  tone: Tone
  title: string
  detail: string
}

const OUTCOMES: Record<HelperUpdateResult['result'], { tone: Tone; title: string }> = {
  updated: { tone: 'ok', title: 'Updated' },
  rolled_back: { tone: 'warn', title: 'Rolled back' },
  failed: { tone: 'bad', title: 'Update failed' },
}

export const outcomeView = (result: HelperUpdateResult): OutcomeView => ({ ...OUTCOMES[result.result], detail: result.message })

const REFUSALS: Record<string, { tone: Tone; title: string }> = {
  login_needed: { tone: 'warn', title: 'Login needed' },
  machine_busy: { tone: 'warn', title: 'Not now' },
  up_to_date: { tone: 'ok', title: 'Already up to date' },
}

/** A refusal of the update route (its error code and sentence) in the same shape as a result. */
export function failureView(code: string, message: string): OutcomeView {
  return { ...(REFUSALS[code] ?? { tone: 'bad', title: OUTCOMES.failed.title }), detail: message }
}

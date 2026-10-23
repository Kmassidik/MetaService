// The one-line summaries on the closed rows of the Environment tab: plain words about the current values, with every empty part left out.
import { parseLabels, type EnvForm } from './environmentForm.ts'
import { formatMb, osName } from './format.ts'
import type { HelperStatus } from './helperUpdate.ts'
import type { Machine } from './types.ts'

const SEPARATOR = ' · '
export const NO_LIMITS_SUMMARY = 'no limits set'
export const STANDARD_SIZES_SUMMARY = 'uses the standard sizes'
export const NO_NAMES_SUMMARY = 'no name set'
/** What the shared formatters write for a figure nobody reported. */
const NOT_REPORTED_DASH = '–'

const HELPER_SUMMARIES: Record<HelperStatus, string> = {
  up_to_date: 'helper up to date',
  available: 'helper update available',
  unknown: 'helper version not reported',
  cannot: 'helper version not reported',
}

const joined = (parts: ReadonlyArray<string | null>): string => parts.filter((part): part is string => part !== null && part !== '').join(SEPARATOR)

/** A field's text put into a phrase, or null when the field is empty. */
const phrase = (value: string, make: (text: string) => string): string | null => (value.trim() === '' ? null : make(value.trim()))

const reported = (text: string): string | null => (text === NOT_REPORTED_DASH ? null : text)

export function machineSummary(machine: Machine): string {
  const cores = machine.cpu_cores === null || machine.cpu_cores === undefined ? null : `${machine.cpu_cores} cores`
  return joined([machine.state, cores, reported(formatMb(machine.ram_total_mb)), reported(osName(machine.os))])
}

export const softwareSummary = (status: HelperStatus): string => HELPER_SUMMARIES[status]

export const ruvioSummary = (on: boolean, version: string | null | undefined): string => (on ? joined(['on', version ?? null]) : 'off')

export function limitsSummary(form: EnvForm): string {
  const sizes = [
    phrase(form.ramReserveMb, (text) => `keeps ${text} MB RAM free`),
    phrase(form.diskReserveGb, (text) => `keeps ${text} GB disk free`),
    phrase(form.ramAllowanceMb, (text) => `VMs up to ${text} MB RAM`),
    phrase(form.diskAllowanceGb, (text) => `VMs up to ${text} GB disk`),
    phrase(form.vmMaxRunning, (text) => `up to ${text} VMs`),
  ]
  // Offering the GPU is the standard, so on its own it is not a limit worth naming.
  const nothingSet = sizes.every((part) => part === null) && form.allowGpu
  return nothingSet ? NO_LIMITS_SUMMARY : joined([...sizes, form.allowGpu ? 'GPU offered' : 'GPU not offered'])
}

export function vmDefaultsSummary(form: EnvForm): string {
  const summary = joined([
    phrase(form.vmCpu, (text) => `${text} CPU`),
    phrase(form.vmRamMb, (text) => `${text} MB RAM`),
    phrase(form.vmDiskGb, (text) => `${text} GB disk`),
    phrase(form.vmImage, (text) => `image ${text}`),
  ])
  return summary === '' ? STANDARD_SIZES_SUMMARY : summary
}

export function namesSummary(form: EnvForm): string {
  const labels = parseLabels(form.labels).length
  const summary = joined([
    form.name.trim(),
    labels === 0 ? null : `${labels} ${labels === 1 ? 'label' : 'labels'}`,
    phrase(form.subdomain, (text) => `name on the internet ${text}`),
    phrase(form.sshJump, (text) => `ssh ${text}`),
  ])
  return summary === '' ? NO_NAMES_SUMMARY : summary
}

/** The save bar's words: how many sections hold changes that are not saved. */
export function unsavedText(sections: number): string {
  if (sections === 0) return 'No unsaved changes'
  return `Unsaved changes in ${sections} ${sections === 1 ? 'section' : 'sections'}`
}

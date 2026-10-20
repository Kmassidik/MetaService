// The Environment tab's form: what it starts with, whether each field is acceptable, and what to send on Save.
// The ranges and patterns are the parent's own (MachineSettings.swift in RootCore), so a refused value never leaves the page.
import { nameProblem } from './format.ts'
import type { Machine, MachineSettingsPatch } from './types.ts'

interface NumberRule {
  label: string
  min: number
  max: number
}

export const NUMBER_RULES = {
  ramReserveMb: { label: 'Memory kept free (MB)', min: 0, max: 10_000_000 },
  diskReserveGb: { label: 'Disk kept free (GB)', min: 0, max: 10_000_000 },
  ramAllowanceMb: { label: 'Most memory VMs may use (MB)', min: 512, max: 10_000_000 },
  diskAllowanceGb: { label: 'Most disk VMs may use (GB)', min: 1, max: 10_000_000 },
  vmMaxRunning: { label: 'Most VMs at once', min: 1, max: 1000 },
  vmCpu: { label: 'CPU', min: 1, max: 64 },
  vmRamMb: { label: 'Memory (MB)', min: 512, max: 1_048_576 },
  vmDiskGb: { label: 'Disk (GB)', min: 1, max: 100_000 },
} as const satisfies Record<string, NumberRule>

export type NumberField = keyof typeof NUMBER_RULES

interface TextRule {
  label: string
  pattern: RegExp
  max: number
  hint: string
}

export const TEXT_RULES = {
  vmImage: { label: 'Image', pattern: /^[a-z0-9][a-z0-9._:/-]{0,127}$/, max: 128, hint: 'lowercase letters, numbers and . _ : / -' },
  subdomain: { label: 'Name on the internet', pattern: /^[a-z0-9][a-z0-9-]{0,30}$/, max: 31, hint: 'lowercase letters, numbers and dashes' },
  aiModel: { label: 'AI model', pattern: /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$/, max: 100, hint: 'letters, numbers and . _ : / -' },
} as const satisfies Record<string, TextRule>

export type TextField = keyof typeof TEXT_RULES

export const MAX_LABELS = 8
export const MAX_NOTES = 300
const LABEL_PATTERN = /^[a-z0-9][a-z0-9-]{0,29}$/
const WHOLE_NUMBER = /^\d+$/
const LABEL_SEPARATOR = /[\s,]+/

export type FormField = 'name' | 'labels' | 'notes' | NumberField | TextField
export type FormErrors = Partial<Record<FormField, string>>

/** Every field as the person sees it: text. An empty number or text field means "not set". */
export interface EnvForm extends Record<NumberField, string>, Record<TextField, string> {
  name: string
  /** Labels separated by commas or spaces. */
  labels: string
  notes: string
  allowGpu: boolean
}

const NUMBER_FIELDS: NumberField[] = ['ramReserveMb', 'diskReserveGb', 'ramAllowanceMb', 'diskAllowanceGb', 'vmMaxRunning', 'vmCpu', 'vmRamMb', 'vmDiskGb']
const TEXT_FIELDS: TextField[] = ['vmImage', 'subdomain', 'aiModel']

const text = (value: number | string | null | undefined): string => (value === null || value === undefined ? '' : String(value))

export function formFromMachine(machine: Machine): EnvForm {
  const settings = machine.settings ?? {}
  return {
    name: machine.name,
    labels: (settings.labels ?? []).join(', '),
    notes: settings.notes ?? '',
    allowGpu: settings.allow_gpu ?? true,
    ramReserveMb: text(settings.ram_reserve_mb),
    diskReserveGb: text(settings.disk_reserve_gb),
    ramAllowanceMb: text(settings.ram_allowance_mb),
    diskAllowanceGb: text(settings.disk_allowance_gb),
    vmMaxRunning: text(settings.vm_max_running),
    vmCpu: text(settings.vm_cpu),
    vmRamMb: text(settings.vm_ram_mb),
    vmDiskGb: text(settings.vm_disk_gb),
    vmImage: text(settings.vm_image),
    subdomain: text(settings.subdomain),
    aiModel: text(settings.ai_model),
  }
}

export const sameForm = (a: EnvForm, b: EnvForm): boolean => JSON.stringify(a) === JSON.stringify(b)

export function parseLabels(value: string): string[] {
  return value.split(LABEL_SEPARATOR).filter((label) => label !== '')
}

/** A number field's value, or null when it is empty. Only call this on a value that passed `numberProblem`. */
export const readNumber = (value: string): number | null => (value.trim() === '' ? null : Number(value))

export function numberProblem(field: NumberField, value: string): string | null {
  const { label, min, max } = NUMBER_RULES[field]
  const trimmed = value.trim()
  if (trimmed === '') return null
  if (!WHOLE_NUMBER.test(trimmed)) return `${label} must be a whole number.`
  const number = Number(trimmed)
  return number >= min && number <= max ? null : `${label} must be between ${min} and ${max}.`
}

export function textProblem(field: TextField, value: string): string | null {
  const { label, pattern, max, hint } = TEXT_RULES[field]
  if (value === '') return null
  if (value.length > max) return `${label} must be at most ${max} characters.`
  return pattern.test(value) ? null : `${label}: use ${hint}.`
}

export function labelsProblem(value: string): string | null {
  const labels = parseLabels(value)
  if (labels.length > MAX_LABELS) return `Use at most ${MAX_LABELS} labels.`
  if (new Set(labels).size !== labels.length) return 'Labels must be different from each other.'
  const bad = labels.find((label) => !LABEL_PATTERN.test(label))
  return bad === undefined ? null : `Label "${bad}": use lowercase letters, numbers and dashes, at most 30 characters.`
}

export const notesProblem = (value: string): string | null => (value.length > MAX_NOTES ? `Use at most ${MAX_NOTES} characters.` : null)

/** The parent refuses a reserve that is not below the allowance; so does the form. Both numbers must be valid before they are compared. */
function reserveProblem(reserve: NumberField, allowance: NumberField, form: EnvForm, what: string): string | null {
  const kept = numberProblem(reserve, form[reserve]) === null ? readNumber(form[reserve]) : null
  const most = numberProblem(allowance, form[allowance]) === null ? readNumber(form[allowance]) : null
  const clash = kept !== null && most !== null && kept >= most
  return clash ? `The ${what} kept free must be smaller than the most VMs may use.` : null
}

function collect(entries: [FormField, string | null][]): FormErrors {
  const errors: FormErrors = {}
  for (const [field, problem] of entries) if (problem !== null) errors[field] = problem
  return errors
}

/** Every field that cannot be saved as it is, with the reason. Empty when the form is fine. */
export function formErrors(form: EnvForm): FormErrors {
  return collect([
    ['name', nameProblem(form.name)],
    ['labels', labelsProblem(form.labels)],
    ['notes', notesProblem(form.notes)],
    ...NUMBER_FIELDS.map((field): [FormField, string | null] => [field, numberProblem(field, form[field])]),
    ...TEXT_FIELDS.map((field): [FormField, string | null] => [field, textProblem(field, form[field])]),
    ['ramReserveMb', reserveProblem('ramReserveMb', 'ramAllowanceMb', form, 'memory')],
    ['diskReserveGb', reserveProblem('diskReserveGb', 'diskAllowanceGb', form, 'disk')],
  ])
}

const sameList = (a: readonly string[], b: readonly string[]): boolean => a.length === b.length && a.every((item, index) => item === b[index])

/**
 * What to send for a form that passed `formErrors`: only the fields that differ from the machine, so a change to one field cannot
 * overwrite another that someone else changed. An emptied field is sent as null, which clears it.
 */
export function patchFor(form: EnvForm, machine: Machine): MachineSettingsPatch {
  const was = machine.settings ?? {}
  const n = (field: NumberField) => readNumber(form[field])
  const textOrNull = (value: string): string | null => (value === '' ? null : value)
  const labels = parseLabels(form.labels)
  return {
    ...(form.name === machine.name ? {} : { name: form.name }),
    ...(sameList(labels, was.labels ?? []) ? {} : { labels }),
    ...(form.notes === (was.notes ?? '') ? {} : { notes: form.notes }),
    ...(form.allowGpu === (was.allow_gpu ?? true) ? {} : { allow_gpu: form.allowGpu }),
    ...(n('ramReserveMb') === (was.ram_reserve_mb ?? null) ? {} : { ram_reserve_mb: n('ramReserveMb') }),
    ...(n('diskReserveGb') === (was.disk_reserve_gb ?? null) ? {} : { disk_reserve_gb: n('diskReserveGb') }),
    ...(n('ramAllowanceMb') === (was.ram_allowance_mb ?? null) ? {} : { ram_allowance_mb: n('ramAllowanceMb') }),
    ...(n('diskAllowanceGb') === (was.disk_allowance_gb ?? null) ? {} : { disk_allowance_gb: n('diskAllowanceGb') }),
    ...(n('vmMaxRunning') === (was.vm_max_running ?? null) ? {} : { vm_max_running: n('vmMaxRunning') }),
    ...(n('vmCpu') === (was.vm_cpu ?? null) ? {} : { vm_cpu: n('vmCpu') }),
    ...(n('vmRamMb') === (was.vm_ram_mb ?? null) ? {} : { vm_ram_mb: n('vmRamMb') }),
    ...(n('vmDiskGb') === (was.vm_disk_gb ?? null) ? {} : { vm_disk_gb: n('vmDiskGb') }),
    ...(textOrNull(form.vmImage) === (was.vm_image ?? null) ? {} : { vm_image: textOrNull(form.vmImage) }),
    ...(textOrNull(form.subdomain) === (was.subdomain ?? null) ? {} : { subdomain: textOrNull(form.subdomain) }),
    ...(textOrNull(form.aiModel) === (was.ai_model ?? null) ? {} : { ai_model: textOrNull(form.aiModel) }),
  }
}

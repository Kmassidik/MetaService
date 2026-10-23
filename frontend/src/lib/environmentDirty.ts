// Whether the Environment form has changes that were not saved yet, which sections they are in, and how to put the form back to the last saved values.
import { sameForm, type EnvForm, type FormErrors } from './environmentForm.ts'

/** The sections of the Environment tab that hold fields to edit. */
export type EditableSection = 'limits' | 'vmDefaults' | 'names'

/** Which form fields live in which section. */
export const SECTION_FIELDS: Record<EditableSection, ReadonlyArray<keyof EnvForm>> = {
  limits: ['ramReserveMb', 'diskReserveGb', 'ramAllowanceMb', 'diskAllowanceGb', 'vmMaxRunning', 'allowGpu'],
  vmDefaults: ['vmCpu', 'vmRamMb', 'vmDiskGb', 'vmImage'],
  names: ['name', 'labels', 'notes', 'subdomain', 'aiModel', 'sshJump'],
}

const SECTIONS = Object.keys(SECTION_FIELDS) as EditableSection[]

/** True when the form differs from the last saved values. Typing a value and then typing the old one back is not a change. */
export const isDirty = (form: EnvForm, saved: EnvForm): boolean => !sameForm(form, saved)

/** The sections where a field differs from the last saved values, in page order. */
export const dirtySections = (form: EnvForm, saved: EnvForm): EditableSection[] =>
  SECTIONS.filter((section) => SECTION_FIELDS[section].some((field) => form[field] !== saved[field]))

/** The sections that hold a field which cannot be saved as it is, in page order. */
export const errorSections = (errors: FormErrors): EditableSection[] =>
  SECTIONS.filter((section) => SECTION_FIELDS[section].some((field) => field in errors))

/** A fresh copy of the last saved values, so the form can be set to it without sharing the saved object. */
export const undoneForm = (saved: EnvForm): EnvForm => ({ ...saved })

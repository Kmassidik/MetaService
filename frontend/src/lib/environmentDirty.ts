// Whether the Environment form has changes that were not saved yet, and how to put it back to the last saved values.
import { sameForm, type EnvForm } from './environmentForm.ts'

/** True when the form differs from the last saved values. Typing a value and then typing the old one back is not a change. */
export const isDirty = (form: EnvForm, saved: EnvForm): boolean => !sameForm(form, saved)

/** A fresh copy of the last saved values, so the form can be set to it without sharing the saved object. */
export const undoneForm = (saved: EnvForm): EnvForm => ({ ...saved })

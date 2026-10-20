/**
 * Pure rules for the side panel's Details form: whether it differs from the saved bot (dirty), and
 * what its Save button says. Whitespace at either end never counts as a change (Save trims).
 */
import type { Agent } from './types.ts'

/** The Details form's fields. */
export interface ProfileForm {
  name: string
  summary: string
  instructions: string
}

type SavedBot = Pick<Agent, 'name' | 'summary' | 'description'>

// Form field → the saved bot's field it edits (the bot keeps its instructions as `description`).
const SAVED_FIELD: Readonly<Record<keyof ProfileForm, keyof SavedBot>> = Object.freeze({
  name: 'name', summary: 'summary', instructions: 'description',
})
const FORM_FIELDS: readonly (keyof ProfileForm)[] = ['name', 'summary', 'instructions']

export const SAVE_STATE = Object.freeze({ clean: 'clean', dirty: 'dirty', saving: 'saving', saved: 'saved' })
export type SaveState = (typeof SAVE_STATE)[keyof typeof SAVE_STATE]

const SAVE_LABELS: Readonly<Record<SaveState, string>> = Object.freeze({
  [SAVE_STATE.clean]: 'Save',
  [SAVE_STATE.dirty]: 'Save changes',
  [SAVE_STATE.saving]: 'Saving…',
  [SAVE_STATE.saved]: 'Saved ✓',
})

const normalized = (value: unknown): string => String(value ?? '').trim()

/** The bot's saved values, as the form holds them. */
export function savedProfile(agent: SavedBot | null | undefined): ProfileForm {
  return {
    name: normalized(agent?.[SAVED_FIELD.name]),
    summary: normalized(agent?.[SAVED_FIELD.summary]),
    instructions: normalized(agent?.[SAVED_FIELD.instructions]),
  }
}

/** True when any edited field differs from what the bot has saved. */
/** A form as the screen holds it: any field may still be unset. */
type EditedForm = Partial<Record<keyof ProfileForm, unknown>>

export function isProfileDirty(form: EditedForm | null | undefined, agent: SavedBot | null | undefined): boolean {
  if (!agent) return false
  const saved = savedProfile(agent)
  return FORM_FIELDS.some(field => normalized(form?.[field]) !== saved[field])
}

interface SaveInputs {
  saving?: boolean
  dirty?: boolean
  justSaved?: boolean
}

/** Saving wins, then unsaved edits, then the brief "Saved" after a save, else clean. */
export function saveState({ saving = false, dirty = false, justSaved = false }: SaveInputs): SaveState {
  if (saving) return SAVE_STATE.saving
  if (dirty) return SAVE_STATE.dirty
  return justSaved ? SAVE_STATE.saved : SAVE_STATE.clean
}

export const saveLabel = (state: SaveState): string => SAVE_LABELS[state]

/** Save can be pressed only with edits to save and nothing locking the form. */
export const canSave = (state: SaveState, locked: boolean): boolean => state === SAVE_STATE.dirty && !locked

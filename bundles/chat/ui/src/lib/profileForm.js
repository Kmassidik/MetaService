/**
 * Pure rules for the side panel's Details form: whether it differs from the saved bot (dirty), and
 * what its Save button says. Whitespace at either end never counts as a change (Save trims).
 */

// Form field → the saved bot's field it edits (the bot keeps its instructions as `description`).
const SAVED_FIELD = Object.freeze({ name: 'name', summary: 'summary', instructions: 'description' })

export const SAVE_STATE = Object.freeze({ clean: 'clean', dirty: 'dirty', saving: 'saving', saved: 'saved' })

const SAVE_LABELS = Object.freeze({
  [SAVE_STATE.clean]: 'Save',
  [SAVE_STATE.dirty]: 'Save changes',
  [SAVE_STATE.saving]: 'Saving…',
  [SAVE_STATE.saved]: 'Saved ✓',
})

const normalized = value => String(value ?? '').trim()

/** The bot's saved values, as the form holds them. */
export function savedProfile(agent) {
  return Object.fromEntries(Object.entries(SAVED_FIELD).map(([field, key]) => [field, normalized(agent?.[key])]))
}

/** True when any edited field differs from what the bot has saved. */
export function isProfileDirty(form, agent) {
  if (!agent) return false
  const saved = savedProfile(agent)
  return Object.keys(SAVED_FIELD).some(field => normalized(form?.[field]) !== saved[field])
}

/** Saving wins, then unsaved edits, then the brief "Saved" after a save, else clean. */
export function saveState({ saving = false, dirty = false, justSaved = false }) {
  if (saving) return SAVE_STATE.saving
  if (dirty) return SAVE_STATE.dirty
  return justSaved ? SAVE_STATE.saved : SAVE_STATE.clean
}

export const saveLabel = state => SAVE_LABELS[state]

/** Save can be pressed only with edits to save and nothing locking the form. */
export const canSave = (state, locked) => state === SAVE_STATE.dirty && !locked

/**
 * Unsaved Details edits: leaving them (another tab, another bot, closing the panel) first asks,
 * inline in the panel, "Save / Discard" instead of silently dropping the edits.
 */
import { type ProfileForm, isProfileDirty } from '../profileForm.ts'
import { chat, selectedAgent } from './state.svelte.ts'

// The leave that waits for the owner's answer; a newer leave replaces it.
let heldLeave: (() => unknown) | null = null

/** The Details form as the dirty check reads it. */
export function profileForm(): ProfileForm {
  return { name: chat.profileName, summary: chat.profileSummary, instructions: chat.profileInstructions }
}

/** True while the open panel's Details form has edits the bot has not saved. */
export function profileDirty(): boolean {
  const active = selectedAgent()
  if (!chat.sidePanelOpen || !active || active.kind === 'team') return false
  return isProfileDirty(profileForm(), active)
}

/** Runs `leave` now, or holds it behind the inline prompt while there are unsaved edits. */
export function guardUnsaved<T>(leave: () => T): T | undefined {
  if (!profileDirty()) return leave()
  heldLeave = leave
  chat.unsavedPrompt = true
  return undefined
}

/** The owner answered Save (after it succeeded) or Discard: carry on with the held leave. */
export function continueLeave(): unknown {
  const leave = heldLeave
  dropLeave()
  return leave?.()
}

/** Forgets the held leave and hides the prompt. */
export function dropLeave(): void {
  heldLeave = null
  chat.unsavedPrompt = false
}

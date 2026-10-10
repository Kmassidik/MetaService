<script>
  /**
   * The sticky foot of Details: the Save button (clean / dirty / saving / saved), or, when the owner
   * tries to leave with unsaved edits, the inline "You have unsaved changes — Save / Discard".
   */
  import { SAVE_STATE, canSave, saveLabel } from '../../lib/profileForm.js'

  let { state = SAVE_STATE.clean, locked = false, asking = false, onSaveAndLeave, onDiscard } = $props()
</script>

<div class="profile-save">
  {#if asking}
    <div class="unsaved" role="alert">
      <p>You have unsaved changes</p>
      <div class="unsaved-actions">
        <button type="button" class="secondary-button" onclick={onDiscard}>Discard</button>
        <button type="button" class="primary-button" disabled={locked} onclick={onSaveAndLeave}>{state === SAVE_STATE.saving ? saveLabel(state) : 'Save'}</button>
      </div>
    </div>
  {:else}
    <button type="submit" class="primary-button" class:is-saved={state === SAVE_STATE.saved} class:is-saving={state === SAVE_STATE.saving} disabled={!canSave(state, locked)} aria-live="polite">{saveLabel(state)}</button>
  {/if}
</div>

<style>
  .profile-save { position: sticky; bottom: 0; padding: 12px 0 max(16px, env(safe-area-inset-bottom)); background: linear-gradient(transparent, var(--sidebar) 30%); }
  .profile-save > .primary-button { width: 100%; }
  /* Opaque even when disabled: the bar floats over the form as it scrolls. */
  .profile-save > .primary-button:disabled { opacity: 1; border-color: var(--hairline); background: var(--page); color: var(--text-3); }
  .profile-save > .primary-button.is-saving:disabled { border-color: var(--ink); background: var(--ink); color: var(--on-ink); }
  .profile-save > .primary-button.is-saved:disabled { border-color: var(--ok); background: var(--ok-bg); color: var(--ok-text); }
  .unsaved { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 10px 10px 14px; border: 1px solid var(--hairline); border-radius: var(--radius-card); background: var(--page); box-shadow: var(--shadow-float); }
  .unsaved p { color: var(--text); font: 500 var(--fs-preview)/1.35 var(--font); }
  .unsaved-actions { display: flex; flex-shrink: 0; gap: 8px; }
  .unsaved-actions button { min-height: 34px; padding: 6px 14px; }
</style>

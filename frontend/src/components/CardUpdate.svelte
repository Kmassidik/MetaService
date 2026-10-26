<script lang="ts">
  // The Update helper button of a machine card, with "Updating…" while it runs and the result sentence after. Same call and wording as the Environment tab.
  import { cardUpdate, UPDATE_BUTTON, UPDATE_EXPLANATION, UPDATING_TEXT } from '../lib/helperUpdate.ts'
  import { HelperUpdater } from '../lib/helperUpdater.svelte.ts'
  import type { Machine } from '../lib/types.ts'

  let { machine, onChanged }: { machine: Machine; onChanged: () => void } = $props()
  const updater = new HelperUpdater()
  const offer = $derived(cardUpdate(machine))
  const outcome = $derived(updater.outcome)

  async function update() {
    await updater.run(machine.id)
    onChanged()
  }
</script>

{#if offer.button || updater.updating}
  <div class="cu" data-card-update>
    <button class="btn line sm" type="button" disabled={updater.updating} aria-busy={updater.updating} title={UPDATE_EXPLANATION} onclick={update}>{updater.updating ? UPDATING_TEXT : UPDATE_BUTTON}</button>
  </div>
{/if}
{#if offer.note}<p class="cu-note">{offer.note}</p>{/if}
{#if outcome}
  <p class="cu-out {outcome.tone}" role={outcome.tone === 'bad' ? 'alert' : 'status'} data-card-outcome><b>{outcome.title}.</b> {outcome.detail}</p>
{/if}

<style>
  /* The card puts the button in its own reserved row, so the margin comes from there. */
  .cu { margin-top: 0; }
  .cu-note, .cu-out { margin: 8px 0 0; font-size: 12.5px; overflow-wrap: anywhere; }
  .cu-note { color: var(--warn); }
  .cu-out.ok { color: var(--ok-note-text); }
  .cu-out.warn { color: var(--warn-note-title); }
  .cu-out.bad { color: var(--danger-note-text); }
</style>

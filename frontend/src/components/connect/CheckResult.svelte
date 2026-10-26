<script lang="ts">
  // Step 3, Check: what the other computer has, in cards by topic. Nothing is installed here, except what a person asks for with "Install it for me".
  // added: this is a machine that is already there ("Check again"), so the footer closes instead of adding it a second time.
  import CheckCard from './CheckCard.svelte'
  import CheckHead from './CheckHead.svelte'
  import { checkCards, checkRows, stoppedEarly } from '../../lib/checkRows.ts'
  import { isolationText } from '../../lib/remote.ts'
  import type { ConnectForm, VerifyResult } from '../../lib/types.ts'

  interface Props {
    result: VerifyResult
    form: ConnectForm
    onChecked: (result: VerifyResult) => void
    onAgain: () => void
    /** Add this computer as a machine. Left out when it is already added. */
    onAdd?: () => void
    /** The machine is already added: no Add, and the footer closes. */
    added?: boolean
    onClose?: () => void
  }

  let { result, form, onChecked, onAgain, onAdd, added = false, onClose }: Props = $props()
  const rows = $derived(checkRows(result.requirements))
  const cards = $derived(checkCards(rows))
</script>

<CheckHead {result} {rows} {added} />
<div class="cards">
  {#each cards as card (card.id)}<CheckCard {card} {form} fingerprint={result.fingerprint} {onChecked} />{/each}
</div>
{#if stoppedEarly(rows)}<p class="note">We stopped here, so nothing else was checked.</p>{/if}
<p class="note"><b>Two words:</b> a VM is a whole virtual computer. A container is a small sealed box that runs one program.</p>
{#if result.isolation.length > 0}
  <div class="note">
    <b>{added ? 'Where MetaService is:' : 'Where MetaService would go:'}</b>
    <ul>{#each result.isolation as level (level)}<li>{isolationText(level)}</li>{/each}</ul>
  </div>
{/if}
<div class="foot">
  <button class="btn line" type="button" onclick={onAgain}>{added ? 'Check again' : 'Check another'}</button>
  {#if added}
    <button class="btn green" type="button" onclick={() => onClose?.()}>Done</button>
  {:else}
    <button class="btn green" type="button" disabled={!result.can_add} onclick={() => onAdd?.()}>Add machine</button>
  {/if}
</div>

<style>
  .cards { display: grid; gap: 10px; }
  .note { margin: 0; font-size: 13px; color: var(--m70); }
  .note b { color: var(--text); }
  .note ul { margin: 2px 0 0; padding-left: 18px; }
  .foot { display: flex; flex-wrap: wrap; gap: 10px; justify-content: flex-end; }
  .btn.line { border-color: var(--line-strong); }
  @media (max-width: 520px) { .foot .btn { flex: 1 1 100%; } }
</style>

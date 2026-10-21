<script lang="ts">
  // What the terminal window says instead of a screen when there is none: why in plain words, why the VM stopped, and the buttons that make sense (Start the VM, Close).
  import WhyStopped from './vm/WhyStopped.svelte'
  import type { StopNote } from '../lib/stoppedReason.ts'
  import type { Notice } from '../lib/terminalNotice.ts'

  interface Props {
    notice: Notice
    /** Why the VM stopped, when it is stopped. */
    note: StopNote | null
    starting: boolean
    onstart: () => void
    onclose: () => void
  }

  let { notice, note, starting, onstart, onclose }: Props = $props()
  const why = $derived(notice.why ? note : null)
</script>

<div class="notice" role="status">
  <p class="ntext">{notice.text}</p>
  {#if why}<WhyStopped note={why} />{/if}
  <div class="nact">
    {#if notice.canStart}<button class="btn green sm" type="button" disabled={starting} onclick={onstart}>{starting ? 'Starting…' : 'Start the VM'}</button>{/if}
    <button class="btn line sm" type="button" onclick={onclose}>Close</button>
  </div>
</div>

<style>
  /* A plain panel in the middle of the window, in the panel's usual light colours. */
  .notice { margin: auto; width: min(560px, calc(100% - 32px)); padding: 20px 22px; display: grid; gap: 14px; background: var(--white); color: var(--black); border: 1px solid var(--gray); }
  .ntext { margin: 0; font-size: 15px; }
  .nact { display: flex; gap: 8px; flex-wrap: wrap; }
</style>

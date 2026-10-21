<script lang="ts">
  // The ✓ ✗ list of what a computer has (a ✗ also says what to do, and may offer to do it), shown before anything is installed (shown by Add a machine).
  import InstallItForMe from './InstallItForMe.svelte'
  import type { ConnectForm, Requirement, VerifyResult } from '../lib/types.ts'

  interface Props {
    items: Requirement[]
    label?: string
    /** With these, a ✗ that the parent can fix gets "Install it for me"; the new check replaces the list. */
    form?: ConnectForm
    fingerprint?: string
    onChecked?: (result: VerifyResult) => void
  }

  let { items, label = 'What this computer has', form, fingerprint, onChecked }: Props = $props()
</script>

<ul class="checks" aria-label={label}>
  {#each items as item (item.id)}
    <li class={item.ok ? 'pass' : 'block'}>
      <span class="mark" aria-hidden="true">{item.ok ? '✓' : '✗'}</span>
      <span>
        {item.label}<small>{item.detail}</small>{#if item.fix}<small class="fix">To fix: {item.fix}</small>{/if}
        {#if item.install && form && fingerprint && onChecked}<InstallItForMe offer={item.install} {form} {fingerprint} {onChecked} />{/if}
      </span>
    </li>
  {/each}
</ul>

<style>
  .checks { list-style: none; margin: 14px 0 0; padding: 10px 12px; display: grid; gap: 8px; background: var(--gray2); border: 1px solid var(--gray); font-size: 13px; }
  li { display: flex; gap: 10px; align-items: baseline; }
  li.pass .mark { color: var(--run); font-weight: 700; }
  li.block .mark { color: #c0392b; font-weight: 700; }
  .fix { color: var(--m70); margin-top: 2px; }
  small { display: block; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .mark { width: 14px; font-family: var(--mono); }
</style>

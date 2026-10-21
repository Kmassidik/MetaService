<script lang="ts">
  // The ✓ ✗ list of what a computer has (a ✗ also says what to do), shown before anything is installed (shown by Add a machine).
  import type { Requirement } from '../lib/types.ts'

  let { items, label = 'What this computer has' }: { items: Requirement[]; label?: string } = $props()
</script>

<ul class="checks" aria-label={label}>
  {#each items as item (item.id)}
    <li class={item.ok ? 'pass' : 'block'}>
      <span class="mark" aria-hidden="true">{item.ok ? '✓' : '✗'}</span>
      <span>{item.label}<small>{item.detail}</small>{#if item.fix}<small class="fix">To fix: {item.fix}</small>{/if}</span>
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

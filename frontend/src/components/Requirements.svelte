<script lang="ts">
  // The ✓ ! ✗ list of what a computer has, shown before anything is installed (this computer in Add machine, another one in Connect).
  import type { Requirement } from '../lib/types.ts'

  let { items, label = 'What this computer has' }: { items: Requirement[]; label?: string } = $props()
</script>

<ul class="checks" aria-label={label}>
  {#each items as item (item.id)}
    <li class={item.ok ? 'pass' : item.optional ? 'miss' : 'block'}>
      <span class="mark" aria-hidden="true">{item.ok ? '✓' : item.optional ? '!' : '✗'}</span>
      <span>{item.label}<small>{item.detail}</small></span>
    </li>
  {/each}
</ul>

<style>
  .checks { list-style: none; margin: 14px 0 0; padding: 10px 12px; display: grid; gap: 8px; background: var(--gray2); border: 1px solid var(--gray); font-size: 13px; }
  li { display: flex; gap: 10px; align-items: baseline; }
  li.pass .mark { color: var(--run); font-weight: 700; }
  li.miss .mark { color: var(--warn); font-weight: 700; }
  li.block .mark { color: #c0392b; font-weight: 700; }
  small { display: block; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .mark { width: 14px; font-family: var(--mono); }
</style>

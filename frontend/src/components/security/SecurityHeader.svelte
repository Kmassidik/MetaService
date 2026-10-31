<script lang="ts">
  // The top of the Security page: its name, one line saying what it is for, the time range, and the link to the sample data.
  import { securityHref, type SecurityView } from '../../lib/securityRoute.ts'
  import { RANGES, RANGE_LABELS, type SecurityRange } from '../../lib/securityTypes.ts'

  let { view }: { view: SecurityView } = $props()

  function choose(range: SecurityRange) {
    location.hash = securityHref({ ...view, range })
  }
</script>

<div class="phead">
  <h1>Security</h1><span class="crumb">Infrastructure › Security</span>
  <div class="sp">
    <div class="segmented" role="group" aria-label="Time range">
      {#each RANGES as range (range)}
        <button type="button" class:on={view.range === range} aria-pressed={view.range === range} data-range={range} onclick={() => choose(range)}>{RANGE_LABELS[range]}</button>
      {/each}
    </div>
  </div>
</div>
<p class="what">
  Who is trying to log in to your machines, what was blocked, and whether the basic settings are safe. Read only.
  {#if !view.preview}<a href={securityHref({ ...view, preview: true })} data-testid="preview-link">Preview with sample data</a>{/if}
</p>

<style>
  .what { margin: 0; padding: 12px 28px 0; font-size: 13px; color: var(--m60); display: flex; gap: 6px 14px; flex-wrap: wrap; align-items: baseline; }
  .what a { font-family: var(--mono); font-size: 11px; color: var(--m50); text-decoration: underline; }
  @media (max-width: 820px) { .what { padding: 12px 16px 0; } }
</style>

<script lang="ts">
  /** The first 200 rows × 50 columns of a CSV as text cells; formulas are never evaluated. */
  import SourceView from './SourceView.svelte'
  import type { CsvPreview as CsvContent } from '../../lib/files/textPreview.ts'
  import { CSV_MAX_COLUMNS, CSV_MAX_ROWS } from '../../lib/files/textPreview.ts'

  // How far one press of a scroll button moves the table (keyboard and switch users).
  const SCROLL_STEP_PX = 240
  const SCROLLS: ReadonlyArray<readonly [string, ScrollToOptions]> = [
    ['Scroll left', { left: -SCROLL_STEP_PX }],
    ['Scroll right', { left: SCROLL_STEP_PX }],
    ['Scroll up', { top: -SCROLL_STEP_PX }],
    ['Scroll down', { top: SCROLL_STEP_PX }],
  ]

  interface Props {
    content: { source: string } & CsvContent
    name: string
  }

  let { content, name }: Props = $props()

  let viewport = $state<HTMLElement | null>(null)
</script>

<p class="file-meta">
  Showing at most {CSV_MAX_ROWS} rows and {CSV_MAX_COLUMNS} columns; formulas are not evaluated.
  {#if content.truncated}This preview is truncated; download the original for the full data.{/if}
</p>
<div class="file-actions" role="group" aria-label="Scroll CSV table">
  {#each SCROLLS as [label, offset] (label)}
    <button type="button" class="secondary-button" onclick={() => viewport?.scrollBy(offset)}>{label}</button>
  {/each}
</div>
<div bind:this={viewport} class="csv-table" role="region" aria-label={`CSV table of ${name}`}>
  <table>
    <tbody>
      {#each content.rows as row, rowIndex (rowIndex)}
        <tr>{#each row as cell, cellIndex (cellIndex)}<td>{cell}</td>{/each}</tr>
      {/each}
    </tbody>
  </table>
</div>
<SourceView source={content.source} {name} />

<style>
  .csv-table { overflow: auto; max-height: 60dvh; margin-top: 12px; border: 1px solid var(--hairline); }
  table { border-collapse: collapse; font: 12px/1.6 var(--font); }
  td { min-width: 80px; max-width: 300px; padding: 6px 9px; border: 1px solid var(--hairline); white-space: pre-wrap; overflow-wrap: anywhere; vertical-align: top; }
</style>

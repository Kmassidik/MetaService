<script lang="ts">
  // Page controls under a long list: "Showing a to b of N", Previous / Next, the page numbers (with gaps) and the page size. Draws nothing when every row fits on
  // one page.
  // The Pager keeps the page and the remembered page size; this only draws and asks the Pager to change.
  import type { Pager } from '../lib/pager.svelte.ts'
  import { PAGE_SIZES, pageCount, pageItems, showingText } from '../lib/paging.ts'

  let { pager, total, label = 'rows' }: { pager: Pager; total: number; label?: string } = $props()
  const sizeId = $props.id()
  const current = $derived(pager.window(total).page)
  const count = $derived(pageCount(total, pager.size))
  const items = $derived(pageItems(current, count))
  const needed = $derived(count > 1)

  function pickSize(event: Event) {
    if (event.currentTarget instanceof HTMLSelectElement) pager.resize(Number(event.currentTarget.value))
  }
</script>

{#if needed}
  <nav class="pager" aria-label="Pages of {label}" data-testid="pagination">
    <p class="showing" role="status" data-testid="pagination-showing">{showingText(current, total, pager.size)}</p>
    <div class="buttons">
      <button class="btn line sm" type="button" data-testid="page-prev" aria-label="Previous page" disabled={current <= 1} onclick={() => pager.go(current - 1)}>Previous</button>
      <ol class="numbers">
        {#each items as item (item.kind === 'page' ? item.page : `gap-${item.after}`)}
          <li>
            {#if item.kind === 'gap'}
              <span class="gap" aria-hidden="true">…</span>
            {:else}
              <button class="btn line sm num" type="button" class:on={item.page === current} aria-label="Page {item.page}" aria-current={item.page === current ? 'page' : undefined} onclick={() => pager.go(item.page)}>{item.page}</button>
            {/if}
          </li>
        {/each}
      </ol>
      <button class="btn line sm" type="button" data-testid="page-next" aria-label="Next page" disabled={current >= count} onclick={() => pager.go(current + 1)}>Next</button>
    </div>
    <label class="size" for={sizeId}>Rows per page
      <select id={sizeId} data-testid="page-size" value={String(pager.size)} onchange={pickSize}>
        {#each PAGE_SIZES as size (size)}<option value={String(size)}>{size}</option>{/each}
      </select>
    </label>
  </nav>
{/if}

<style>
  .pager { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px 16px; padding: 12px 0 0; min-width: 0; }
  .showing { margin: 0; font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .buttons { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
  .numbers { display: flex; flex-wrap: wrap; align-items: center; gap: 4px; margin: 0; padding: 0; list-style: none; }
  .num { min-width: 34px; padding-inline: 8px; }
  .num.on { background: var(--inverse-bg); color: var(--inverse-text); border-color: var(--line-strong); }
  .gap { padding: 0 4px; color: var(--m50); font-family: var(--mono); }
  .size { display: flex; align-items: center; gap: 8px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  select { min-height: 34px; padding: 0 8px; border: 1px solid var(--line); background: var(--surface); color: var(--text); font-family: var(--mono); font-size: 12px; }
  @media (max-width: 820px) {
    .pager { flex-direction: column; align-items: stretch; }
    .buttons { justify-content: space-between; }
    .numbers { flex: 1; justify-content: center; }
    .size { justify-content: space-between; }
  }
</style>

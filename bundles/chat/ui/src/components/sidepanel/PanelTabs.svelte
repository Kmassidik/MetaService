<script lang="ts">
  import type { PanelTab, PanelTabItem } from '../../lib/sidePanel.ts'

  /** Details / Files / Computer: plain words, the current one in a soft outlined pill. */
  interface Props {
    tabs?: readonly PanelTabItem[]
    current?: string
    panelId?: string
    onSelect: (id: PanelTab) => void
  }

  const STEPS: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1 }

  let { tabs = [], current = '', panelId = '', onSelect }: Props = $props()

  function move(event: KeyboardEvent & { currentTarget: HTMLElement }, index: number): void {
    const step = STEPS[event.key]
    const next = step ? tabs[(index + step + tabs.length) % tabs.length] : undefined
    if (!step || !next) return
    event.preventDefault()
    onSelect(next.id)
    event.currentTarget.parentElement?.querySelector<HTMLElement>(`[data-tab="${next.id}"]`)?.focus()
  }
</script>

<div class="tabs" role="tablist" aria-label="Panel sections">
  {#each tabs as tab, index (tab.id)}
    <button
      type="button"
      role="tab"
      class="tab"
      data-tab={tab.id}
      aria-selected={tab.id === current}
      aria-controls={panelId}
      tabindex={tab.id === current ? 0 : -1}
      onclick={() => onSelect(tab.id)}
      onkeydown={event => move(event, index)}
    >{tab.label}</button>
  {/each}
</div>

<style>
  .tabs { display: flex; justify-content: center; gap: 4px; padding: 0 16px 14px; }
  .tab {
    height: 34px;
    padding: 0 12px;
    border: 1px solid transparent;
    border-radius: var(--radius-control);
    background: none;
    color: var(--text-2);
    font: 400 var(--fs-name)/1 var(--font);
    cursor: pointer;
  }
  .tab:hover { color: var(--text); }
  .tab[aria-selected="true"] { border-color: var(--hairline); background: var(--page); color: var(--text); box-shadow: var(--shadow-float); }
  .tab:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 1px; }
</style>

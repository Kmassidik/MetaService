<script lang="ts">
  // "Type": the CPU model the VM sees, as in Proxmox: a box showing the model, × to go back to host, and a list under it with a Model and a Vendor column.
  // Only the models the machine offers are listed, host first. The keys work as in the window's other dropdowns: the focus stays on the box, Escape shuts only the list.
  import { firstPickable, isMenuKey, nextActive } from '../../../lib/menuNav.ts'
  import { HOST_MODEL, modelVendor } from '../../../lib/cpuOptions.ts'
  import { cpuTypeLabel } from '../../../lib/cpuModel.ts'
  import FieldBlock from './FieldBlock.svelte'

  interface Props {
    id: string
    models: string[]
    chosen: string
    /** The machine's CPU name, shown after host; null or left out when the machine does not say. */
    hostName?: string | null | undefined
    /** Why the type cannot be changed (a machine that offers host only); null when it can. */
    reason: string | null
    onpick: (model: string) => void
  }

  const OPENING_KEYS = ['ArrowDown', 'ArrowUp']

  let { id, models, chosen, hostName = null, reason, onpick }: Props = $props()
  let open = $state(false)
  let active = $state(0)
  let root: HTMLDivElement | undefined = $state()
  let trigger: HTMLButtonElement | undefined = $state()
  const labelId = $derived(`${id}-label`)
  const menuId = $derived(`${id}-menu`)
  const optionId = (index: number) => `${id}-option-${index}`
  const disabledFlags = $derived(models.map(() => false))

  function show() {
    const at = models.indexOf(chosen)
    active = at >= 0 ? at : firstPickable(disabledFlags)
    open = true
  }

  const toggle = () => (open ? (open = false) : show())

  function choose(index: number) {
    const model = models[index]
    if (model === undefined) return
    onpick(model)
    open = false
    trigger?.focus()
  }

  function onkeydown(event: KeyboardEvent) {
    if (!open) {
      if (!OPENING_KEYS.includes(event.key)) return
      event.preventDefault()
      show()
    } else if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      open = false
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault()
      choose(active)
    } else if (event.key === 'Tab') {
      open = false
    } else if (isMenuKey(event.key)) {
      event.preventDefault()
      active = nextActive(disabledFlags, active, event.key)
    }
  }

  /** A press anywhere outside the box closes the list. */
  function closeOnOutside(event: PointerEvent) {
    if (!open || !(event.target instanceof Node) || root?.contains(event.target)) return
    open = false
  }

  function backToHost() {
    onpick(HOST_MODEL)
    trigger?.focus()
  }
</script>

<svelte:window onpointerdown={closeOnOutside} />

<FieldBlock label="Type" {labelId}>
  <div class="combo" bind:this={root} title={reason ?? undefined}>
    <button
      bind:this={trigger}
      {id}
      type="button"
      class="trigger"
      role="combobox"
      aria-haspopup="listbox"
      aria-expanded={open}
      aria-controls={menuId}
      aria-labelledby="{labelId} {id}-value"
      aria-activedescendant={open ? optionId(active) : undefined}
      disabled={reason !== null}
      data-count={models.length}
      onclick={toggle}
      {onkeydown}
    >
      <span class="value" id="{id}-value" title={cpuTypeLabel(chosen, hostName)}>{cpuTypeLabel(chosen, hostName)}</span>
      <svg class="chevron" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
    </button>
    {#if chosen !== HOST_MODEL}<button type="button" class="clear" aria-label="Back to host" title="Back to host" onclick={backToHost}>✕</button>{/if}
    {#if open}
      <div class="menu" id={menuId} role="listbox" aria-labelledby={labelId}>
        <div class="head" aria-hidden="true"><span>Model</span><span>Vendor</span></div>
        {#each models as model, index (model)}
          <div
            class="row"
            class:active={index === active}
            id={optionId(index)}
            data-value={model}
            role="option"
            tabindex="-1"
            aria-selected={model === chosen}
            onmousedown={(event) => event.preventDefault()}
            onclick={() => choose(index)}
            {onkeydown}
            onmousemove={() => (active = index)}
          >
            <span class="model" title={cpuTypeLabel(model, hostName)}>{cpuTypeLabel(model, hostName)}</span><span class="vendor">{modelVendor(model)}</span>
          </div>
        {/each}
      </div>
    {/if}
  </div>
</FieldBlock>

<style>
  .combo { position: relative; min-width: 0; }
  .trigger { display: flex; align-items: center; width: 100%; min-height: 32px; padding: 0 9px; border: 1px solid var(--reserve-line); border-radius: 0; background: var(--surface); color: var(--text); font: 400 13px var(--sans); text-align: left; cursor: pointer; }
  .trigger:hover:not(:disabled) { border-color: var(--m50); }
  .trigger:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 1px; }
  .trigger:disabled { background: var(--surface-2); color: var(--m40); cursor: not-allowed; }
  .value { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .chevron { flex: none; width: 14px; height: 14px; color: var(--m60); }
  .clear { position: absolute; top: 50%; right: 28px; width: 20px; height: 20px; margin-top: -10px; padding: 0; border: 0; background: none; color: var(--m50); font-size: 11px; line-height: 1; }
  .clear:hover { color: var(--text); }
  .clear:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 1px; }
  .menu { position: absolute; z-index: 5; left: 0; right: 0; top: 100%; margin-top: 2px; max-height: 264px; overflow-y: auto; border: 1px solid var(--line-strong); background: var(--surface); box-shadow: var(--shadow-card); font: 400 13px var(--sans); }
  .head, .row { display: grid; grid-template-columns: minmax(0, 1fr) 116px; }
  .head { position: sticky; top: 0; background: var(--surface-2); border-bottom: 1px solid var(--line); font-weight: 600; color: var(--m70); }
  .head span, .row span { padding: 6px 9px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .head span + span, .row span + span { border-left: 1px solid var(--line); }
  .row { cursor: pointer; }
  .row:nth-child(odd) { background: var(--page-bg); }
  .row:nth-child(even) { background: var(--surface-2); }
  .row.active { background: var(--ok-note-bg); }
  .row[aria-selected='true'] { background: var(--accent-soft); color: var(--accent-text); }
  .vendor { color: var(--m60); }
  .row[aria-selected='true'] .vendor { color: var(--accent-text); }
</style>

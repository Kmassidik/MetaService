<script lang="ts">
  // "Server image": a button showing the chosen image, and a list under it with one row for each image of the parent's catalog. An image that cannot be picked is shown greyed out with its reason as the caption and a small tag.
  // The focus stays on the button while the list is open (the row the arrow keys are on is named by aria-activedescendant). Escape closes only the list, never the window around it.
  import { firstPickable, isMenuKey, nextActive } from '../../../lib/menuNav.ts'
  import type { ImageCard } from '../../../lib/images.ts'
  import FieldBlock from './FieldBlock.svelte'
  import ImageBadge from './ImageBadge.svelte'

  interface Props {
    id: string
    cards: ImageCard[]
    chosen: string
    /** True when the parent's list of images could not be read, so only Blank is offered. */
    unreadable: boolean
    onpick: (id: string) => void
  }

  const UNREADABLE_NOTE = 'The list of images could not be read, so only Blank is offered.'
  const OPENING_KEYS = ['ArrowDown', 'ArrowUp']

  let { id, cards, chosen, unreadable, onpick }: Props = $props()
  let open = $state(false)
  let active = $state(0)
  let root: HTMLDivElement | undefined = $state()
  let trigger: HTMLButtonElement | undefined = $state()
  let menu: HTMLDivElement | undefined = $state()
  const labelId = $derived(`${id}-label`)
  const menuId = $derived(`${id}-menu`)
  const optionId = (index: number) => `${id}-option-${index}`
  const disabledFlags = $derived(cards.map((card) => card.disabled))
  const selected = $derived(cards.find((card) => card.id === chosen) ?? cards[0])

  $effect(() => {
    if (open) menu?.scrollIntoView({ block: 'nearest' })
  })

  function show() {
    const at = cards.findIndex((card) => card.id === chosen)
    active = at >= 0 ? at : firstPickable(disabledFlags)
    open = true
  }

  const toggle = () => (open ? (open = false) : show())

  function choose(index: number) {
    const card = cards[index]
    if (!card || card.disabled) return
    onpick(card.id)
    open = false
    trigger?.focus()
  }

  function keyWhileClosed(event: KeyboardEvent) {
    if (!OPENING_KEYS.includes(event.key)) return
    event.preventDefault()
    show()
  }

  function keyWhileOpen(event: KeyboardEvent) {
    if (event.key === 'Escape') {
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

  const onkeydown = (event: KeyboardEvent) => (open ? keyWhileOpen(event) : keyWhileClosed(event))

  /** A press anywhere outside the dropdown closes the list. */
  function closeOnOutside(event: PointerEvent) {
    if (!open || !(event.target instanceof Node) || root?.contains(event.target)) return
    open = false
  }
</script>

<svelte:window onpointerdown={closeOnOutside} />

<FieldBlock label="Server image" {labelId}>
  <div class="dropdown" bind:this={root} data-images={cards.length}>
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
      onclick={toggle}
      {onkeydown}
    >
      {#if selected}
        <ImageBadge title={selected.title} logo={selected.logo} />
        <span class="text" id="{id}-value"><span class="name">{selected.title}</span><span class="caption">{selected.caption}</span></span>
      {/if}
      <svg class="chevron" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
    </button>
    {#if open}
      <div class="menu" id={menuId} role="listbox" aria-labelledby={labelId} bind:this={menu}>
        {#each cards as card, index (card.id)}
          <div
            class="row"
            class:active={index === active}
            class:disabled={card.disabled}
            id={optionId(index)}
            role="option"
            tabindex="-1"
            aria-selected={card.id === chosen}
            aria-disabled={card.disabled}
            onmousedown={(event) => event.preventDefault()}
            onclick={() => choose(index)}
            onkeydown={onkeydown}
            onmousemove={() => !card.disabled && (active = index)}
          >
            <ImageBadge title={card.title} logo={card.logo} muted={card.disabled} />
            <span class="text"><span class="name">{card.title}</span><span class="caption">{card.caption}</span></span>
            {#if card.tag}<span class="chip">{card.tag}</span>{/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>
  {#if unreadable}<p class="note">{UNREADABLE_NOTE}</p>{/if}
</FieldBlock>

<style>
  .dropdown { position: relative; min-width: 0; }
  .trigger { display: flex; align-items: center; gap: 12px; width: 100%; min-height: 56px; padding: 10px 12px; border: 2px solid var(--line-strong); border-radius: 0; background: var(--surface); color: var(--text); font-family: var(--mono); text-align: left; cursor: pointer; }
  .trigger:hover { background: var(--surface-2); }
  .trigger:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .text { display: grid; flex: 1; min-width: 0; }
  .name { font-size: 14px; font-weight: 700; line-height: 1.3; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .caption { font-size: 12px; color: var(--m50); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .chevron { flex: none; width: 16px; height: 16px; color: var(--m70); }
  .menu { position: absolute; z-index: 5; left: 0; right: 0; top: 100%; margin-top: 4px; border: 2px solid var(--line-strong); background: var(--surface); box-shadow: var(--shadow-card); }
  .row { display: flex; align-items: center; gap: 12px; padding: 12px; cursor: pointer; font-family: var(--mono); }
  .row + .row { border-top: 1px solid var(--line); }
  .row.active { background: var(--surface-2); }
  .row[aria-selected='true'] { box-shadow: inset 3px 0 0 var(--accent-mark); }
  .row.disabled { cursor: not-allowed; color: var(--m40); }
  .row.disabled .name, .row.disabled .caption { color: var(--m60); }
  .chip { flex: none; padding: 2px 8px; background: var(--reserve-bg); color: var(--m70); font: 700 10px var(--mono); letter-spacing: .06em; text-transform: uppercase; }
  .note { margin: 0; font-size: 12px; color: var(--m50); }
</style>

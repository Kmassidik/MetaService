<script lang="ts">
  // A small square badge for a machine card: one line icon, coloured by what it says, and its word in a tip on hover or keyboard focus. The tip is positioned on the screen
  // (not inside the card), so the card's clipping can never hide it. Screen readers read the label.
  import Icon from './Icon.svelte'

  type Tone = 'green' | 'blue' | 'violet' | 'amber' | 'red' | 'dark'
  const TIP_GAP_PX = 6
  let { path, label, tone = 'green', ...rest }: { path: string; label: string; tone?: Tone; [key: string]: unknown } = $props()
  let tip = $state<{ x: number; y: number } | null>(null)
  let tipBox = $state<HTMLElement | null>(null)
  // The page policy refuses a style attribute, so the tip is placed through the DOM instead.
  $effect(() => {
    if (!tipBox || !tip) return
    tipBox.style.left = `${tip.x}px`
    tipBox.style.top = `${tip.y}px`
  })

  function show(event: Event) {
    const box = (event.currentTarget as HTMLElement).getBoundingClientRect()
    tip = { x: box.left + box.width / 2, y: box.bottom + TIP_GAP_PX }
  }
  const hide = () => (tip = null)
</script>

<span class="ib {tone}" role="img" aria-label={label} tabindex="0" onmouseenter={show} onmouseleave={hide} onfocus={show} onblur={hide} {...rest}>
  <Icon {path} />
  {#if tip}<span class="tip" aria-hidden="true" bind:this={tipBox}>{label}</span>{/if}
</span>

<style>
  .ib { display: inline-flex; align-items: center; justify-content: center; flex: none; width: 24px; height: 22px; border: 1px solid; cursor: default; }
  .ib:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 1px; }
  .green { color: var(--ok); background: var(--ok-bg); border-color: var(--ok-note-line); }
  .blue { color: var(--info); background: var(--info-bg); border-color: var(--info-line); }
  .violet { color: var(--violet); background: var(--violet-bg); border-color: var(--violet-line); }
  .amber { color: var(--warn); background: var(--warn-bg); border-color: var(--warn-line); }
  .red { color: var(--danger); background: var(--danger-bg); border-color: var(--danger-line); }
  .dark { color: var(--inverse-text); background: var(--inverse-bg); border-color: var(--inverse-bg); }
  .tip { position: fixed; z-index: 90; transform: translateX(-50%); padding: 5px 9px; background: var(--inverse-bg); color: var(--inverse-text); font-family: var(--mono); font-size: 11px; font-weight: 600; letter-spacing: 0.02em; white-space: nowrap; pointer-events: none; box-shadow: var(--shadow-card); }
</style>

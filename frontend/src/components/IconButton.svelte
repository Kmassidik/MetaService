<script lang="ts">
  // A small icon-only button with a line icon in the sidebar's style. Its spoken name is the aria-label (the label, then the subject); the label alone shows as a tooltip on hover and on keyboard focus.
  // The tooltip is fixed-positioned from the button's own spot, so a table's overflow cannot clip it and it adds no sideways scrolling.
  // On a phone there is no hover: the short `text` stays beside the icon instead.
  interface Props {
    label: string
    /** What the button is about, for example the VM's name. Added to the spoken name only, so a screen reader can tell rows apart; the tooltip stays the short label. */
    subject?: string | undefined
    /** SVG path data on a 24 x 24 grid; several sub-paths may be joined in one string. */
    icon: string
    /** A page address: the control is then a link (it can open in a new tab) and not a button; `onclick` is not used. */
    href?: string
    onclick?: () => void
    variant?: 'normal' | 'danger'
    disabled?: boolean
    /** True while the action runs: a spinner replaces the icon. */
    busy?: boolean
    /** The short word shown beside the icon on a phone. */
    text?: string
  }

  let { label, subject, icon, href, onclick, variant = 'normal', disabled = false, busy = false, text }: Props = $props()
  const spokenName = $derived(subject ? `${label} ${subject}` : label)
</script>

{#snippet face()}
  {#if busy}<span class="btn-spin" aria-hidden="true"></span>{:else}<svg viewBox="0 0 24 24" aria-hidden="true"><path d={icon} /></svg>{/if}
  {#if text}<span class="word">{text}</span>{/if}
{/snippet}

{#if href}
  <a class="ib" class:danger={variant === 'danger'} {href} aria-label={spokenName} data-tip={label}>{@render face()}</a>
{:else}
  <button class="ib" class:danger={variant === 'danger'} type="button" aria-label={spokenName} data-tip={label} aria-busy={busy} {disabled} {onclick}>{@render face()}</button>
{/if}

<style>
  a.ib { text-decoration: none; }
  .ib { position: relative; display: inline-flex; align-items: center; justify-content: center; gap: 6px; min-width: 36px; min-height: 36px; padding: 0; background: transparent; color: var(--text); border: 1px solid var(--line); cursor: pointer; }
  .ib:hover:not(:disabled) { border-color: var(--line-strong); background: var(--surface-2); }
  .ib:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .ib:disabled { opacity: 0.45; cursor: not-allowed; }
  .ib[aria-busy='true'] { opacity: 0.75; cursor: progress; }
  .ib.danger { color: var(--danger); border-color: var(--danger-line); }
  .ib.danger:hover:not(:disabled) { background: var(--danger); color: var(--inverse-text); border-color: var(--danger); }
  svg { width: 16px; height: 16px; flex: none; stroke: currentColor; fill: none; stroke-width: 1.5; stroke-linecap: square; }
  .btn-spin { margin: 0; }
  .word { display: none; font-family: var(--mono); font-size: 11px; font-weight: 700; }
  /* No box of its own in the flow: fixed with no offsets stays where the button's centre is, then is lifted above the button. */
  .ib::after { content: attr(data-tip); position: fixed; transform: translateY(calc(-50% - 30px)); width: max-content; max-width: 240px; padding: 4px 8px; background: var(--inverse-bg); color: var(--inverse-text); font-family: var(--mono); font-size: 11px; font-weight: 400; letter-spacing: 0.02em; text-align: center; opacity: 0; pointer-events: none; transition: opacity 0.12s; z-index: 60; }
  .ib:hover::after, .ib:focus-visible::after { opacity: 1; }
  @media (prefers-reduced-motion: reduce) { .ib::after { transition: none; } }
  @media (max-width: 820px) {
    .ib { padding: 0 10px; }
    .word { display: inline; }
    .ib::after { display: none; }
  }
</style>

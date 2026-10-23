<script lang="ts">
  // The square before a row's name: its bundled logo when it has one (drawn as it is, with nothing behind it), else a small outline picture (None, container, VM), else the first letter of its name.
  import { badgeFace } from '../../../lib/createSelects.ts'
  import type { Glyph } from '../../../lib/imageChoices.ts'

  interface Props {
    title: string
    /** The address of the row's logo. */
    logo?: string | undefined
    /** The outline picture for a row without a logo. */
    glyph?: Glyph | undefined
    /** Greyed out, for a row that cannot be picked. */
    muted?: boolean
  }

  let { title, logo, glyph, muted = false }: Props = $props()
  const face = $derived(badgeFace(title, logo))
</script>

<span class="badge" class:muted class:letter={face.kind === 'letter' && glyph === undefined} data-badge={face.kind === 'logo' ? 'logo' : (glyph ?? 'letter')} aria-hidden="true">
  {#if face.kind === 'logo'}
    <img src={face.src} alt="" />
  {:else if glyph === 'none'}
    <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" /><path d="M6.5 17.5l11-11" /></svg>
  {:else if glyph === 'container'}
    <svg viewBox="0 0 24 24"><path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3zM4 7.5l8 4.5 8-4.5M12 12v9" /></svg>
  {:else if glyph === 'vm'}
    <svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="12" /><path d="M8 20h8M12 16v4" /></svg>
  {:else}
    {face.text}
  {/if}
</span>

<style>
  .badge { flex: none; display: inline-grid; place-items: center; width: var(--badge-size, 28px); height: var(--badge-size, 28px); color: var(--m70); }
  .badge.letter { background: var(--inverse-bg); color: var(--inverse-text); font: 700 calc(var(--badge-size, 28px) * .43) var(--mono); }
  .badge.letter.muted { background: var(--reserve-bg); color: var(--m60); }
  img { width: 100%; height: 100%; object-fit: contain; }
  .muted img { opacity: .45; filter: grayscale(1); }
  svg { width: 80%; height: 80%; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
  .muted svg { opacity: .6; }
</style>

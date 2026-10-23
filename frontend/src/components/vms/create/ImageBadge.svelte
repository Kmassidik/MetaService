<script lang="ts">
  // The small square before an image's name: its logo when it has one, else the first letter of its name.
  import { badgeFace } from '../../../lib/createSelects.ts'

  interface Props {
    title: string
    /** The address of the image's logo; the letter is shown without it. */
    logo?: string | undefined
    /** Greyed out, for an image that cannot be picked. */
    muted?: boolean
  }

  let { title, logo, muted = false }: Props = $props()
  const face = $derived(badgeFace(title, logo))
</script>

<span class="badge" class:muted class:has-logo={face.kind === 'logo'} aria-hidden="true">
  {#if face.kind === 'logo'}<img src={face.src} alt="" />{:else}{face.text}{/if}
</span>

<style>
  .badge { flex: none; display: inline-grid; place-items: center; width: 28px; height: 28px; background: var(--inverse-bg); color: var(--inverse-text); font: 700 12px var(--mono); overflow: hidden; }
  .badge.has-logo { background: var(--surface-2); }
  .badge.muted { background: var(--reserve-bg); color: var(--m60); }
  img { width: 100%; height: 100%; object-fit: contain; }
</style>

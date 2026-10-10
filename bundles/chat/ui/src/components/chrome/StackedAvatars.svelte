<script>
  /**
   * Two overlapped bot faces for a group chat, drawn like iMessage
   * group avatars: two flat circles, the front one cut out of the back one by a thin ring.
   */
  import BotAvatar from '../BotAvatar.svelte'

  // `ring` is the surface behind the pair, so the gap between the faces reads as background.
  let { agents = [], size = 36, ring = 'var(--sidebar)' } = $props()

  // Each face is ~68% of the slot so the pair overlaps diagonally inside the same square.
  const FACE_RATIO = 0.68
  const RING_PX = 1.5
  const face = $derived(Math.round(size * FACE_RATIO))
</script>

<span
  class="stacked-avatars"
  style:width={`${size}px`}
  style:height={`${size}px`}
  style:--stack-ring={ring}
  style:--stack-ring-width={`${RING_PX}px`}
  aria-hidden="true"
>
  {#each agents as agent (agent.id)}
    <span class="stacked-face"><BotAvatar {agent} size={face} round /></span>
  {/each}
</span>

<style>
  .stacked-avatars { position: relative; display: inline-block; flex-shrink: 0; }
  .stacked-face { position: absolute; line-height: 0; border-radius: 50%; }
  .stacked-face:first-child { left: 0; top: 0; }
  /* The ring sits outside the front face, so both circles keep their full size. */
  .stacked-face:nth-child(2) {
    right: 0;
    bottom: 0;
    background: var(--stack-ring);
    box-shadow: 0 0 0 var(--stack-ring-width) var(--stack-ring);
  }
</style>

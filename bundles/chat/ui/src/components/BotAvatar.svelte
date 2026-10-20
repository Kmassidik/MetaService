<script lang="ts">
  import type { HTMLAttributes } from 'svelte/elements'
  import type { Agent } from '../lib/types.ts'
  import { avatarSnake } from '../lib/avatars.ts'
  import { DEFAULT_AVATAR_COLOR } from '../lib/constants.ts'

  /**
   * Ruvio bot avatar: one of Ruvi's plush snakes, picked by the bot's avatar colour.
   * `round` puts the snake on a disc in the page colour so stacked group faces overlap cleanly, iMessage style.
   */
  interface Props extends HTMLAttributes<HTMLSpanElement> {
    agent?: Pick<Agent, 'avatarColor'> | null | undefined
    color?: string
    size?: number
    round?: boolean
    class?: string
  }

  let {
    agent = null,
    color = DEFAULT_AVATAR_COLOR,
    size = 30,
    round = false,
    class: className = '',
    ...rest
  }: Props = $props()

  const snake = $derived(avatarSnake(agent?.avatarColor || color))
</script>

<span
  class="bot-face {className}"
  class:bot-avatar={true}
  class:round
  style={`width:${size}px;height:${size}px`}
  aria-hidden="true"
  {...rest}
>
  <img src={snake.src} alt="" width={size} height={size} decoding="async" draggable="false" />
</span>

<style>
  .bot-face {
    display: inline-grid;
    place-items: center;
    flex-shrink: 0;
    line-height: 0;
  }
  /* The snakes have transparent backgrounds, so any row or bubble colour shows through. */
  .bot-face img {
    display: block;
    width: 100%;
    height: 100%;
    user-select: none;
  }
  .bot-face.round {
    border-radius: 50%;
    overflow: hidden;
    background: var(--page);
  }
</style>

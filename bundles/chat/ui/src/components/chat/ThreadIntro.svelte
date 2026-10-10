<script>
  import BotAvatar from '../BotAvatar.svelte'

  // Shown in a bot's chat before the first message.
  const INTRO_AVATAR_SIZE = 64
  // New bots start with setup instructions the owner never wrote; those aren't shown as a blurb.
  const SETUP_PROMPT_PREFIX = 'You are a new Ruvio bot'
  let { active } = $props()
  const blurb = $derived(!active.description || active.description.startsWith(SETUP_PROMPT_PREFIX)
    ? `Message ${active.name} to get started.`
    : active.description)
</script>

<section class="intro">
  <BotAvatar agent={active} size={INTRO_AVATAR_SIZE} /><h2>Ready when you are</h2><p>{blurb}</p>
</section>

<style>
  .intro { display: flex; flex-direction: column; align-items: center; gap: 10px; max-width: 440px; margin: 48px auto; text-align: center; }
  h2 { margin: 6px 0 0; color: var(--text); font: 600 20px/1.35 var(--font); }
  p { margin: 0; color: var(--text-2); font: 400 15px/1.5 var(--font); white-space: pre-wrap; overflow-wrap: anywhere; }
</style>

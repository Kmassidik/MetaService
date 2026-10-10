<script>
  import BotAvatar from '../BotAvatar.svelte'
  import { DEFAULT_AVATAR_COLOR, DEFAULT_AVATAR_SHAPE } from '../../lib/constants.js'

  // First run: a friendly face and one black pill. The bot itself offers starter ideas.
  const HERO_AVATAR_SIZE = 64

  let {
    greeting = 'there',
    saving = false,
    createError = '',
    blockReason = '',
    storageLoading = false,
    loadStorage,
    startNewBot,
  } = $props()

  const hero = { id: 'ruvio-welcome', avatarShape: DEFAULT_AVATAR_SHAPE, avatarColor: DEFAULT_AVATAR_COLOR }
</script>

<section class="empty">
  <BotAvatar agent={hero} size={HERO_AVATAR_SIZE} />
  <h2>Create your first bot</h2>
  <p>Welcome, {greeting}. Each bot has its own face, memory and a private computer it can use for you.</p>
  <button type="button" class="primary-button cta" disabled={saving || Boolean(blockReason)} onclick={startNewBot}>{saving ? 'Opening…' : 'New bot'}</button>
  {#if blockReason}
    <p class="reason" role="status">{blockReason}</p>
    <button type="button" class="quiet" disabled={storageLoading} onclick={loadStorage}>Check again</button>
  {/if}
  {#if createError}<p class="reason error" role="alert">{createError}</p>{/if}
</section>

<style>
  .empty { display: flex; flex-direction: column; align-items: center; width: 100%; max-width: 520px; margin: auto; padding: 56px 24px; text-align: center; }
  h2 { margin: 18px 0 8px; color: var(--text); font: 600 24px/1.3 var(--font); }
  p { margin: 0; max-width: 400px; color: var(--text-2); font: 400 15px/1.5 var(--font); }
  .cta { margin-top: 22px; min-height: 44px; padding: 10px 28px; font-size: 15px; }
  .reason { margin-top: 12px; font-size: var(--fs-preview); }
  .error { color: var(--danger); }
  .quiet { margin-top: 6px; border: 0; background: none; color: var(--text-2); font: 500 var(--fs-preview)/1.4 var(--font); text-decoration: underline; text-underline-offset: 3px; cursor: pointer; }
</style>

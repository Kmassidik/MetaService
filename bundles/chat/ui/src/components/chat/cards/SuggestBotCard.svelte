<script>
  import Card from './Card.svelte'
  import BotAvatar from '../../BotAvatar.svelte'

  // The bot suggests creating a specialist bot.
  const AVATAR_SIZE = 36
  let { card, busy = false, limitReached = false, onResolve } = $props()
  const preview = $derived({ id: card.name, name: card.name, avatarShape: card.avatarShape, avatarColor: card.avatarColor })
</script>

<Card label={`Suggested bot: ${card.name}`} title={card.reason ? '' : 'A bot for this'} reason={card.reason}>
  <div class="suggested">
    <BotAvatar agent={preview} size={AVATAR_SIZE} />
    <span><strong>{card.name}</strong>{#if card.title}<small>{card.title}</small>{/if}</span>
  </div>
  {#if limitReached}<p class="limit">You’ve reached your bot limit. Delete a bot to make room.</p>{/if}
  {#snippet actions()}
    <button type="button" class="primary-button" disabled={busy || limitReached} onclick={() => onResolve('create')}>Create</button>
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onResolve('dismiss')}>Not now</button>
  {/snippet}
</Card>

<style>
  .suggested { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border-radius: 12px; background: var(--page); }
  .suggested span { display: grid; min-width: 0; }
  strong { font: 500 var(--fs-name)/1.3 var(--font); }
  small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-2); font: 400 var(--fs-preview)/1.35 var(--font); }
  .limit { margin: 0; color: var(--text-2); font: 400 13px/1.45 var(--font); }
</style>

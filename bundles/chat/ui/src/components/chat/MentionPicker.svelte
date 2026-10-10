<script>
  import Icon from '../Icon.svelte'
  import BotAvatar from '../BotAvatar.svelte'
  import PickerShell from './PickerShell.svelte'

  const AVATAR_SIZE = 28
  let {
    open = false,
    query = $bindable(''),
    bots = [],
    routines = [],
    connectors = [],
    busy = false,
    pending = false,
    everyone = false,
    onSelect,
    onClose,
  } = $props()

  const locked = $derived(busy || pending)
  const nothing = $derived(!bots.length && !routines.length && !connectors.length)
</script>

{#if open}
  <PickerShell label="Mention" placeholder="Search bots, routines, apps…" bind:query {onClose}>
    {#if everyone}
      <button type="button" class="picker-option" role="option" aria-selected="false" disabled={locked} onclick={() => onSelect('everyone')}>
        <span class="picker-glyph"><Icon name="at" size={16} /></span>
        <span><strong>everyone</strong><small>Notify all bots in this group</small></span>
      </button>
    {/if}
    {#each bots as bot (bot.id)}
      <button type="button" class="picker-option" role="option" aria-selected="false" disabled={locked} onclick={() => onSelect(bot.id)}>
        <BotAvatar agent={bot} size={AVATAR_SIZE} />
        <span><strong>{bot.name}</strong>{#if bot.title}<small>{bot.title}</small>{/if}</span>
      </button>
    {/each}
    {#if routines.length}
      <p class="picker-heading">Routines</p>
      {#each routines as routine (routine.id)}
        <button type="button" class="picker-option" role="option" aria-selected="false" disabled={locked} onclick={() => onSelect(`routine:${routine.id}`)}>
          <span class="picker-glyph"><Icon name="clock" size={16} /></span>
          <span><strong>{routine.title}</strong><small>{routine.triggerKind || 'schedule'} · {routine.state}</small></span>
        </button>
      {/each}
    {/if}
    {#if connectors.length}
      <p class="picker-heading">Apps</p>
      {#each connectors as connector (connector.id)}
        <button type="button" class="picker-option" role="option" aria-selected="false" disabled={locked} onclick={() => onSelect(`connector:${connector.id}`)}>
          <span class="picker-glyph"><Icon name="plug" size={16} /></span>
          <span><strong>{connector.name}</strong><small>Connected app</small></span>
        </button>
      {/each}
    {/if}
    {#if nothing}<p class="picker-empty">Nothing to mention yet. Add another bot, a routine or an app.</p>{/if}
  </PickerShell>
{/if}

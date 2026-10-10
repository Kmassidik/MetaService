<script>
  import Icon from '../Icon.svelte'

  // Whole-pane states for a bot whose chat can't be shown: setup failed, loading, or a load error.
  let { view, active, error = '', onManage, onReload } = $props()
</script>

<section class="bot-status">
  {#if view === 'failed'}
    <Icon name="shield" size={30} /><h2>This bot could not be prepared</h2>
    <p role="alert">{active.lastError || 'Private-computer setup failed. Delete this bot and try again.'}</p>
    <button class="secondary-button" onclick={onManage}>Manage bot</button>
  {:else if view === 'loading'}
    <div class="spinner"></div><p>Loading your conversation…</p>
  {:else}
    <Icon name="chat" size={30} /><h2>Let’s reconnect.</h2><p role="alert">{error}</p>
    <button class="secondary-button" onclick={onReload}><Icon name="refresh" size={16} />Reload conversation</button>
  {/if}
</section>

<style>
  .bot-status { display: flex; flex-direction: column; align-items: center; gap: 10px; max-width: 440px; margin: auto; padding: 56px 24px; text-align: center; color: var(--text-2); }
  h2 { margin: 6px 0 0; color: var(--text); font: 600 20px/1.35 var(--font); }
  p { margin: 0; font: 400 15px/1.5 var(--font); overflow-wrap: anywhere; }
  .secondary-button { margin-top: 10px; }
</style>

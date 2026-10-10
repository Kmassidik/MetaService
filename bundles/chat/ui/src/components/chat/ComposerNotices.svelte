<script>
  // Problems and blockers that affect sending, stacked just above the composer.
  let {
    selectedId = '',
    runErrors = {},
    runActionErrors = $bindable({}),
    historyError = '',
    historyReloadDisabled = false,
    // Why the last New bot couldn't be opened (a limit or storage); dismissable.
    createError = $bindable(''),
    usageBlocked = false,
    otherBotBusy = false,
    takingOver = false,
    // While the computer panel is open it already says you're in control, so this notice steps aside.
    computerOpen = false,
    attachmentErrors = $bindable({}),
    mentionError = $bindable(''),
    onReconnect,
    onReloadHistory,
    onOpenComputer,
  } = $props()

  function clearFor(map) {
    return { ...map, [selectedId]: '' }
  }
</script>

{#snippet problem(text, action, run, disabled = false)}
  <div class="notice problem" role="alert"><span>{text}</span><button type="button" {disabled} onclick={run}>{action}</button></div>
{/snippet}

<div class="notices">
  {#if runErrors[selectedId]}{@render problem(runErrors[selectedId], 'Reconnect', onReconnect)}{/if}
  {#if runActionErrors[selectedId]}{@render problem(runActionErrors[selectedId], 'Dismiss', () => runActionErrors = clearFor(runActionErrors))}{/if}
  {#if historyError}{@render problem(historyError, 'Reload history', onReloadHistory, historyReloadDisabled)}{/if}
  {#if attachmentErrors[selectedId]}{@render problem(attachmentErrors[selectedId], 'Dismiss', () => attachmentErrors = clearFor(attachmentErrors))}{/if}
  {#if createError}{@render problem(createError, 'Dismiss', () => createError = '')}{/if}
  {#if mentionError}{@render problem(mentionError, 'Dismiss', () => mentionError = '')}{/if}
  {#if usageBlocked}<div class="notice" role="status">Your usage allowance is used up for now. Check Settings for details.</div>{/if}
  {#if otherBotBusy}<div class="notice" role="status">Another bot is working. You can send when it finishes.</div>{/if}
  {#if takingOver && !computerOpen}<div class="notice" role="status"><span>You have control of the computer.</span><button type="button" onclick={onOpenComputer}>Open computer</button></div>{/if}
</div>

<style>
  .notices { display: grid; gap: 6px; margin-bottom: 8px; }
  .notices:empty { display: none; }
  .notice {
    display: flex; align-items: center; justify-content: center; gap: 10px; padding: 8px 14px;
    border-radius: var(--radius-control); color: var(--text-2); font: 400 var(--fs-preview)/1.4 var(--font); text-align: center;
  }
  .problem { justify-content: space-between; background: var(--danger-bg); color: var(--danger); text-align: left; }
  button { flex-shrink: 0; padding: 2px 8px; border: 0; border-radius: var(--radius-item); background: transparent; color: inherit; font: 600 13px/1.4 var(--font); text-decoration: underline; text-underline-offset: 3px; cursor: pointer; }
  button:disabled { opacity: .5; cursor: default; }
</style>

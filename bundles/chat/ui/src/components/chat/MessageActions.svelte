<script>
  import Icon from '../Icon.svelte'

  // Hover toolbar beside a bubble: react, reply in thread, and copy/export.
  const NOTICE_MS = 1400
  const EXPORT_URL_LIFETIME_MS = 1000
  const EXPORT_FILENAME = 'message.md'

  let { message, picking = false, replying = false, forceVisible = false, onReact, onReply } = $props()
  let menuOpen = $state(false)
  let notice = $state('')

  function flash(text) {
    notice = text
    setTimeout(() => { notice = '' }, NOTICE_MS)
  }

  async function copyText() {
    menuOpen = false
    try {
      await navigator.clipboard.writeText(message.text || '')
      flash('Copied')
    } catch (error) {
      flash(`Couldn’t copy: ${error.message || 'clipboard unavailable'}`)
    }
  }

  function exportMarkdown() {
    menuOpen = false
    const url = URL.createObjectURL(new Blob([message.text || ''], { type: 'text/markdown;charset=utf-8' }))
    const link = document.createElement('a')
    link.href = url
    link.download = EXPORT_FILENAME
    link.click()
    setTimeout(() => URL.revokeObjectURL(url), EXPORT_URL_LIFETIME_MS)
  }
</script>

<div class="actions" class:visible={forceVisible || menuOpen || picking || replying || notice}>
  <button type="button" class="action" class:active={picking} aria-label="React" title="React" aria-expanded={picking} onclick={onReact}><Icon name="smile" size={16} /></button>
  <button type="button" class="action" class:active={replying} aria-label="Reply in thread" title="Reply" aria-pressed={replying} onclick={onReply}><Icon name="reply" size={16} /></button>
  <div class="more">
    <button type="button" class="action" aria-label="More message actions" title="More" aria-expanded={menuOpen} onclick={() => menuOpen = !menuOpen}><Icon name="more" size={16} /></button>
    {#if menuOpen}
      <div class="menu" role="menu">
        <button type="button" role="menuitem" onclick={copyText}>Copy text</button>
        <button type="button" role="menuitem" onclick={exportMarkdown}>Export Markdown</button>
      </div>
    {/if}
  </div>
  {#if notice}<span class="notice" role="status">{notice}</span>{/if}
</div>

<style>
  .actions { display: flex; align-items: center; gap: 2px; opacity: 0; transition: opacity .12s ease; }
  .actions.visible, :global(.bubble-row:hover) .actions, :global(.bubble-row:focus-within) .actions { opacity: 1; }
  .action { display: grid; place-items: center; width: 28px; height: 28px; padding: 0; border: 0; border-radius: var(--radius-pill); background: transparent; color: var(--text-2); cursor: pointer; }
  .action:hover, .action.active { background: var(--row-hover); color: var(--text); }
  .action:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 1px; }
  .more { position: relative; }
  .menu { position: absolute; top: calc(100% + 4px); right: 0; z-index: 20; min-width: 170px; padding: 6px; border: 1px solid var(--hairline); border-radius: var(--radius-menu); background: var(--surface); box-shadow: var(--shadow-float); }
  .menu button { display: block; width: 100%; padding: 8px 10px; border: 0; border-radius: var(--radius-item); background: transparent; color: var(--text); text-align: left; font: 400 var(--fs-menu)/1.3 var(--font); cursor: pointer; }
  .menu button:hover { background: var(--row-hover); }
  .notice { margin-left: 4px; color: var(--text-2); font: 400 var(--fs-time)/1.3 var(--font); white-space: nowrap; }
  @media (prefers-reduced-motion: reduce) { .actions { transition: none; } }
</style>

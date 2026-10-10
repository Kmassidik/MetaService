<script>
  import { onDestroy } from 'svelte'
  import { Marked } from 'marked'
  import DOMPurify from 'dompurify'
  import hljs from 'highlight.js/lib/common'
  import Icon from './Icon.svelte'

  let { text = '', showActions = true } = $props()
  let source = $state(false)
  let copyStatus = $state('')
  const exportUrls = new Set()
  onDestroy(() => { for (const url of exportUrls) URL.revokeObjectURL(url) })
  const escape = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;')
  const parser = new Marked({
    gfm: true,
    renderer: {
      html({ text }) { return escape(text) },
      image({ text }) { return escape(text || 'Image: use the attached file to preview') },
      link({ href, text, tokens }) {
        const label = tokens ? this.parser.parseInline(tokens) : escape(text)
        // Generated prose cannot invent authenticated download URLs or navigate local mutation routes.
        if (!/^https?:\/\//i.test(href) && !/^mailto:/i.test(href)) return label
        try { if (new URL(href, window.location.href).origin === window.location.origin) return label } catch { return label }
        return `<a href="${escape(href)}" target="_blank" rel="noopener noreferrer">${label}</a>`
      },
      code({ text, lang }) {
        const language = (lang || '').split(/\s/)[0]
        const code = hljs.getLanguage(language) ? hljs.highlight(text, { language, ignoreIllegals: true }).value : escape(text)
        return `<pre><code class="hljs">${code}</code></pre>`
      },
    },
  })
  const html = $derived(DOMPurify.sanitize(parser.parse(text), {
    ALLOWED_TAGS: ['p', 'br', 'hr', 'strong', 'em', 'del', 'blockquote', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'code', 'span', 'a', 'table', 'thead', 'tbody', 'tr', 'th', 'td'],
    ALLOWED_ATTR: ['href', 'target', 'rel', 'class', 'start', 'align'],
    ALLOW_DATA_ATTR: false,
  }))
  async function copy() {
    try { await navigator.clipboard.writeText(text); copyStatus = 'Copied' }
    catch { copyStatus = 'Copy failed. Select the source text to copy.' }
    setTimeout(() => { if (copyStatus === 'Copied') copyStatus = '' }, 1600)
  }
  function exportSource() {
    const url = URL.createObjectURL(new Blob([text], { type: 'text/markdown;charset=utf-8' }))
    exportUrls.add(url)
    const link = document.createElement('a')
    link.href = url; link.download = 'message.md'; link.click()
    setTimeout(() => { URL.revokeObjectURL(url); exportUrls.delete(url) }, 1000)
  }
</script>

<div class="markdown">{@html html}</div>
{#if text && showActions}
  <div class="message-source-actions">
    <button class="msg-icon-btn" type="button" aria-label={source ? 'Hide source' : 'Show source'} title={source ? 'Hide source' : 'Source'} aria-expanded={source} onclick={() => source = !source}><Icon name="code" size={15} /></button>
    <button class="msg-icon-btn" type="button" aria-label="Copy text" title="Copy text" onclick={copy}><Icon name="copy" size={15} /></button>
    <button class="msg-icon-btn" type="button" aria-label="Export Markdown" title="Export Markdown" onclick={exportSource}><Icon name="download" size={15} /></button>
    {#if copyStatus}<span class="msg-action-status" role="status">{copyStatus}</span>{/if}
  </div>
  {#if source}<textarea class="message-source source-review" aria-label="Message Markdown source" readonly rows="8" value={text}></textarea>{/if}
{/if}

<style>
  /* Message markdown on the calm tokens; only code keeps a monospace font. */
  .markdown { line-height: var(--lh-message); overflow-wrap: anywhere; }
  .markdown :global(p), .markdown :global(ul), .markdown :global(ol), .markdown :global(blockquote) { margin: 0 0 8px; }
  .markdown :global(> :last-child) { margin-bottom: 0; }
  .markdown :global(ul), .markdown :global(ol) { padding-left: 22px; }
  .markdown :global(li + li) { margin-top: 2px; }
  .markdown :global(h1), .markdown :global(h2), .markdown :global(h3) { margin: 14px 0 6px; font-family: var(--font); font-weight: 600; line-height: 1.35; }
  .markdown :global(h1) { font-size: 20px; }
  .markdown :global(h2) { font-size: 18px; }
  .markdown :global(h3) { font-size: 16px; }
  .markdown :global(a) { color: inherit; text-decoration: underline; text-underline-offset: 3px; }
  .markdown :global(blockquote) { padding-left: 12px; border-left: 3px solid var(--hairline); color: var(--text-2); }
  .markdown :global(pre) { margin: 8px 0; padding: 12px 14px; border: 1px solid var(--hairline); border-radius: 12px; background: var(--page); font: 13px/1.55 var(--font-code); }
  .markdown :global(code) { padding: 1px 5px; border-radius: 6px; background: var(--tint-hover); font-family: var(--font-code); font-size: .88em; }
  .markdown :global(pre code) { padding: 0; background: none; font-size: inherit; }
  .markdown :global(table) { border-radius: var(--radius-item); font-size: 14px; }
  .markdown :global(th), .markdown :global(td) { border-color: var(--hairline); }
</style>

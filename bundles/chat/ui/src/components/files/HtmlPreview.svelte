<script>
  /** Static, sanitized HTML in a sandboxed frame (no scripts, styles, forms, links or network). */
  import SourceView from './SourceView.svelte'

  let { content, name } = $props()
</script>

<p class="file-meta">Sanitized static HTML. Scripts, styles, forms, links, embeds and network resources are removed.</p>
<iframe class="html-frame" title={`Sanitized static preview of ${name}`} sandbox="" referrerpolicy="no-referrer" srcdoc={content.html}></iframe>
<SourceView source={content.source} {name} />

<style>
  .html-frame { display: block; width: 100%; min-height: 60dvh; margin-top: 12px; border: 1px solid var(--hairline); background: var(--paper); }
</style>

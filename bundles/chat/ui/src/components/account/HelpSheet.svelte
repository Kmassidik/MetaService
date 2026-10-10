<script>
  /** Help: how files and messages work, their limits, and shortcuts to upload or browse files. */
  import Icon from '../Icon.svelte'
  import { chat, closeModal, openFiles } from '../../lib/chatApp.svelte.js'

  let { uploadLocked = false } = $props()

  function upload() {
    closeModal()
    chat.fileChooser?.click()
  }

  function browseFiles() {
    closeModal()
    openFiles()
  }
</script>

<h2>Help</h2>
<div class="tool-actions">
  <button class="secondary-button" disabled={uploadLocked} onclick={upload}><Icon name="plus" size={18} />Upload files</button>
  <button class="secondary-button" onclick={browseFiles}><Icon name="folder" size={18} />Saved files & results</button>
</div>
<p class="form-help">Drop files or paste images into your message. Up to 25 MiB per file, 10 files and 100 MiB per message. Removing an attachment from a message keeps the saved file.</p>
<p class="form-help">Messages support 16,000 UTF-8 bytes. Shift + Enter adds a new line. Cmd/Ctrl + F finds text in the chat. Auto selects Astra or Grok for each task. AI can make mistakes; review important results.</p>

<style>
  .tool-actions { display: flex; flex-wrap: wrap; gap: 10px; margin: 20px 0; }
</style>

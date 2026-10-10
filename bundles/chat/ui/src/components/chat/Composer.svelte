<script>
  import Icon from '../Icon.svelte'
  import ComposerPlusMenu from './ComposerPlusMenu.svelte'
  import ComposerAttachments from './ComposerAttachments.svelte'
  import { composerTrigger, withoutTrigger } from './composerTriggers.js'
  import { bytes } from '../../lib/format.js'

  // One pill — [+] [text] [mic] [send].
  const MAX_MESSAGE_BYTES = 16000
  const BYTE_WARNING_AT = 14000
  const MAX_VISIBLE_LINES = 6

  let {
    botName = '',
    selectedId = '',
    draft = '',
    drafts = $bindable({}),
    composer = $bindable(null),
    fileChooser = $bindable(null),
    attachments = $bindable({}),
    selectedAttachments = [],
    selectedUploads = [],
    canSend = false,
    sending = false,
    locked = false,
    // The bot is working: Send queues text on its task, and files wait until it finishes.
    followUp = false,
    toolsDisabled = false,
    dictationSupported = false,
    dictating = false,
    sendMessage,
    composerKey,
    pasteImages,
    dropFiles,
    uploadFiles,
    cancelUpload,
    toggleDictation,
    onSkillTrigger,
    onMentionTrigger,
    menuActions,
  } = $props()

  let menuOpen = $state(false)
  const placeholder = $derived(followUp ? `Message ${botName} · files later` : `Message ${botName}`)
  const sendLabel = $derived(sendLabelNow())

  function sendLabelNow() {
    if (sending) return 'Waiting for response'
    if (selectedUploads.length) return 'Wait for uploads before sending'
    if (followUp && selectedAttachments.length) return 'Files can be sent after it finishes'
    return 'Send message'
  }

  function setDraft(value) {
    drafts = { ...drafts, [selectedId]: value }
  }

  // A sent draft clears the box; shrink it back to one line too.
  $effect(() => {
    if (!draft && composer) composer.style.height = ''
  })

  function fitHeight(field) {
    const lineHeight = parseFloat(getComputedStyle(field).lineHeight)
    field.style.height = 'auto'
    field.style.height = `${Math.min(field.scrollHeight, lineHeight * MAX_VISIBLE_LINES)}px`
  }

  function openTriggeredPicker(field, trigger) {
    // Set the field too: when the draft was empty it stays empty, so Svelte wouldn't repaint it.
    field.value = withoutTrigger(field.value, field.selectionStart)
    setDraft(field.value)
    if (trigger === 'skill') onSkillTrigger()
    else onMentionTrigger()
  }

  function handleInput(event) {
    const field = event.currentTarget
    const trigger = composerTrigger(field.value, field.selectionStart, event.data)
    if (trigger && !toolsDisabled) openTriggeredPicker(field, trigger)
    else setDraft(field.value)
    fitHeight(field)
  }

  function removeAttachment(file) {
    attachments = { ...attachments, [selectedId]: selectedAttachments.filter(item => item.id !== file.id) }
  }

  function chooseFiles(event) {
    uploadFiles(event.currentTarget.files)
    event.currentTarget.value = ''
  }
</script>

<form class="composer-box" aria-label="Message and file composer" onsubmit={sendMessage} ondragover={event => event.preventDefault()} ondrop={dropFiles}>
  <ComposerAttachments files={selectedAttachments} uploads={selectedUploads} {locked} onRemove={removeAttachment} onCancel={cancelUpload} />
  <div class="composer-line">
    <div class="plus-anchor">
      <button class="round-button plus" type="button" aria-label="Message tools" aria-haspopup="menu" aria-expanded={menuOpen} title="Attach and tools" onclick={() => menuOpen = !menuOpen}><Icon name="plus" size={20} /></button>
      <ComposerPlusMenu bind:open={menuOpen} attachDisabled={locked || followUp} {toolsDisabled} {...menuActions} onAttach={() => fileChooser?.click()} />
    </div>
    <textarea bind:this={composer} aria-label={`Message ${botName}`} {placeholder} rows="1" maxlength={MAX_MESSAGE_BYTES} value={draft} oninput={handleInput} onkeydown={composerKey} onpaste={pasteImages}></textarea>
    {#if dictationSupported}
      <button class="round-button" type="button" class:dictating aria-label={dictating ? 'Stop dictation' : 'Dictate'} title={dictating ? 'Stop dictation' : 'Dictate'} disabled={locked} onclick={toggleDictation}><Icon name="mic" size={19} /></button>
    {/if}
    <button class="send" type="submit" disabled={!canSend} aria-label={sendLabel} title={sendLabel}>
      {#if sending}<span class="tiny-spinner"></span>{:else}<Icon name="arrow" size={18} />{/if}
    </button>
  </div>
  <input bind:this={fileChooser} type="file" multiple hidden onchange={chooseFiles} />
</form>
{#if bytes(draft) > BYTE_WARNING_AT}<p class="byte-count" role="status">{bytes(draft)} / {MAX_MESSAGE_BYTES} bytes</p>{/if}

<style>
  .composer-box {
    display: flex; flex-direction: column; width: 100%;
    padding: 4px; border: 1px solid var(--hairline); border-radius: var(--radius-composer);
    background: var(--surface); box-shadow: var(--shadow-float);
  }
  .composer-line { display: flex; align-items: flex-end; gap: 4px; min-height: 34px; }
  .plus-anchor { position: relative; flex-shrink: 0; }
  textarea {
    flex: 1; min-width: 0; min-height: 34px;
    padding: 6px 4px; border: 0; outline: none; resize: none;
    background: transparent; color: var(--text);
    font: 400 var(--fs-message)/1.45 var(--font);
  }
  /* One line even when the hint is long (phones): never grow the pill for a placeholder. */
  textarea::placeholder { color: var(--text-2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  textarea:focus-visible { outline: none; }
  .round-button {
    display: grid; place-items: center; flex-shrink: 0; width: 34px; height: 34px; padding: 0;
    border: 0; border-radius: var(--radius-pill);
    background: transparent; color: var(--text-2); cursor: pointer;
  }
  .round-button:hover:not(:disabled) { background: var(--row-hover); color: var(--text); }
  /* Reference: the + sits in its own hairline circle; the mic stays bare. */
  .round-button.plus { border: 1px solid var(--hairline); color: var(--text); }
  .round-button.dictating { background: var(--row-selected); color: var(--text); }
  .send {
    display: grid; place-items: center; flex-shrink: 0; width: 34px; height: 34px; padding: 0;
    border: 0; border-radius: var(--radius-pill);
    background: var(--ink); color: var(--on-ink); cursor: pointer;
  }
  .send:disabled { background: var(--row-selected); color: var(--text-3); cursor: default; }
  .round-button:focus-visible, .send:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .byte-count { margin: 6px 0 0; text-align: center; color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  @media (max-width: 820px) { textarea { font-size: 16px; } }
</style>

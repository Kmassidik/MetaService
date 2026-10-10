<script>
  import Markdown from '../Markdown.svelte'
  import BotAvatar from '../BotAvatar.svelte'
  import MessageFiles from './MessageFiles.svelte'
  import MessageActions from './MessageActions.svelte'
  import MessageReactions from './MessageReactions.svelte'
  import MessageThread from './MessageThread.svelte'
  import ReplySteps from './steps/ReplySteps.svelte'
  import { time } from '../../lib/format.js'

  // One message: gray bubble for the bot, black for you.
  const GROUP_AVATAR_SIZE = 28
  const LONG_PRESS_MS = 500

  let {
    message,
    sender,
    showSender = false,
    groupStart = true,
    matched = false,
    replies = [],
    steps = [],
    replyOpen = false,
    replyDraft = '',
    onReact,
    onToggleReply,
    onReplyDraft,
    onSendReply,
    onViewResults,
  } = $props()

  let picking = $state(false)
  let pressed = $state(false)
  let pressTimer = null
  let row = $state(null)
  const mine = $derived(message.role === 'user')

  // A long-pressed toolbar stays until the person taps somewhere else.
  $effect(() => {
    if (!pressed) return
    window.addEventListener('pointerdown', releaseOutside)
    return () => window.removeEventListener('pointerdown', releaseOutside)
  })

  $effect(() => () => clearTimeout(pressTimer))

  function releaseOutside(event) {
    if (row?.contains(event.target)) return
    pressed = false
  }

  function react(emoji) {
    picking = false
    pressed = false
    onReact(message.id, emoji)
  }

  // Phones have no hover, so a long press reveals the toolbar instead.
  function startPress(event) {
    if (event.pointerType !== 'touch') return
    pressTimer = setTimeout(() => { pressed = true }, LONG_PRESS_MS)
  }

  function endPress() {
    clearTimeout(pressTimer)
  }
</script>

<article bind:this={row} id={`message-${message.id}`} class="message-row" class:mine class:group-start={groupStart} class:matched aria-label={mine ? 'Your message' : `Message from ${sender.name}`}>
  {#if showSender}
    <div class="sender"><BotAvatar agent={sender} size={GROUP_AVATAR_SIZE} /><span>{sender.name}</span></div>
  {/if}
  <div class="bubble-row" role="presentation" onpointerdown={startPress} onpointerup={endPress} onpointercancel={endPress} onpointerleave={endPress}>
    <div class="bubble" title={time(message.createdAt)}>
      {#if mine}<div class="plain">{message.text}</div>{:else}<Markdown text={message.text || ''} showActions={false} />{/if}
    </div>
    <MessageActions {message} {picking} replying={replyOpen} forceVisible={pressed} onReact={() => picking = !picking} onReply={onToggleReply} />
  </div>
  <MessageFiles items={message.attachments || []} {onViewResults} />
  {#if !mine}<ReplySteps {steps} />{/if}
  <MessageReactions reactions={message.reactions || []} {picking} onToggle={react} />
  <MessageThread {replies} open={replyOpen} draft={replyDraft} onToggle={onToggleReply} onDraft={onReplyDraft} onSend={onSendReply} />
</article>

<style>
  .message-row { display: flex; flex-direction: column; align-items: flex-start; margin-top: 4px; }
  .message-row.group-start { margin-top: 12px; }
  .message-row.mine { align-items: flex-end; }
  .sender { display: flex; align-items: center; gap: 8px; margin: 4px 0 6px; color: var(--text-2); font: 500 var(--fs-preview)/1.3 var(--font); }
  .bubble-row { display: flex; align-items: center; gap: 6px; max-width: 100%; }
  .mine .bubble-row { flex-direction: row-reverse; }
  .bubble {
    min-width: 0; max-width: min(560px, calc(100vw - 96px));
    padding: 12px 16px; border-radius: var(--radius-bubble);
    background: var(--bubble); color: var(--text);
    font: 400 var(--fs-message)/var(--lh-message) var(--font); overflow-wrap: anywhere;
  }
  .mine .bubble { background: var(--ink); color: var(--on-ink); }
  .matched .bubble { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .plain { white-space: pre-wrap; tab-size: 2; }
</style>

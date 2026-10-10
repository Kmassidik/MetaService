<script>
  import MessageBubble from './MessageBubble.svelte'
  import { layoutMessages } from './messageLayout.js'

  // Centered time dividers, same-speaker grouping, and threads under their parents.
  let {
    messages = [],
    threadReplies = [],
    active,
    matchedMessageId = undefined,
    // Message id → the steps of the run it answered ("Show steps").
    replySteps = {},
    replyParent = $bindable(''),
    replyDrafts = $bindable({}),
    toggleReaction,
    sendThreadReply,
    onViewResults,
  } = $props()

  const rows = $derived(layoutMessages(messages))
  const isGroup = $derived(active.kind === 'team')

  function repliesTo(id) {
    return threadReplies.filter(reply => reply.parentId === id)
  }

  function toggleReply(id) {
    replyParent = replyParent === id ? '' : id
  }

  function setReplyDraft(id, value) {
    replyDrafts = { ...replyDrafts, [id]: value }
  }
</script>

{#each rows as { message, divider, groupStart } (message.id)}
  {#if divider}<p class="divider">{divider}</p>{/if}
  {#if message.role === 'system'}
    <p class="system-note" id={`message-${message.id}`}>{message.text}</p>
  {:else}
    <MessageBubble
      {message}
      sender={active}
      showSender={isGroup && groupStart && message.role !== 'user'}
      {groupStart}
      matched={matchedMessageId === message.id}
      replies={repliesTo(message.id)}
      steps={replySteps[message.id]}
      replyOpen={replyParent === message.id}
      replyDraft={replyDrafts[message.id] || ''}
      onReact={toggleReaction}
      onToggleReply={() => toggleReply(message.id)}
      onReplyDraft={value => setReplyDraft(message.id, value)}
      onSendReply={() => sendThreadReply(message.id)}
      {onViewResults}
    />
  {/if}
{/each}

<style>
  .divider { margin: 20px 0 8px; text-align: center; color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  .system-note { margin: 14px 12px; text-align: center; color: var(--text-2); font: 400 13px/1.45 var(--font); }
</style>

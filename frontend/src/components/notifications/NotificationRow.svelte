<script lang="ts">
  // One notification: what happened (kind, title, detail), where, when, and the buttons to open the VM or machine it names and to mark it read.
  // Every text is drawn as plain text; an unread one has a bar and bold title.
  import { kindWords, targetHref, targetName, titleOf } from '../../lib/notifications.ts'
  import type { Notification } from '../../lib/notificationsParse.ts'
  import type { TimeFormat } from '../../lib/securityTime.ts'

  let { item, time, onRead }: { item: Notification; time: TimeFormat; onRead: (item: Notification) => void } = $props()
  const words = $derived(kindWords(item.kind))
  const href = $derived(targetHref(item))
  const where = $derived(targetName(item))
</script>

<li class="note" class:unread={!item.read} data-kind={item.kind} data-id={item.id}>
  <div class="head">
    <span class="tag {words.tone}">{words.label}</span>
    <b class="title">{titleOf(item)}</b>
    <time class="when" title={time.title(item.createdAt)}>{time.show(item.createdAt)}</time>
  </div>
  {#if item.detail}<p class="detail">{item.detail}</p>{/if}
  <div class="foot">
    {#if where}<span class="where">{where}</span>{/if}
    <span class="acts">
      {#if href}<a class="btn line sm" {href} data-testid="open-target" onclick={() => onRead(item)}>Open</a>{/if}
      {#if !item.read}<button class="btn line sm" type="button" data-testid="mark-read" onclick={() => onRead(item)}>Mark read</button>{/if}
    </span>
  </div>
</li>

<style>
  .note { display: grid; gap: 6px; padding: 12px 16px; border-top: 1px solid var(--line); border-left: 4px solid transparent; min-width: 0; }
  .note:first-child { border-top: 0; }
  .note.unread { border-left-color: var(--accent-mark); background: var(--warn-bg); }
  .head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 10px; }
  .title { font-size: 14px; font-weight: 400; overflow-wrap: anywhere; }
  .unread .title { font-weight: 700; }
  .when { margin-left: auto; font-family: var(--mono); font-size: 11px; color: var(--m50); white-space: nowrap; }
  .detail { margin: 0; font-size: 13px; color: var(--m70); line-height: 1.5; overflow-wrap: anywhere; }
  .foot { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 12px; }
  .where { font-family: var(--mono); font-size: 11px; color: var(--m60); overflow-wrap: anywhere; }
  .acts { margin-left: auto; display: inline-flex; gap: 6px; }
  .tag.ok { color: var(--ok); border-color: var(--ok); background: var(--ok-bg); }
  .tag.bad { color: var(--danger); border-color: var(--danger-line); background: var(--danger-note-bg); }
  @media (max-width: 820px) { .when { margin-left: 0; width: 100%; } .acts { margin-left: 0; } }
</style>

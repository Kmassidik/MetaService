<script lang="ts">
  /** The panel's top: a large face, the name, and the bot's label (its title), edited in place. */
  import type { Agent } from '../../lib/types.ts'
  import BotAvatar from '../BotAvatar.svelte'
  import StackedAvatars from '../chrome/StackedAvatars.svelte'
  import SavedTick from '../profile/SavedTick.svelte'
  import { PROFILE_LIMITS } from '../../lib/constants.ts'

  const AVATAR_SIZE = 88
  const STACKED_FACES = 2
  const LABEL_PLACEHOLDER = 'Add a label'

  interface Props {
    agent: Agent
    members?: Agent[]
    labelSaved?: boolean | undefined
    onSaveLabel?: (label: string) => unknown
  }

  type InputEvent<E extends Event> = E & { currentTarget: HTMLInputElement }

  let { agent, members = [], labelSaved = false, onSaveLabel }: Props = $props()

  const isGroup = $derived(agent.kind === 'team')
  const faces = $derived(members.length ? members.slice(0, STACKED_FACES) : [agent])
  const groupLine = $derived(members.length === 1 ? '1 member' : `${members.length} members`)

  function saveLabel(event: InputEvent<Event>): void {
    const value = event.currentTarget.value.trim()
    if (value === (agent.title || '')) return
    onSaveLabel?.(value)
  }

  function labelKey(event: InputEvent<KeyboardEvent>): void {
    if (event.key === 'Enter') {
      event.currentTarget.blur()
      return
    }
    if (event.key !== 'Escape') return
    // Escape abandons the edit; the panel's own Escape (close) must not fire too.
    event.stopPropagation()
    event.currentTarget.value = agent.title || ''
    event.currentTarget.blur()
  }
</script>

<header class="identity">
  {#if isGroup}
    <StackedAvatars agents={faces} size={AVATAR_SIZE} />
  {:else}
    <BotAvatar {agent} size={AVATAR_SIZE} />
  {/if}
  <h2>{agent.name}</h2>
  {#if isGroup}
    <p class="group-line">Group · {groupLine}</p>
  {:else}
    <div class="label-wrap">
      <input
        class="label"
        value={agent.title || ''}
        placeholder={LABEL_PLACEHOLDER}
        maxlength={PROFILE_LIMITS.title}
        aria-label={`Label for ${agent.name}`}
        onblur={saveLabel}
        onkeydown={labelKey}
      />
      {#if labelSaved}<span class="label-tick"><SavedTick shown /></span>{/if}
    </div>
  {/if}
</header>

<style>
  .identity { display: grid; justify-items: center; gap: 2px; padding: 8px 20px 14px; text-align: center; }
  .identity > :global(:first-child) { margin-bottom: 14px; }
  h2 { max-width: 100%; color: var(--text); font: 600 20px/1.25 var(--font); overflow-wrap: anywhere; }
  .label-wrap { position: relative; width: 100%; max-width: 280px; }
  /* Over the label's right end, so the brief tick never moves the header. */
  .label-tick { position: absolute; top: 50%; right: 6px; transform: translateY(-50%); padding-left: 6px; background: var(--sidebar); pointer-events: none; }
  .label, .group-line { width: 100%; max-width: 280px; color: var(--text-2); font: 400 var(--fs-preview)/1.4 var(--font); text-align: center; }
  .label {
    padding: 3px 8px;
    border: 1px solid transparent;
    border-radius: var(--radius-item);
    background: transparent;
    text-overflow: ellipsis;
  }
  .label::placeholder { color: var(--text-2); opacity: 1; }
  .label:hover { background: var(--tint-hover); }
  .label:focus { border-color: var(--hairline); background: var(--page); color: var(--text); outline: none; }
  @media (max-width: 820px) { .label { font-size: 16px; } }
</style>

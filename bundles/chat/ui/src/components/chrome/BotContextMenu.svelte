<script lang="ts">
  /** Bot / group actions (right-click, hover ⋯ or long-press on a sidebar row). */
  import type { Agent } from '../../lib/types.ts'
  import FloatingMenu from './FloatingMenu.svelte'
  import { isTeam } from '../../lib/chat/roster.ts'

  interface Props {
    open?: boolean
    x?: number
    y?: number
    agent?: Agent | null
    agentLimitReached?: boolean
    onAction?: (action: string, agent: Agent | null) => unknown
    onClose?: () => void
  }

  let {
    open = false,
    x = 0,
    y = 0,
    agent = null,
    agentLimitReached = false,
    onAction,
    onClose,
  }: Props = $props()

  // The avatar picker replaces this menu in place, so Rail closes it itself.
  const KEEPS_MENU_OPEN = 'avatar'

  function run(action: string): void {
    onAction?.(action, agent)
    if (action !== KEEPS_MENU_OPEN) onClose?.()
  }
</script>

<FloatingMenu open={open && Boolean(agent)} {x} {y} label={`Actions for ${agent?.name || ''}`} {onClose}>
  {#if isTeam(agent)}
    <button type="button" role="menuitem" class="menu-item" onclick={() => run('details')}>Group details</button>
  {:else}
    <button type="button" role="menuitem" class="menu-item" onclick={() => run('avatar')}>Change avatar</button>
    <button type="button" role="menuitem" class="menu-item" onclick={() => run('pin')}>{agent?.pinned ? 'Unpin' : 'Pin to top'}</button>
    <button type="button" role="menuitem" class="menu-item" onclick={() => run('hide')}>{agent?.hidden ? 'Show in sidebar' : 'Hide from sidebar'}</button>
    <button type="button" role="menuitem" class="menu-item" disabled={agentLimitReached} onclick={() => run('duplicate')}>Duplicate</button>
    <button type="button" role="menuitem" class="menu-item" onclick={() => run('details')}>Show details</button>
  {/if}
  <hr class="menu-divider" />
  <button type="button" role="menuitem" class="menu-item danger" onclick={() => run('delete')}>Delete…</button>
</FloatingMenu>

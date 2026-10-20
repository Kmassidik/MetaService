<script lang="ts">
  import type { Routine } from '../../../lib/types.ts'
  import Card from './Card.svelte'
  import Icon from '../../Icon.svelte'
  import { describeRoutine } from './routineSchedule.ts'

  // A compact confirmation that a routine exists, with Pause (or Resume) and Open.
  const ACTIVE_STATE = 'active'
  interface Props {
    routine: Routine
    busy?: boolean
    onAction: (id: string, action: string) => unknown
    onOpen: () => unknown
  }

  let { routine, busy = false, onAction, onOpen }: Props = $props()

  const active = $derived(routine.state === ACTIVE_STATE)
  const schedule = $derived(active ? describeRoutine(routine) : `Paused · ${describeRoutine(routine)}`)
</script>

<Card label="Routine created" title={routine.title}>
  <p class="schedule"><Icon name="clock" size={16} />{schedule}</p>
  {#snippet actions()}
    <button type="button" class="primary-button" onclick={onOpen}>Open</button>
    <button type="button" class="card-quiet" disabled={busy} onclick={() => onAction(routine.id, active ? 'pause' : 'resume')}>{active ? 'Pause' : 'Resume'}</button>
  {/snippet}
</Card>

<style>
  .schedule { display: flex; align-items: center; gap: 8px; margin: -4px 0 0; color: var(--text-2); font: 400 14px/1.45 var(--font); }
  .schedule :global(svg) { flex-shrink: 0; }
</style>

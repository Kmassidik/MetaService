<script>
  import { relativeTime, commandName, commandOutcome } from '../lib/format.js'

  let { commands, now } = $props()
</script>

<section class="activity" aria-label="Recent activity">
  <h2>Recent activity</h2>
  {#if commands.length === 0}
    <p class="muted">Nothing yet. Requests to create, start, stop or delete VMs show up here.</p>
  {:else}
    <ul>
      {#each commands as command (command.id)}
        <li>
          <span class="what"><strong>{commandName(command.type)}</strong> {command.params.name ?? command.workload_id ?? ''} <span class="muted">on {command.machine}</span></span>
          <span class="state {command.state}">{command.state}</span>
          <span class="muted outcome">{commandOutcome(command)}</span>
          <span class="muted nums">{relativeTime(command.created_at, now)}</span>
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .activity { display: grid; gap: 10px; }
  h2 { font-size: 16px; }
  ul { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); }
  li { display: grid; grid-template-columns: minmax(180px, 2fr) 90px minmax(160px, 3fr) 80px; gap: 12px; align-items: center; padding: 10px 16px; border-top: 1px solid var(--line); }
  li:first-child { border-top: 0; }
  .state { font-weight: 600; font-size: 13px; }
  .state.succeeded { color: var(--ok); }
  .state.failed { color: var(--danger); }
  .state.running, .state.queued { color: var(--warn); }
  .outcome { overflow-wrap: anywhere; }
  @media (max-width: 760px) { li { grid-template-columns: 1fr auto; } .outcome { grid-column: 1 / -1; } }
</style>

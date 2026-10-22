<script lang="ts">
  import ActionButton from './ActionButton.svelte'
  import type { BundleOverview } from '../lib/types.ts'

  let { overview, onPin, onRollback }: { overview: BundleOverview | null; onPin: (version: string) => Promise<unknown>; onRollback: () => Promise<unknown> } = $props()
</script>

<section class="bundles" aria-label="Chat bundle">
  <div class="top">
    <h2>Chat bundle</h2>
    <ActionButton variant="line" label={`Roll back${overview?.previous ? ` to ${overview.previous}` : ''}`} busyLabel="Rolling back…" doneLabel="Rolled back" disabled={!overview?.previous} onrun={onRollback} />
  </div>
  {#if !overview || overview.bundles.length === 0}
    <p class="muted">No bundle files on the Root machine yet. Put a built bundle in its bundle folder.</p>
  {:else}
    <ul>
      {#each overview.bundles as bundle (bundle.version + bundle.platform)}
        <li>
          <strong>{bundle.version}</strong>
          <span class="muted">{bundle.platform} · {Math.max(1, Math.round(bundle.size / 1024))} KB</span>
          <span class="mono muted sha">{bundle.sha256.slice(0, 12)}</span>
          {#if bundle.pinned}<span class="pinned">pinned</span>{:else}<ActionButton variant="line" small label="Pin" busyLabel="Pinning…" doneLabel="Pinned" onrun={() => onPin(bundle.version)} />{/if}
        </li>
      {/each}
    </ul>
    <p class="muted note">Machines and VMs that already have the chat follow the pinned version within a few seconds. A first install is always your request.</p>
  {/if}
</section>

<style>
  .bundles { display: grid; gap: 10px; }
  .top { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
  h2 { font-size: 16px; }
  ul { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); }
  li { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; padding: 10px 16px; border-top: 1px solid var(--line); }
  li:first-child { border-top: 0; }
  .sha { margin-left: auto; }
  .pinned { padding: 0 10px; border-radius: 999px; background: var(--ok-bg); color: var(--ok); font-weight: 600; font-size: 13px; }
  .note { font-size: 13px; }
</style>

<script lang="ts">
  import ConfirmDialog from '../ConfirmDialog.svelte'
  import { shareRemovePeer } from '../../lib/api.ts'
  import type { JoinedMachine } from '../../lib/share.ts'
  import { handshakeText, OS_NAMES, removePeerCopy } from '../../lib/shareText.ts'

  let { peers, onChanged }: { peers: JoinedMachine[]; onChanged: () => Promise<void> } = $props()
  let removing = $state<JoinedMachine | null>(null)
  const copy = $derived(removing ? removePeerCopy(removing) : removePeerCopy({ name: '' }))

  async function remove() {
    if (!removing) return
    await shareRemovePeer(removing.name)
    await onChanged()
  }
</script>

{#if peers.length === 0}
  <p class="none" data-testid="peers-empty">No machine has joined yet.</p>
{:else}
  <div class="tablewrap" role="region" aria-label="Joined machines, scroll to view columns">
    <table class="restable stack">
      <thead><tr><th>Name</th><th>Address</th><th>System</th><th>Key</th><th>Last handshake</th><th><span class="sr">Actions</span></th></tr></thead>
      <tbody>
        {#each peers as peer (peer.name)}
          <tr>
            <td class="c-name" data-label="Name">{peer.name}</td>
            <td class="small" data-label="Address">{peer.address}</td>
            <td data-label="System">{OS_NAMES[peer.os]} {peer.cpu}</td>
            <td class="small" data-label="Key">{peer.key}</td>
            <td data-label="Seen">{handshakeText(peer.handshakeSecsAgo)}</td>
            <td data-label="Actions"><button class="btn danger sm" type="button" aria-label="Remove {peer.name}" onclick={() => (removing = peer)}>Remove</button></td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<ConfirmDialog open={removing !== null} {...copy} onconfirm={remove} onClose={() => (removing = null)} />

<style>
  .none { margin: 0; padding: 16px 28px; color: var(--m50); font-size: 13px; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m50); overflow-wrap: anywhere; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
  @media (max-width: 820px) { .none { padding: 16px; } }
</style>

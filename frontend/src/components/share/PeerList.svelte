<script lang="ts">
  import ConfirmDialog from '../ConfirmDialog.svelte'
  import SecretField from '../SecretField.svelte'
  import { cleanReady, removeSharedMachine } from '../../lib/leave.ts'
  import type { JoinedMachine } from '../../lib/share.ts'
  import { handshakeText, LEAVE_COMMAND, OS_NAMES, removePeerCopy } from '../../lib/shareText.ts'

  let { peers, onChanged }: { peers: JoinedMachine[]; onChanged: () => Promise<void> } = $props()
  let removing = $state<JoinedMachine | null>(null)
  let clean = $state(true)
  let sudoPassword = $state('')
  /** Said under the list after a removal that could not clean the computer. */
  let notice = $state('')
  const copy = $derived(removing ? removePeerCopy(removing, clean) : removePeerCopy({ name: '' }))

  $effect(() => {
    if (removing) return
    clean = true
    sudoPassword = ''
  })

  /** The clean-up comes first, so a wrong password stops here with the machine still listed; the password is cleared as the request starts. */
  async function remove() {
    if (!removing) return
    const password = sudoPassword
    sudoPassword = ''
    const result = await removeSharedMachine({ id: removing.name, clean, sudoPassword: password })
    notice = result.note ?? ''
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
{#if notice}<p class="leave notice" role="status">{notice}</p>{/if}
{#if peers.length > 0}<p class="leave">Remove cleans the computer too when you type its sudo password: it stops its helper and WireGuard and deletes its join folder. If you untick that, run <code>{LEAVE_COMMAND}</code> on it yourself.</p>{/if}

<ConfirmDialog open={removing !== null} {...copy} ready={cleanReady(clean, sudoPassword)} onconfirm={remove} onClose={() => (removing = null)}>
  <label class="check"><input type="checkbox" bind:checked={clean} /> Also clean the computer: stop its helper and WireGuard, remove its boot entries and delete its join folder (recommended)</label>
  {#if clean}
    <SecretField label={`Sudo password of ${removing?.name ?? 'that computer'}`} name="sudo-password" bind:value={sudoPassword} />
    <p class="hint">Typed once, sent to that computer's helper, used for this one clean-up and never saved. A wrong password changes nothing and the machine stays listed.</p>
  {/if}
</ConfirmDialog>

<style>
  .none { margin: 0; padding: 16px 28px; color: var(--m50); font-size: 13px; }
  .check { display: flex; gap: 8px; align-items: center; font-size: 14px; margin-top: 10px; }
  .check input { margin: 0; }
  .hint { margin: 4px 0 0; font-size: 12px; color: var(--m50); }
  .leave { margin: 0; padding: 12px 28px; color: var(--m60); font-size: 13px; }
  .notice { color: var(--warn); font-weight: 600; }
  .leave code { font-family: var(--mono); font-size: 12px; overflow-wrap: anywhere; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m50); overflow-wrap: anywhere; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
  @media (max-width: 820px) { .none, .leave { padding: 12px 16px; } }
</style>

<script lang="ts">
  // The SSH keys of one VM: the list, a red confirm before a key is removed, a block to add one, the status lines the parent's answer calls for, and the SSH setup block (progress, Try again, the command to log in).
  // Only the fingerprint of a key is shown, never the key itself. The list is read each time the dialog opens, and again every few seconds while the helper sets SSH up.
  import ConfirmDialog from '../ConfirmDialog.svelte'
  import Dialog from '../Dialog.svelte'
  import IconButton from '../IconButton.svelte'
  import ActionLine from '../ActionLine.svelte'
  import SshKeyAdd from './SshKeyAdd.svelte'
  import SshSetupBlock from './SshSetupBlock.svelte'
  import { addSshKey, listSshKeys, removeSshKey, retrySshSetup } from '../../lib/api.ts'
  import { removeSshKeyCopy } from '../../lib/confirmCopy.ts'
  import { environmentHref } from '../../lib/routes.ts'
  import { addedText, statusLines } from '../../lib/sshKeys.ts'
  import { setupBlock, shouldPoll, SSH_POLL_MS } from '../../lib/sshSetup.ts'
  import { VM_ICONS } from './vmIcons.ts'
  import type { Machine, SshKey, SshKeyList, Workload } from '../../lib/types.ts'

  interface Props {
    machine: Machine
    workload: Workload
    open: boolean
    onClose: () => void
  }

  const CHECK_FAILED = 'Could not check the progress. Trying again…'
  const READ_FAILED = 'The keys could not be read. Close this and open it again.'

  let { machine, workload, open, onClose }: Props = $props()
  let list = $state<SshKeyList | null>(null)
  let readFailure = $state('')
  let removing = $state<SshKey | null>(null)
  let checkFailed = $state(false)
  const lines = $derived(list ? statusLines(list, workload.state) : [])
  const block = $derived(setupBlock(list, workload.state))
  const polling = $derived(shouldPoll(list))
  const copy = $derived(removeSshKeyCopy(workload))

  async function load() {
    list = null
    readFailure = ''
    checkFailed = false
    try {
      take(await listSshKeys(machine.id, workload.id))
    } catch (error) {
      readFailure = error instanceof Error && error.message ? error.message : READ_FAILED
    }
  }

  $effect(() => {
    if (open) void load()
  })

  /** Every answer that replaces the list counts; a progress check that was sent before one of them must not undo it. */
  let listVersion = 0
  const take = (next: SshKeyList) => {
    listVersion += 1
    list = next
  }

  /** One progress check. A failed check keeps what is shown and says so; the next one runs on schedule. */
  async function check() {
    const sentAt = listVersion
    try {
      const next = await listSshKeys(machine.id, workload.id)
      if (sentAt === listVersion) take(next)
      checkFailed = false
    } catch {
      checkFailed = true
    }
  }

  // While the helper installs, ask again every few seconds, one request at a time; closing the dialog or a finished setup stops it.
  $effect(() => {
    if (!open || !polling) return
    let stopped = false
    let timer: ReturnType<typeof setTimeout> | undefined
    const tick = async () => {
      await check()
      if (!stopped) timer = setTimeout(tick, SSH_POLL_MS)
    }
    timer = setTimeout(tick, SSH_POLL_MS)
    return () => {
      stopped = true
      clearTimeout(timer)
    }
  })

  async function removeChosen() {
    if (removing) take(await removeSshKey(machine.id, workload.id, removing.id))
  }

  async function retry() {
    take(await retrySshSetup(machine.id, workload.id))
  }
</script>

<Dialog {open} title={`SSH keys for ${workload.name}`} {onClose} closeButton backdropClose>
  {#if readFailure}
    <ActionLine line={readFailure} failed />
  {:else if list === null}
    <p class="hint">Reading the keys…</p>
  {:else}
    {#if list.keys.length === 0}
      <p class="hint">No keys yet. Nobody can log in with a key until one is added.</p>
    {:else}
      <ul class="keys" aria-label="SSH keys">
        {#each list.keys as key (key.id)}
          <li>
            <div class="info">
              <span class="head"><span class="kind mono">{key.type}</span>{#if key.comment}<span class="comment">{key.comment}</span>{/if}</span>
              <code class="print">{key.fingerprint}</code>
              <small class="when">Added {addedText(key)}</small>
            </div>
            <IconButton label="Remove key" subject={key.comment || key.fingerprint} text="Remove" icon={VM_ICONS.trash} variant="danger" onclick={() => (removing = key)} />
          </li>
        {/each}
      </ul>
    {/if}
    {#each lines as line (line)}<p class="status">{line}</p>{/each}
    {#if checkFailed}<p class="hint" role="status">{CHECK_FAILED}</p>{/if}
    <SshKeyAdd send={(publicKey) => addSshKey(machine.id, workload.id, publicKey)} onAdded={take} />
  {/if}
  {#if list}
    <SshSetupBlock {block} address={workload.address} subject={workload.name} environmentHref={environmentHref(machine.id)} onRetry={retry} onLeave={onClose} />
  {/if}
  <div class="row"><button class="btn line" type="button" onclick={onClose}>Close</button></div>
</Dialog>

<ConfirmDialog
  open={removing !== null}
  title={copy.title}
  what={copy.what}
  consequence={copy.consequence}
  confirmLabel={copy.confirmLabel}
  busyLabel={copy.busyLabel}
  doneLabel={copy.doneLabel}
  onconfirm={removeChosen}
  onClose={() => (removing = null)}
/>

<style>
  .hint { margin: 0; font-size: 12px; color: var(--m60); line-height: 1.5; }
  .status { margin: 0; padding: 8px 10px; border-left: 3px solid var(--warn-line); background: var(--warn-note-bg); font-size: 12.5px; line-height: 1.5; }
  .keys { list-style: none; margin: 0; padding: 0; border: 1px solid var(--line); }
  li { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 10px 12px; }
  li + li { border-top: 1px solid var(--line); }
  .info { display: grid; gap: 3px; min-width: 0; }
  .head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 8px; }
  .kind { font-size: 11px; font-weight: 700; }
  .comment { font-size: 13px; overflow-wrap: anywhere; }
  .print { font-family: var(--mono); font-size: 11.5px; overflow-wrap: anywhere; background: none; padding: 0; }
  .when { font-size: 11px; color: var(--m50); }
  .row { display: flex; justify-content: flex-end; }
</style>

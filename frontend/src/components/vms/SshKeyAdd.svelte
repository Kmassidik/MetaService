<script lang="ts">
  // The "Add a key" block of the SSH keys dialog: a box for the pasted public key and an Add button that runs one request at a time.
  // The panel trims the text and refuses a private key before anything is sent; the parent's own refusal shows next to the button.
  import ActionButton from '../ActionButton.svelte'
  import { ApiError } from '../../lib/api.ts'
  import { addRefusalText, checkPastedKey, HELP_LINE } from '../../lib/sshKeys.ts'
  import type { SshKeyList } from '../../lib/types.ts'

  interface Props {
    /** Sends the key and answers with the new list. */
    send: (publicKey: string) => Promise<SshKeyList>
    onAdded: (list: SshKeyList) => void
  }

  let { send, onAdded }: Props = $props()
  let pasted = $state('')

  /** Throws the plain refusal so the button shows it; nothing is sent when the panel itself refuses. */
  async function add() {
    const checked = checkPastedKey(pasted)
    if (!checked.ok) throw new Error(checked.text)
    try {
      onAdded(await send(checked.key))
    } catch (error) {
      throw error instanceof ApiError ? new Error(addRefusalText(error)) : error
    }
    pasted = ''
  }
</script>

<div class="add">
  <label class="lbl" for="ssh-key-paste">Add a key</label>
  <textarea id="ssh-key-paste" class="fld" rows="3" spellcheck="false" autocomplete="off" autocapitalize="off" placeholder="ssh-ed25519 AAAA… name@laptop" bind:value={pasted}></textarea>
  <p class="hint">{HELP_LINE}</p>
  <ActionButton label="Add" busyLabel="Adding…" doneLabel="Added" onrun={add} />
</div>

<style>
  .add { display: grid; gap: 8px; justify-items: start; }
  .lbl { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.14em; color: var(--m50); }
  textarea { font-family: var(--mono); font-size: 12px; resize: vertical; overflow-wrap: anywhere; }
  .hint { margin: 0; font-size: 12px; color: var(--m60); line-height: 1.5; }
</style>

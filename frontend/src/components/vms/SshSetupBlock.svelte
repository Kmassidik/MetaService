<script lang="ts">
  // What the SSH keys dialog says about the SSH server inside the VM: setting up (a calm progress line), failed (the plain message and Try again),
  // ready (the command to paste), why there is no command, or the old plain line when the parent is old. Every text from the parent is shown as plain text.
  import ActionButton from '../ActionButton.svelte'
  import SshCommandBox from './SshCommandBox.svelte'
  import { connectionLine, CONNECT_NOTE } from '../../lib/sshKeys.ts'
  import { DEFAULT_JUMP_NOTE, ENVIRONMENT_LINK_TEXT, INSTALLING_TEXT, PASTE_NOTE, READY_TEXT, type SetupBlock } from '../../lib/sshSetup.ts'

  interface Props {
    block: SetupBlock
    /** The VM's own address, for the old plain line. */
    address: string | null | undefined
    /** The VM's name, added to the spoken name of the Copy button. */
    subject: string
    /** Where the machine's Environment tab is. */
    environmentHref: string
    /** Asks the helper to set SSH up again. Throws the plain refusal. Without it a failure shows no button. */
    onRetry?: () => Promise<unknown>
    /** Called when a link inside the block leaves the page it is on (a dialog closes itself then). */
    onLeave?: () => void
  }

  let { block, address, subject, environmentHref, onRetry, onLeave }: Props = $props()
  const legacy = $derived(connectionLine(address))
</script>

{#snippet environmentLink()}
  <a class="link" href={environmentHref} onclick={onLeave}>{ENVIRONMENT_LINK_TEXT}</a>
{/snippet}

{#if block.kind === 'installing'}
  <p class="progress" role="status"><span class="btn-spin" aria-hidden="true"></span>{INSTALLING_TEXT}</p>
{:else if block.kind === 'failed'}
  <div class="failed" role="alert">
    <p class="message">{block.message}</p>
    {#if onRetry}<ActionButton label="Try again" busyLabel="Trying…" doneLabel="Started" onrun={onRetry} small />{/if}
  </div>
{:else if block.kind === 'ready'}
  <div class="ready">
    <p class="ok" role="status">{READY_TEXT}</p>
    <SshCommandBox command={block.command} {subject} />
    <p class="hint">{PASTE_NOTE}</p>
    {#if block.jumpIsDefault}<p class="hint">{DEFAULT_JUMP_NOTE} {@render environmentLink()}</p>{/if}
  </div>
{:else if block.kind === 'no-command'}
  <p class="status">{block.text}{#if block.needsEnvironment}{' '}{@render environmentLink()}{/if}</p>
{:else if block.kind === 'legacy' && legacy}
  <div class="ready">
    <span class="lbl">Log in</span>
    <SshCommandBox command={legacy} {subject} />
    <p class="hint">{CONNECT_NOTE}</p>
  </div>
{/if}

<style>
  .progress { display: flex; align-items: center; gap: 2px; margin: 0; padding: 10px 12px; border: 1px solid var(--line); background: var(--surface-2); font-size: 12.5px; line-height: 1.5; }
  .progress :global(.btn-spin) { flex: none; }
  .failed { display: grid; gap: 8px; justify-items: start; padding: 10px 12px; border: 1px solid var(--danger-note-line); border-left: 4px solid var(--danger-note-bar); background: var(--danger-note-bg); }
  .message { margin: 0; font-size: 12.5px; line-height: 1.5; color: var(--danger-note-text); overflow-wrap: anywhere; }
  .ready { display: grid; gap: 8px; }
  .ok { margin: 0; padding: 8px 10px; border: 1px solid var(--ok-note-line); border-left: 4px solid var(--ok); background: var(--ok-note-bg); color: var(--ok-note-text); font-size: 12.5px; font-weight: 700; }
  .hint { margin: 0; font-size: 12px; color: var(--m60); line-height: 1.5; }
  .status { margin: 0; padding: 8px 10px; border-left: 3px solid var(--warn-line); background: var(--warn-note-bg); font-size: 12.5px; line-height: 1.5; }
  .lbl { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.14em; color: var(--m50); }
  .link { text-decoration: underline; font-weight: 700; }
</style>

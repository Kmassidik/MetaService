<script lang="ts">
  // Create token: name, what it may do, its limits, how long it lives. After it is made the window shows the token once.
  // The token text lives only in this window's memory: closing the window forgets it. It is never put in storage or in the address.
  import { untrack } from 'svelte'
  import ActionButton from '../ActionButton.svelte'
  import Dialog from '../Dialog.svelte'
  import McpCodeBox from './McpCodeBox.svelte'
  import { mcpCreateToken } from '../../lib/api.ts'
  import { MCP_SCOPES, type McpInfo } from '../../lib/mcp.ts'
  import { draftFor, draftProblem, toggleScope, tokenBody } from '../../lib/mcpDraft.ts'
  import { AUTO_APPROVE_WARNING, NEW_TOKEN_WARNING, SCOPE_TEXT } from '../../lib/mcpText.ts'

  let { open, defaults, onClose, onCreated }: { open: boolean; defaults: McpInfo['defaults'] | undefined; onClose: () => void; onCreated: () => Promise<void> } = $props()
  let draft = $state(draftFor())
  /** The new token's text, or empty while the form is shown. */
  let secret = $state('')

  $effect(() => {
    if (!open) return
    untrack(() => {
      draft = draftFor(defaults)
      secret = ''
    })
  })

  function close() {
    secret = ''
    onClose()
  }

  async function create() {
    const problem = draftProblem(draft)
    if (problem) throw new Error(problem)
    secret = await mcpCreateToken(tokenBody(draft))
    await onCreated()
  }
</script>

<Dialog {open} title={secret ? 'Token created' : 'Create token'} onClose={close} spacious>
  {#if secret}
    <p class="warn" role="alert" data-testid="token-warning">{NEW_TOKEN_WARNING}</p>
    <McpCodeBox text={secret} describe="new token" />
    <div class="row"><button class="btn" type="button" onclick={close}>Done</button></div>
  {:else}
    <label class="field"><span>Name</span><input type="text" maxlength="64" autocomplete="off" spellcheck="false" placeholder="for example: my laptop" bind:value={draft.name} aria-label="Token name" /></label>
    <fieldset>
      <legend>What it may do</legend>
      {#each MCP_SCOPES as scope (scope)}
        <label class="scope">
          <input type="checkbox" checked={draft.scopes.includes(scope)} onchange={(event) => (draft.scopes = toggleScope(draft.scopes, scope, event.currentTarget.checked))} aria-label="Scope {scope}" />
          <span><strong>{SCOPE_TEXT[scope].name}</strong> {SCOPE_TEXT[scope].explain}</span>
        </label>
      {/each}
    </fieldset>
    <fieldset>
      <legend>Limits (for this token alone)</legend>
      <div class="limits">
        <label><span>VMs alive at once</span><input type="number" min="1" bind:value={draft.maxVms} aria-label="VMs alive at once" /></label>
        <label><span>vCPU in total</span><input type="number" min="1" bind:value={draft.maxVcpu} aria-label="vCPU in total" /></label>
        <label><span>RAM in total (GB)</span><input type="number" min="1" bind:value={draft.maxRamGb} aria-label="RAM in total in GB" /></label>
        <label><span>Disk in total (GB)</span><input type="number" min="1" bind:value={draft.maxDiskGb} aria-label="Disk in total in GB" /></label>
        <label><span>Creates per day</span><input type="number" min="1" bind:value={draft.createsPerDay} aria-label="Creates per day" /></label>
        {#if draft.scopes.includes('gpu')}
          <label><span>GPU memory (GB)</span><input type="number" min="1" bind:value={draft.gpuMemoryGb} aria-label="GPU memory in GB" /></label>
        {/if}
        <label><span>Lasts (days, up to 365)</span><input type="number" min="1" max="365" bind:value={draft.expiresInDays} aria-label="Days until it expires" /></label>
      </div>
    </fieldset>
    <label class="auto">
      <input type="checkbox" bind:checked={draft.autoApprove} aria-label="Auto-approve" />
      <span><strong>Auto-approve</strong> Do not ask me about risky requests.</span>
    </label>
    {#if draft.autoApprove}<p class="warn" role="alert" data-testid="auto-warning">{AUTO_APPROVE_WARNING}</p>{/if}
    <div class="row">
      <button class="btn line" type="button" onclick={close}>Cancel</button>
      <ActionButton label="Create token" busyLabel="Creating…" doneLabel="Created" variant="green" onrun={create} />
    </div>
  {/if}
</Dialog>

<style>
  fieldset { margin: 0; padding: 0; border: 0; display: grid; gap: 8px; min-width: 0; }
  legend { padding: 0; margin-bottom: 8px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: .12em; color: var(--m50); }
  .scope, .auto { display: flex; gap: 10px; align-items: flex-start; font-size: 13px; line-height: 1.5; cursor: pointer; }
  .scope input, .auto input { margin-top: 3px; flex: none; }
  .limits { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; }
  .limits label { display: grid; gap: 4px; font-size: 13px; }
  .limits span { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: .06em; color: var(--m50); }
  .limits input { border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 8px 10px; font-family: var(--mono); font-size: 13px; min-width: 0; }
  .field { margin: 0; }
  .warn { margin: 0; padding: 10px 14px; background: var(--warn-bg); color: var(--warn); border: 1px solid var(--warn-line); font-size: 13px; line-height: 1.6; }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; align-items: center; }
</style>

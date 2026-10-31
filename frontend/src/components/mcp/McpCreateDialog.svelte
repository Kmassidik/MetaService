<script lang="ts">
  // Create token: which person it is for, a name, what it may do, how long it lives. The limits are the person's, so none are asked here.
  // After it is made the window shows the token once. The text lives only in this window's memory: closing the window forgets it. It is never put in storage or in the address.
  import { untrack } from 'svelte'
  import ActionButton from '../ActionButton.svelte'
  import Dialog from '../Dialog.svelte'
  import McpCodeBox from './McpCodeBox.svelte'
  import { mcpCreateToken } from '../../lib/api.ts'
  import type { McpInfo, McpPerson } from '../../lib/mcp.ts'
  import { tokenBody, tokenDraftFor, tokenProblem, toggleScope } from '../../lib/mcpDraft.ts'
  import { NEW_TOKEN_WARNING, SCOPE_TEXT } from '../../lib/mcpText.ts'

  let { open, people, defaults, onClose, onCreated }: { open: boolean; people: McpPerson[]; defaults: McpInfo['defaults'] | undefined; onClose: () => void; onCreated: () => Promise<void> } = $props()
  let draft = $state(tokenDraftFor([]))
  /** The new token's text, or empty while the form is shown. */
  let secret = $state('')
  const active = $derived(people.filter((person) => person.disabledAt === null))
  const person = $derived(active.find((entry) => entry.id === draft.personId))

  $effect(() => {
    if (!open) return
    untrack(() => {
      draft = tokenDraftFor(people, defaults?.expiryDays)
      secret = ''
    })
  })

  /** Choosing another person offers that person's scopes, all ticked. */
  function choose(id: string) {
    draft.personId = id
    draft.scopes = [...(active.find((entry) => entry.id === id)?.scopes ?? [])]
  }

  function close() {
    secret = ''
    onClose()
  }

  async function create() {
    const problem = tokenProblem(draft, person)
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
  {:else if active.length === 0}
    <p class="muted" data-testid="no-person">There is no person to make a token for. Add a person first.</p>
    <div class="row"><button class="btn line" type="button" onclick={close}>Close</button></div>
  {:else}
    <label class="field"><span>For which person</span>
      <select value={draft.personId} onchange={(event) => choose(event.currentTarget.value)} aria-label="Person">
        {#each active as entry (entry.id)}<option value={entry.id}>{entry.name}</option>{/each}
      </select>
    </label>
    <label class="field"><span>Token name</span><input type="text" maxlength="40" autocomplete="off" spellcheck="false" placeholder="for example: laptop" bind:value={draft.name} aria-label="Token name" /></label>
    <fieldset>
      <legend>What it may do (never more than the person may)</legend>
      {#each person?.scopes ?? [] as scope (scope)}
        <label class="scope">
          <input type="checkbox" checked={draft.scopes.includes(scope)} onchange={(event) => (draft.scopes = toggleScope(draft.scopes, scope, event.currentTarget.checked))} aria-label="Scope {scope}" />
          <span><strong>{SCOPE_TEXT[scope].name}</strong> {SCOPE_TEXT[scope].explain}</span>
        </label>
      {/each}
    </fieldset>
    <label class="field"><span>Lasts (days, up to 365)</span><input type="number" min="1" max="365" bind:value={draft.expiresInDays} aria-label="Days until it expires" /></label>
    <div class="row">
      <button class="btn line" type="button" onclick={close}>Cancel</button>
      {#key open}<ActionButton label="Create token" busyLabel="Creating…" doneLabel="Created" variant="green" onrun={create} />{/key}
    </div>
  {/if}
</Dialog>

<style>
  fieldset { margin: 0; padding: 0; border: 0; display: grid; gap: 8px; min-width: 0; }
  legend { padding: 0; margin-bottom: 8px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: .12em; color: var(--m50); }
  .scope { display: flex; gap: 10px; align-items: flex-start; font-size: 13px; line-height: 1.5; cursor: pointer; }
  .scope input { margin-top: 3px; flex: none; }
  .field { margin: 0; }
  select { width: 100%; border: 1px solid var(--line); padding: 11px 12px; font-size: 14px; font-family: var(--sans); background: var(--surface); color: var(--text); }
  .muted { margin: 0; color: var(--m60); font-size: 13px; }
  .warn { margin: 0; padding: 10px 14px; background: var(--warn-bg); color: var(--warn); border: 1px solid var(--warn-line); font-size: 13px; line-height: 1.6; }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; align-items: center; }
</style>

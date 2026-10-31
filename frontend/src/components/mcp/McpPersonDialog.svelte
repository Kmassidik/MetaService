<script lang="ts">
  // Add person or Edit person: the scopes and the limits. The limits are the person's, counted over all their tokens. An edit keeps the name.
  import { untrack } from 'svelte'
  import ActionButton from '../ActionButton.svelte'
  import Dialog from '../Dialog.svelte'
  import { mcpAddPerson, mcpEditPerson } from '../../lib/api.ts'
  import { MCP_SCOPES, type McpInfo, type McpPerson } from '../../lib/mcp.ts'
  import { personBody, personDraftFor, personPatch, personProblem, toggleScope } from '../../lib/mcpDraft.ts'
  import { SCOPE_TEXT } from '../../lib/mcpText.ts'

  /** `person` is the one being edited; null adds a new one. */
  let { open, person, defaults, onClose, onSaved }: { open: boolean; person: McpPerson | null; defaults: McpInfo['defaults'] | undefined; onClose: () => void; onSaved: () => Promise<void> } = $props()
  let draft = $state(personDraftFor())

  $effect(() => {
    if (open) untrack(() => (draft = personDraftFor(defaults, person ?? undefined)))
  })

  async function save() {
    const problem = personProblem(draft, person === null)
    if (problem) throw new Error(problem)
    if (person) await mcpEditPerson(person.id, personPatch(draft))
    else await mcpAddPerson(personBody(draft))
    await onSaved()
    onClose()
  }
</script>

<Dialog {open} title={person ? `Edit ${person.name}` : 'Add person'} {onClose} spacious>
  {#if person === null}
    <label class="field"><span>Name</span><input type="text" maxlength="40" autocomplete="off" spellcheck="false" placeholder="for example: Ayu" bind:value={draft.name} aria-label="Person name" /></label>
  {/if}
  <fieldset>
    <legend>What they may do</legend>
    {#each MCP_SCOPES as scope (scope)}
      <label class="scope">
        <input type="checkbox" checked={draft.scopes.includes(scope)} onchange={(event) => (draft.scopes = toggleScope(draft.scopes, scope, event.currentTarget.checked))} aria-label="Scope {scope}" />
        <span><strong>{SCOPE_TEXT[scope].name}</strong> {SCOPE_TEXT[scope].explain}</span>
      </label>
    {/each}
  </fieldset>
  <fieldset>
    <legend>Limits (over all their tokens together)</legend>
    <div class="limits">
      <label><span>VMs alive at once</span><input type="number" min="1" bind:value={draft.maxVms} aria-label="VMs alive at once" /></label>
      <label><span>vCPU in total</span><input type="number" min="1" bind:value={draft.maxVcpu} aria-label="vCPU in total" /></label>
      <label><span>RAM in total (GB)</span><input type="number" min="1" bind:value={draft.maxRamGb} aria-label="RAM in total in GB" /></label>
      <label><span>Disk in total (GB)</span><input type="number" min="1" bind:value={draft.maxDiskGb} aria-label="Disk in total in GB" /></label>
      <label><span>Creates per day</span><input type="number" min="1" bind:value={draft.createsPerDay} aria-label="Creates per day" /></label>
      {#if draft.scopes.includes('gpu')}
        <label><span>GPU memory (GB)</span><input type="number" min="1" bind:value={draft.gpuMemoryGb} aria-label="GPU memory in GB" /></label>
      {/if}
    </div>
  </fieldset>
  <div class="row">
    <button class="btn line" type="button" onclick={onClose}>Cancel</button>
    {#key open}<ActionButton label={person ? 'Save' : 'Add person'} busyLabel="Saving…" doneLabel="Saved" variant="green" onrun={save} />{/key}
  </div>
</Dialog>

<style>
  fieldset { margin: 0; padding: 0; border: 0; display: grid; gap: 8px; min-width: 0; }
  legend { padding: 0; margin-bottom: 8px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: .12em; color: var(--m50); }
  .scope { display: flex; gap: 10px; align-items: flex-start; font-size: 13px; line-height: 1.5; cursor: pointer; }
  .scope input { margin-top: 3px; flex: none; }
  .limits { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; }
  .limits label { display: grid; gap: 4px; font-size: 13px; }
  .limits span { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: .06em; color: var(--m50); }
  .limits input { border: 1px solid var(--line); background: var(--surface); color: var(--text); padding: 8px 10px; font-family: var(--mono); font-size: 13px; min-width: 0; }
  .field { margin: 0; }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; align-items: center; }
</style>

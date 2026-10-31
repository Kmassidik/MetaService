<script lang="ts">
  // The people who use AI clients. The limits belong to the person, over all their tokens. Names are typed by people: shown as text only.
  import ActionButton from '../ActionButton.svelte'
  import ConfirmDialog from '../ConfirmDialog.svelte'
  import { mcpDisablePerson, mcpEnablePerson } from '../../lib/api.ts'
  import type { McpPerson } from '../../lib/mcp.ts'
  import { disableCopy, lastUsedText, quotaLine, SCOPE_TEXT, tokensText } from '../../lib/mcpText.ts'

  let { people, now, onChanged, onAdd, onEdit }: { people: McpPerson[]; now: number; onChanged: () => Promise<void>; onAdd: () => void; onEdit: (person: McpPerson) => void } = $props()
  let disabling = $state<McpPerson | null>(null)
  const copy = $derived(disableCopy(disabling ?? { name: '' }))

  async function disable() {
    if (!disabling) return
    await mcpDisablePerson(disabling.id)
    await onChanged()
  }

  async function enable(person: McpPerson) {
    await mcpEnablePerson(person.id)
    await onChanged()
  }
</script>

<div class="bar"><button class="btn green sm" type="button" onclick={onAdd}>Add person</button></div>
{#if people.length === 0}
  <p class="none" data-testid="mcp-people-empty">No one yet. Add a person, then make a token for them.</p>
{:else}
  <div class="tablewrap">
    <table class="restable stack" data-testid="mcp-people">
      <thead><tr><th>Name</th><th>Can do</th><th>Limits</th><th>Tokens</th><th>VMs alive</th><th>Last used</th><th><span class="sr">Actions</span></th></tr></thead>
      <tbody>
        {#each people as person (person.id)}
          <tr class:gone={person.disabledAt !== null}>
            <td class="c-name" data-label="Name" data-testid="person-name">{person.name}{#if person.disabledAt !== null}<span class="tag warn off">disabled</span>{/if}</td>
            <td data-label="Can do"><span class="chips">{#each person.scopes as scope (scope)}<span class="tag" title={SCOPE_TEXT[scope].explain}>{scope}</span>{/each}</span></td>
            <td class="small" data-label="Limits">{quotaLine(person.quotas, person.scopes)}</td>
            <td data-label="Tokens">{tokensText(person.tokens)}</td>
            <td class="nums" data-label="VMs alive">{person.vmsAlive}</td>
            <td data-label="Last used">{lastUsedText(person.lastUsedAt, now)}</td>
            <td data-label="">
              <div class="acts">
                <button class="btn line sm" type="button" aria-label="Edit {person.name}" onclick={() => onEdit(person)}>Edit</button>
                {#if person.disabledAt === null}
                  <button class="btn danger sm" type="button" aria-label="Disable {person.name}" onclick={() => (disabling = person)}>Disable</button>
                {:else}
                  <ActionButton label="Enable" busyLabel="Enabling…" doneLabel="Enabled" variant="green" small onrun={() => enable(person)} />
                {/if}
              </div>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<ConfirmDialog open={disabling !== null} {...copy} onconfirm={disable} onClose={() => (disabling = null)} />

<style>
  .bar { display: flex; justify-content: flex-end; }
  .none { margin: 0; color: var(--m50); font-size: 13px; }
  .tablewrap { padding: 0; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m50); overflow-wrap: anywhere; }
  .chips { display: flex; gap: 4px; flex-wrap: wrap; }
  .off { margin-left: 8px; }
  .gone { opacity: .55; }
  .acts { display: flex; gap: 8px; flex-wrap: wrap; align-items: flex-start; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
</style>

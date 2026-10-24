<script lang="ts">
  // API keys for sandboxes: a key's text is shown once, when it is made, and only its prefix is kept. A team is made the first
  // time a key names it, so no key is ever left without an owner.
  import { onMount } from 'svelte'
  import ActionButton from '../components/ActionButton.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import { ApiError, createSandboxKey, listSandboxKeys, revokeSandboxKey } from '../lib/api.ts'
  import { copyText } from '../lib/clipboard.ts'
  import { relativeTime } from '../lib/format.ts'
  import { DEFAULT_TEAM_NAME, keyState, revokeCopy, teamNameProblem } from '../lib/sandboxPanel.ts'
  import type { SandboxKey, SandboxKeyMade } from '../lib/types.ts'

  let keys = $state<SandboxKey[]>([])
  let loading = $state(true)
  let banner = $state('')
  let teamName = $state('')
  let made = $state<SandboxKeyMade | null>(null)
  let copyNote = $state('')
  let revoking = $state<SandboxKey | null>(null)
  const nameProblem = $derived(teamNameProblem(teamName))
  const revokeText = $derived(revoking ? revokeCopy(revoking) : revokeCopy({ prefix: '', team_name: '' }))

  async function load() {
    try {
      keys = await listSandboxKeys()
      banner = ''
    } catch (error) {
      banner = error instanceof ApiError ? error.message : 'The keys could not be read.'
    } finally {
      loading = false
    }
  }

  /** Makes the key and keeps it on screen until the person says they have copied it. */
  async function make() {
    made = await createSandboxKey(teamName)
    teamName = ''
    copyNote = ''
    await load()
  }

  async function copy() {
    if (!made) return
    copyNote = (await copyText(made.key)) ? 'Copied.' : 'Copying was refused: select the key and copy it yourself.'
  }

  function dismiss() {
    made = null
    copyNote = ''
  }

  async function revoke() {
    if (!revoking) return
    await revokeSandboxKey(revoking.id)
    await load()
  }

  onMount(load)
</script>

<div class="phead"><h1>API keys</h1><span class="crumb">Sandboxes › {keys.length} {keys.length === 1 ? 'key' : 'keys'}</span></div>
<p class="op-note">A key lets a program make sandboxes for its team. The key is shown once, when it is made; after that only its first part is kept, so it can be recognised but never used again. Keys are for our own programs only.</p>

{#if banner}<p class="banner" role="status">{banner}</p>{/if}

<section class="make" aria-label="Make a key">
  <label class="field">
    <span>Team</span>
    <input type="text" name="team" bind:value={teamName} placeholder={DEFAULT_TEAM_NAME} maxlength={48} aria-describedby="team-help" />
  </label>
  <ActionButton label="Make a key" busyLabel="Making…" doneLabel="Made" disabled={nameProblem !== null} onrun={make} />
  <p class="help" id="team-help">{nameProblem ?? `Leave it empty for ${DEFAULT_TEAM_NAME}. A team that does not exist yet is made with the standard limits.`}</p>
</section>

{#if made}
  <section class="made" aria-label="The new key" data-testid="new-key">
    <h2>This is the only time the key is shown</h2>
    <p>Copy it now and keep it where the program reads it. It cannot be shown again; if it is lost, revoke it and make a new one.</p>
    <div class="keyline"><code data-testid="new-key-text">{made.key}</code><button class="btn line sm" type="button" onclick={copy}>Copy</button></div>
    {#if copyNote}<p class="help" role="status">{copyNote}</p>{/if}
    <p class="help">Team {made.team_name} · starts with {made.prefix}</p>
    <button class="btn sm" type="button" onclick={dismiss}>Done, I have it</button>
  </section>
{/if}

<div class="tablewrap" role="region" aria-label="Keys, scroll to view columns">
  <table class="restable stack">
    <thead><tr><th>Key</th><th>Team</th><th>Made</th><th>Last used</th><th>State</th><th><span class="sr">Actions</span></th></tr></thead>
    <tbody>
      {#each keys as key (key.id)}
        <tr>
          <td data-label="Key"><b>{key.prefix}</b>…</td>
          <td data-label="Team">{key.team_name}</td>
          <td data-label="Made" class="muted">{relativeTime(key.created_at)}</td>
          <td data-label="Last used" class="muted">{relativeTime(key.last_used_at)}</td>
          <td data-label="State"><span class="tag" class:run={key.revoked_at === null}>{keyState(key.revoked_at)}</span></td>
          <td data-label="Actions">
            {#if key.revoked_at === null}
              <button class="btn danger sm" type="button" onclick={() => (revoking = key)}>Revoke</button>
            {:else}
              <span class="muted">—</span>
            {/if}
          </td>
        </tr>
      {:else}
        <tr><td colspan="6">{loading ? 'Reading the keys…' : 'No keys yet. Make one above.'}</td></tr>
      {/each}
    </tbody>
  </table>
</div>

<ConfirmDialog open={revoking !== null} {...revokeText} onconfirm={revoke} onClose={() => (revoking = null)} />

<style>
  .make { display: flex; align-items: flex-end; gap: 12px; flex-wrap: wrap; padding: 20px 28px; border-bottom: 1px solid var(--line); }
  .make .field { width: auto; min-width: 220px; }
  .help { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .make .help { flex-basis: 100%; }
  .made { margin: 20px 28px; padding: 18px 20px; border: 1px solid var(--warn-note-line); border-left: 4px solid var(--warn-line); background: var(--warn-note-bg); display: grid; gap: 10px; justify-items: start; }
  .made h2 { margin: 0; font-family: var(--mono); font-size: 13px; letter-spacing: 0.06em; text-transform: uppercase; color: var(--warn-note-title); }
  .made p { margin: 0; font-size: 13px; line-height: 1.6; color: var(--m70); }
  .keyline { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .keyline code { padding: 8px 10px; border: 1px solid var(--line); background: var(--surface-2); font-family: var(--mono); font-size: 12px; overflow-wrap: anywhere; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
  @media (max-width: 820px) { .make, .made { margin-left: 0; margin-right: 0; } .made { margin: 16px; } }
</style>

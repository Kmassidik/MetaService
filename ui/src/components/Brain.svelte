<script>
  import { ApiError } from '../lib/api.js'

  let { status, onTest } = $props()
  let busy = $state(false)
  let result = $state(null)

  async function test() {
    busy = true
    result = null
    try {
      await onTest()
      result = { ok: true, text: 'Connected: the provider answered a one-word test.' }
    } catch (error) {
      result = { ok: false, text: error instanceof ApiError ? sentence(error.message) : 'The test did not finish.' }
    } finally {
      busy = false
    }
  }

  const sentence = (text) => text.charAt(0).toUpperCase() + text.slice(1) + (text.endsWith('.') ? '' : '.')
  const who = (row) => (row.workload ? `${row.machine} / ${row.workload}` : row.machine)
  const number = (value) => value.toLocaleString('en')
</script>

<section class="brain" aria-label="AI provider">
  <div class="top">
    <h2>AI provider</h2>
    <button class="btn" type="button" disabled={!status?.configured || busy} onclick={test}>{busy ? 'Testing…' : 'Test connection'}</button>
  </div>
  {#if !status}
    <p class="muted">Loading…</p>
  {:else if !status.configured}
    <p class="muted">Not set up. The chat answers with a plain message until the Root machine's protected env file holds <span class="mono">AI_BASE_URL</span>, <span class="mono">AI_API_KEY</span> and <span class="mono">AI_DEFAULT_MODEL</span>, and the Root is restarted.</p>
  {:else}
    <p class="line"><span class="ready">Configured</span> <span class="mono">{status.model}</span> <span class="muted">at {status.host} · up to {number(status.max_tokens)} tokens per reply</span></p>
    {#if result}<p class:good={result.ok} class:bad={!result.ok} role="status">{result.text}</p>{/if}
    {#if status.usage.length > 0}
      <ul>
        {#each status.usage as row (row.machine + '/' + (row.workload ?? ''))}
          <li>
            <strong>{who(row)}</strong>
            <span class="muted">{number(row.requests)} {row.requests === 1 ? 'reply' : 'replies'} · {number(row.prompt_tokens)} tokens in · {number(row.completion_tokens)} out</span>
          </li>
        {/each}
      </ul>
    {/if}
  {/if}
  <p class="muted note">The key stays on the Root machine. Chats get a short-lived pass and never see it.</p>
</section>

<style>
  .brain { display: grid; gap: 10px; }
  .top { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
  h2 { font-size: 16px; }
  .line { display: flex; gap: 10px; flex-wrap: wrap; align-items: baseline; margin: 0; }
  .ready { padding: 0 10px; border-radius: 999px; background: var(--ok-bg); color: var(--ok); font-weight: 600; font-size: 13px; }
  .good { color: var(--ok); margin: 0; }
  .bad { color: var(--warn); margin: 0; }
  ul { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); }
  li { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; padding: 10px 16px; border-top: 1px solid var(--line); }
  li:first-child { border-top: 0; }
  .note { font-size: 13px; }
</style>

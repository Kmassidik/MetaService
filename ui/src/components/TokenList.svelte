<script>
  let { invites } = $props()
  let copied = $state('')

  async function copy(invite) {
    try {
      await navigator.clipboard.writeText(invite.enrollment_token)
      copied = invite.name
    } catch {
      copied = ''
    }
  }
</script>

<ul>
  {#each invites as invite (invite.name)}
    <li>
      <div class="head">
        <strong>{invite.name}</strong>
        <span class="mono muted">{invite.ip ?? ''}</span>
        <button class="btn" type="button" onclick={() => copy(invite)}>{copied === invite.name ? 'Copied' : 'Copy token'}</button>
      </div>
      <code class="token mono">{invite.enrollment_token}</code>
    </li>
  {/each}
</ul>

<style>
  ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 14px; }
  .head { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin-bottom: 6px; }
  .head .btn { margin-left: auto; min-height: 32px; }
  .token { display: block; padding: 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); overflow-wrap: anywhere; user-select: all; }
</style>

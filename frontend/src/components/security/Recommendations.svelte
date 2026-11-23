<script lang="ts">
  // Simple card: which IPs to ban on the router, and a check whether an IP is already banned.
  import type { SecurityMachineLine, TopRow } from '../../lib/securityTypes.ts'

  let { machines, topAddresses }: { machines: SecurityMachineLine[]; topAddresses: TopRow[] } = $props()

  const ips = $derived(topAddresses.filter((row) => row.count >= 3).slice(0, 8))
  // Prefer the internet-facing Macs (pf wrapper installed) over Linux fail2ban for the pf check.
  const banMachine = $derived(
    machines.find((m) => m.reported && m.baseline?.ban_tool === 'running' && m.machine.startsWith('mac-'))?.machine
      ?? machines.find((m) => m.reported && m.baseline?.ban_tool === 'running')?.machine
      ?? machines.find((m) => m.reported)?.machine,
  )
  let ip = $state('')
  let checking = $state(false)
  let result = $state('')

  async function check(): Promise<void> {
    if (!ip.trim() || !banMachine) return
    checking = true
    result = ''
    try {
      const reply = await fetch(`/api/security/ban-status?machine=${encodeURIComponent(banMachine)}&address=${encodeURIComponent(ip.trim())}`)
      const body = (await reply.json()) as { banned: boolean }
      result = body.banned ? '✓ banned' : 'not banned'
    } catch {
      result = 'unreachable'
    } finally {
      checking = false
    }
  }
</script>

{#if ips.length > 0 || banMachine}
  <section class="card tile" data-testid="recommendations">
    {#if ips.length > 0}
      <div class="row head"><span>Block these on the router (Omada → Firewall → ipblock group):</span></div>
      {#each ips as entry (entry.name)}
        <div class="row">
          <code class="ip">{entry.name}</code>
          <span class="tries">{entry.count} tries</span>
          <button type="button" class="btn line sm" onclick={() => (ip = entry.name)}>check</button>
        </div>
      {/each}
    {/if}
    <div class="row check">
      <input class="input" type="text" placeholder="IP to check" bind:value={ip} aria-label="IP to check" />
      <button type="button" class="btn line sm" onclick={check} disabled={checking}>{checking ? '…' : 'Already banned?'}</button>
      <span class="result">{result}</span>
    </div>
  </section>
{/if}

<style>
  .card { border: 1px solid var(--line); background: var(--surface); padding: 16px; display: flex; flex-direction: column; gap: 4px; }
  .tile { height: 100%; }
  .row { display: flex; align-items: center; gap: 10px; padding: 4px 0; font-size: 12px; }
  .head { color: var(--muted); margin-bottom: 4px; }
  .ip { font-family: var(--mono); font-size: 12px; color: var(--text); }
  .tries { color: var(--muted); font-size: 11px; }
  .check { margin-top: 8px; border-top: 1px solid var(--line); padding-top: 10px; }
  .input { width: 180px; padding: 5px 10px; border: 1px solid var(--line); border-radius: 6px; background: var(--surface); color: var(--text); font-family: var(--mono); font-size: 12px; }
  .result { color: var(--ok); font-size: 12px; }
</style>

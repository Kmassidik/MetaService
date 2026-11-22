<script lang="ts">
  // Recommendations card: what to do NEXT, derived from the overview data (PRD-security-hardening.md §3).
  // Router blocks come with the exact Omada rule text; the is-banned button checks a machine's pf table.
  import { recommendations } from '../../lib/securityRecommend.ts'
  import type { SecurityMachineLine, TopRow } from '../../lib/securityTypes.ts'

  let { machines, topAddresses }: { machines: SecurityMachineLine[]; topAddresses: TopRow[] } = $props()

  const recs = $derived(recommendations(machines, topAddresses))
  let checking = $state<Record<string, boolean>>({})
  let banResult = $state<Record<string, string>>({})

  async function checkBan(machine: string, address: string): Promise<void> {
    checking[machine + address] = true
    try {
      const params = new URLSearchParams({ machine, address })
      const reply = await fetch(`/api/security/ban-status?${params}`)
      if (!reply.ok) throw new Error('unreachable')
      const body = (await reply.json()) as { banned: boolean; reachable: boolean }
      banResult[machine + address] = body.banned ? '✓ already banned' : 'not banned yet'
    } catch {
      banResult[machine + address] = 'unreachable'
    } finally {
      checking[machine + address] = false
    }
  }
</script>

{#if recs.length > 0}
  <section class="reccard" aria-label="Security recommendations" data-testid="recommendations">
    <h2>Do this next</h2>
    <ol>
      {#each recs as rec, index (rec.target + rec.action)}
        <li class="rec">
          <div class="action">
            <strong>{rec.action}</strong>
            <span class="target">on {rec.target}</span>
          </div>
          <p class="why">{rec.why}</p>
          {#if rec.omadaRule}
            <pre class="rule">{rec.omadaRule}</pre>
            <div class="checkrow">
              <label for="checkip-{index}">Is it already banned?</label>
              <input id="checkip-{index}" class="ipinput" type="text" placeholder="1.2.3.4" value={topAddresses[0]?.name ?? ''} />
              <button type="button" class="btn line sm" onclick={(e) => {
                const input = (e.currentTarget as HTMLElement).parentElement?.querySelector('input') as HTMLInputElement
                const firstMachine = machines.find((m) => m.reported)?.machine
                if (input?.value && firstMachine) void checkBan(firstMachine, input.value.trim())
              }}>Check</button>
              <span class="result">{banResult[machines.find((m) => m.reported)?.machine! + (topAddresses[0]?.name ?? '')] ?? ''}</span>
            </div>
          {/if}
        </li>
      {/each}
    </ol>
  </section>
{/if}

<style>
  .reccard { border: 1px solid var(--line); border-radius: 10px; background: var(--surface); padding: 14px 18px; margin-bottom: 16px; }
  h2 { font-size: 12px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: var(--m50); margin: 0 0 10px; }
  ol { padding: 0 0 0 20px; margin: 0; }
  .rec { margin-bottom: 12px; }
  .action { display: flex; gap: 8px; align-items: baseline; }
  .action strong { font-size: 13px; color: var(--text); }
  .target { font-size: 11px; color: var(--muted); }
  .why { font-size: 12px; color: var(--m60); margin: 4px 0 0; }
  .rule { font-family: var(--mono); font-size: 11px; background: var(--surface-2); border: 1px solid var(--line); border-radius: 6px; padding: 8px 12px; margin: 8px 0 0; white-space: pre-wrap; }
  .checkrow { display: flex; align-items: center; gap: 8px; margin-top: 8px; font-size: 12px; }
  .checkrow label { color: var(--muted); }
  .ipinput { width: 160px; padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px; background: var(--surface); color: var(--text); font-family: var(--mono); font-size: 12px; }
  .result { color: var(--ok); font-size: 12px; }
</style>

<script>
  // Token ledger, as in the MAAS panel: what each machine and VM has used of the AI, as the Root counted it.
  import { usageName, usageTotals } from '../lib/overview.js'

  let { brain } = $props()
  const rows = $derived(brain?.usage ?? [])
  const totals = $derived(usageTotals(rows))
  const number = (value) => value.toLocaleString('en')
</script>

<div class="phead"><h1>Token ledger</h1><span class="crumb">Operator › Token ledger</span></div>
<p class="op-note">The Root counts every reply the AI gives to Ruvio, per machine and per VM. The AI key never leaves the Root.</p>
<section class="op-stats" aria-label="Totals">
  <div class="op-stat"><span>Replies</span><b class="nums">{number(totals.requests)}</b></div>
  <div class="op-stat"><span>Tokens in</span><b class="nums">{number(totals.promptTokens)}</b></div>
  <div class="op-stat"><span>Tokens out</span><b class="nums">{number(totals.completionTokens)}</b></div>
  <div class="op-stat"><span>Total tokens</span><b class="nums">{number(totals.promptTokens + totals.completionTokens)}</b></div>
</section>
<div class="tablewrap" role="region" aria-label="Usage per machine and VM, scroll to view columns">
  <table class="restable">
    <thead><tr><th>Machine / VM</th><th>Replies</th><th>Tokens in</th><th>Tokens out</th></tr></thead>
    <tbody>
      {#each rows as row (usageName(row))}
        <tr><td><b>{usageName(row)}</b></td><td class="nums">{number(row.requests)}</td><td class="nums">{number(row.prompt_tokens)}</td><td class="nums">{number(row.completion_tokens)}</td></tr>
      {:else}
        <tr><td colspan="4">{brain?.configured ? 'No replies yet.' : 'The AI provider is not set up, so nothing is counted yet.'}</td></tr>
      {/each}
    </tbody>
  </table>
</div>

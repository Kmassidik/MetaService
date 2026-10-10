<script>
  import Card from './Card.svelte'
  import { resultLine, resultLinkLabel, resultTitle } from '../../../lib/appCards.js'

  // What an app tool did, as the app itself showed it (the tick, "Message sent", the saved event), not as the bot words it.
  let { result } = $props()
</script>

<Card label={resultTitle(result)} title={resultTitle(result)}>
  <p class="proof" class:failed={!result.ok}>{resultLine(result)}</p>
  {#if result.ok && result.link}
    <a class="link" href={result.link} target="_blank" rel="noopener noreferrer">{resultLinkLabel(result)}</a>
  {/if}
</Card>

<style>
  .proof { margin: -4px 0 0; color: var(--text-2); font: 500 14px/1.45 var(--font); overflow-wrap: anywhere; }
  .proof.failed { font-weight: 400; }
  .link { color: var(--text); font: 500 14px/1.4 var(--font); }
</style>

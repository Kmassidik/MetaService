<script>
  import RuviHero from '../../RuviHero.svelte'
  import { SETUP_EXPECTED_SECONDS } from '../../../lib/constants.js'

  // The status line while a sent message waits for the bot's new computer; the reply follows on its own.
  const ART_WIDTH = 40
</script>

<div class="setup-status" role="status">
  <RuviHero pose="setting-up" width={ART_WIDTH} variant="inline" />
  <span>Setting up your computer… about {SETUP_EXPECTED_SECONDS} seconds</span>
</div>

<style>
  .setup-status { display: flex; align-items: center; gap: 10px; margin: 6px 0 2px; color: var(--text-2); font: 400 14px/1.4 var(--font); }
</style>

<script lang="ts">
  import Owl from '../components/Owl.svelte'
  import { shownAddress } from '../lib/routes.ts'

  let { route }: { route: string } = $props()
</script>

<div class="phead"><h1>Page not found</h1><span class="crumb">Not found</span></div>
<div class="empty stage">
  <Owl name="notFound" />
  <p>There is nothing at this address: <code>{shownAddress(route)}</code></p>
  <a class="btn green" href="#/">Go to Overview</a>
  <p class="muted">Or open <a href="#/machines">Machines</a> or <a href="#/vms">VMs</a>.</p>
</div>

<style>
  p { margin: 0; overflow-wrap: anywhere; }
</style>

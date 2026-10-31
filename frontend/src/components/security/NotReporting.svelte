<script lang="ts">
  // The whole tab for a machine that has sent no security report. It says why that can be, and that such a machine is not being watched. No numbers, no zeros.
  import type { Machine } from '../../lib/types.ts'

  let { machine }: { machine: Machine } = $props()
  const offline = $derived(machine.state === 'offline')
  const reason = $derived(offline
    ? 'The machine is offline, so its helper cannot send anything.'
    : 'Its helper is old and does not send security data, or it has not connected yet.')
</script>

<div class="op-alert" role="status" data-testid="security-not-reporting">
  <b>Not reporting yet</b>
  <p>{reason}</p>
  <p><strong>A machine that does not report is not being watched.</strong> Nobody would see failed logins or blocked addresses here, so do not read the empty tab as "all quiet".</p>
</div>

<style>
  .op-alert { max-width: 640px; }
</style>

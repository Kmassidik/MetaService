<script>
  import { STATE_LABELS } from '../lib/format.js'

  let { state, label = null } = $props()
  const tone = $derived(state === 'online' ? 'run' : state === 'busy' ? 'warn' : '')
</script>

<span class="tag {tone}">{label ?? STATE_LABELS[state] ?? 'Unknown'}</span>

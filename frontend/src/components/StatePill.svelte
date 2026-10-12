<script lang="ts">
  import { STATE_LABELS } from '../lib/format.ts'

  let { state, label = null }: { state: string; label?: string | null } = $props()
  const tone = $derived(state === 'online' ? 'run' : state === 'busy' ? 'warn' : '')
</script>

<span class="tag {tone}">{label ?? STATE_LABELS[state] ?? 'Unknown'}</span>

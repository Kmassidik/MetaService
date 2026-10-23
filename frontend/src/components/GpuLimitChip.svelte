<script lang="ts">
  // The small chip next to a VM's status that says how much GPU memory is booked for it ("GPU 4 GB"). It only exists for a VM that has a limit.
  import { LIMIT_CHIP_TITLE, limitChipText } from '../lib/gpuBooking.ts'

  let { gb }: { gb: number } = $props()
</script>

<span class="tag" title={LIMIT_CHIP_TITLE} data-gpu-limit-chip>{limitChipText(gb)}</span>

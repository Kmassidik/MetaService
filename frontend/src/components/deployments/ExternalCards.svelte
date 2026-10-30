<script lang="ts">
  // The services that were on the machine before MetaService, as cards of the Cards view. Each opens the same dialog as its block in the Building.
  import RuntimeLogo from './RuntimeLogo.svelte'
  import type { ExternalBlock } from '../../lib/externalBlocks.ts'

  let { blocks, onOpen }: { blocks: ExternalBlock[]; onOpen: (id: string) => void } = $props()
</script>

{#each blocks as block (block.id)}
  <div class="card external-card" data-service-id={block.id}>
    <div class="ch">
      <div class="row1"><RuntimeLogo logo={block.logo} size={20} /><span class="nm">{block.name}</span><span class="tag" class:run={block.state === 'running'}>{block.state}</span><span class="tag">external</span></div>
      <div class="specs"><span>{block.tag}</span><span>{block.kind}</span></div>
      <div class="dom">{block.image ?? '—'}</div>
    </div>
    <div class="acts"><button class="btn sm" type="button" onclick={() => onOpen(block.id)}>Details</button></div>
  </div>
{/each}

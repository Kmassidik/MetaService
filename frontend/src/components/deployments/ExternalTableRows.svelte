<script lang="ts">
  // The services that were on the machine before MetaService, as rows of the Table view. Each opens the same dialog as its block in the Building.
  import RuntimeLogo from './RuntimeLogo.svelte'
  import type { ExternalBlock } from '../../lib/externalBlocks.ts'

  let { blocks, onOpen }: { blocks: ExternalBlock[]; onOpen: (id: string) => void } = $props()
</script>

{#each blocks as block (block.id)}
  <tr class="external-row" data-service-id={block.id}>
    <td class="c-name" data-label="Name"><span class="who"><RuntimeLogo logo={block.logo} /><span>{block.name}</span></span><small class="ext-id mono">{block.id}</small></td>
    <td data-label="Status"><span class="tag" class:run={block.state === 'running'}>{block.state}</span><span class="tag">external</span></td>
    <td class="mono muted" data-label="Ruvio">—</td>
    <td class="mono" data-label="Type">{block.tag} · {block.kind}</td>
    <td class="mono muted" data-label="Size">—</td>
    <td class="mono muted" data-label="Address">{block.image ?? '—'}</td>
    <td data-label="Actions"><button class="btn sm" type="button" onclick={() => onOpen(block.id)}>Details</button></td>
  </tr>
{/each}

<style>
  .who { display: inline-flex; align-items: center; gap: 8px; }
  .ext-id { display: block; margin-top: 2px; font-size: 11px; font-weight: 400; color: var(--m50); overflow-wrap: anywhere; }
</style>

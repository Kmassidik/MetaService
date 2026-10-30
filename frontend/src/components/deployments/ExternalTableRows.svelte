<script lang="ts">
  // The services that were on the machine before MetaService, as rows of the Table view. Each opens the same dialog as its block in the Building.
  import RuntimeLogo from './RuntimeLogo.svelte'
  import type { ExternalBlock } from '../../lib/externalBlocks.ts'

  let { blocks, onOpen }: { blocks: ExternalBlock[]; onOpen: (id: string) => void } = $props()
</script>

{#each blocks as block (block.id)}
  <tr class="external-row" data-service-id={block.id}>
    <td class="c-name" data-label="Name"><span class="who"><RuntimeLogo logo={block.logo} /><span>{block.name}</span></span><small class="ext-id mono" title={block.id}>{block.id}</small></td>
    <td data-label="Status"><span class="tag" class:run={block.state === 'running'}>{block.state}</span><span class="tag">external</span></td>
    <td class="mono muted" data-label="Ruvio">—</td>
    <td class="mono kind" data-label="Type">{block.tag} · {block.kind}</td>
    <td class="mono muted" data-label="Size">—</td>
    <td class="mono muted" data-label="Address"><span class="image" title={block.image ?? ''}>{block.image ?? '—'}</span></td>
    <td data-label="Actions"><button class="btn sm" type="button" onclick={() => onOpen(block.id)}>Details</button></td>
  </tr>
{/each}

<style>
  .who { display: inline-flex; align-items: center; gap: 8px; }
  /* The full id and image are in the dialog; the row keeps one line each so the columns stay even. */
  .ext-id { display: block; max-width: 240px; margin-top: 2px; font-size: 11px; font-weight: 400; color: var(--m50); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .kind { white-space: nowrap; }
  .image { display: block; max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  @media (max-width: 820px) { .ext-id, .image { max-width: none; white-space: normal; overflow-wrap: anywhere; } }
</style>

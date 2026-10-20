<script lang="ts">
  /** A file's ⋯ menu in the Files tab: Download, Attach to chat, Extract text, rendered PDF, Details, Delete. */
  import type { FileMenuTarget } from './fileMenu.ts'
  import Icon from '../Icon.svelte'
  import FloatingMenu from '../chrome/FloatingMenu.svelte'
  import { canExtractText, downloadUrl, isReady } from '../../lib/files/preview.ts'
  import { ICON_SIZE } from '../../lib/constants.ts'

  interface Props {
    menu?: FileMenuTarget | null
    attached?: boolean
    attachDisabled?: boolean
    deleteDisabled?: boolean
    onClose: () => void
    onAttach: (target: FileMenuTarget) => unknown
    onExtract: (target: FileMenuTarget) => unknown
    onPreviewRendered: (target: FileMenuTarget) => unknown
    onDetails: (target: FileMenuTarget) => unknown
    onDelete: (target: FileMenuTarget) => unknown
  }

  let { menu = null, attached = false, attachDisabled = false, deleteDisabled = false, onClose, onAttach, onExtract, onPreviewRendered, onDetails, onDelete }: Props = $props()

  const file = $derived(menu?.file)
  const rendered = $derived(menu?.renderedPdf)

  // Close first so the action's own view (viewer, confirm) is what has focus next.
  function run(action: (target: FileMenuTarget) => unknown): void {
    const target = menu
    if (!target) return
    onClose()
    action(target)
  }
</script>

<FloatingMenu open={Boolean(file)} x={menu?.x} y={menu?.y} label={file ? `Actions for ${file.name}` : 'File actions'} {onClose}>
  {#if file}
    {#if isReady(file)}
      <a class="menu-item" role="menuitem" href={downloadUrl(file.id)} download onclick={onClose}><Icon name="download" size={ICON_SIZE.inline} />Download</a>
      <button type="button" class="menu-item" role="menuitem" disabled={attachDisabled || attached} onclick={() => run(onAttach)}>
        <Icon name="attach" size={ICON_SIZE.inline} />{attached ? 'Attached to this chat' : 'Attach to chat'}
      </button>
    {/if}
    {#if canExtractText(file)}
      <button type="button" class="menu-item" role="menuitem" onclick={() => run(onExtract)}><Icon name="code" size={ICON_SIZE.inline} />Extract text</button>
    {/if}
    {#if rendered}
      <button type="button" class="menu-item" role="menuitem" onclick={() => run(onPreviewRendered)}><Icon name="eye" size={ICON_SIZE.inline} />Preview rendered PDF</button>
      <a class="menu-item" role="menuitem" href={downloadUrl(rendered.id)} download onclick={onClose}><Icon name="download" size={ICON_SIZE.inline} />Download rendered PDF</a>
    {/if}
    <button type="button" class="menu-item" role="menuitem" onclick={() => run(onDetails)}><Icon name="info" size={ICON_SIZE.inline} />Details and versions</button>
    <hr class="menu-divider" />
    <button type="button" class="menu-item danger" role="menuitem" disabled={deleteDisabled} onclick={() => run(onDelete)}><Icon name="trash" size={ICON_SIZE.inline} />Delete</button>
  {/if}
</FloatingMenu>

<script>
  /**
   * The side panel's Files tab: every saved file from all bots, newest first, with one search box
   * and type chips. Tapping a picture opens the viewer; PDF, HTML and CSV open their preview; other
   * files open their details. Everything else (download, attach, extract text, delete) is in ⋯.
   */
  import Icon from '../Icon.svelte'
  import FileRow from './FileRow.svelte'
  import FileRowMenu from './FileRowMenu.svelte'
  import ImageViewer from '../files/ImageViewer.svelte'
  import DocumentPreview from '../files/DocumentPreview.svelte'
  import ExtractionView from '../files/ExtractionView.svelte'
  import FileDetails from '../files/FileDetails.svelte'
  import { isDocumentPreview, isViewableImage } from '../../lib/files/preview.js'
  import { filterGroups, groupVersions, presentCategories, renderedPdfOf, shownVersion } from '../../lib/files/fileList.js'
  import { ICON_SIZE } from '../../lib/constants.js'

  // Wide enough that the menu opens to the left of the ⋯ button; FloatingMenu keeps it on screen.
  const MENU_WIDTH = 240
  const MENU_GAP = 4
  const CHIP_ICON_SIZE = 15

  let { files = [], agents = [], loading = false, error = '', refresh, attach, remove, selectedIds = [], canAttach = false, deleting = '', sessionKey = '' } = $props()

  let query = $state('')
  let category = $state('')
  let versions = $state({})
  let overlay = $state(null)
  let menu = $state(null)
  let confirmDelete = $state('')

  const agentNames = $derived(new Map(agents.map(agent => [agent.id, agent.name])))
  const groups = $derived(groupVersions(files))
  const categories = $derived(presentCategories(files))
  const rows = $derived(filterGroups(groups, { query, category }).map(group => ({ group, file: shownVersion(group, versions[group.id]) })))
  const images = $derived(rows.map(row => row.file).filter(isViewableImage))
  const detailsGroup = $derived(overlay?.mode === 'details' ? groups.find(group => group.id === overlay.groupId) : null)

  function botName(id) {
    return agentNames.get(id) || `Unavailable bot (${id || 'unknown'})`
  }

  function clearFilters() {
    query = ''
    category = ''
  }

  // A new session (sign-in, account switch) starts from a clean list.
  $effect(() => {
    if (!sessionKey) return
    clearFilters()
    versions = {}
    overlay = null
    menu = null
    confirmDelete = ''
  })

  // A view closes when its file disappears (deleted here, or in another tab).
  $effect(() => {
    const present = new Set(files.map(file => file.id))
    if (overlay && !overlay.fileIds.every(id => present.has(id))) overlay = null
  })

  function showImage(file) {
    overlay = { mode: 'image', images, index: images.indexOf(file), fileIds: images.map(image => image.id) }
  }

  function showDocument(file, title = file.name, sourceIds = []) {
    overlay = { mode: 'document', file, title, fileIds: [file.id, ...sourceIds] }
  }

  function showDetails(group) {
    overlay = { mode: 'details', groupId: group.id, fileIds: [] }
  }

  function openRow({ group, file }) {
    if (isViewableImage(file)) showImage(file)
    else if (isDocumentPreview(file)) showDocument(file)
    else showDetails(group)
  }

  function openMenu(event, row) {
    const rect = event.currentTarget.getBoundingClientRect()
    menu = { ...row, renderedPdf: renderedPdfOf(row.file, files), x: rect.right - MENU_WIDTH, y: rect.bottom + MENU_GAP }
  }

  async function deleteFile(file) {
    if (await remove(file)) confirmDelete = ''
  }
</script>

<div class="files" aria-busy={loading}>
  <div class="toolbar">
    <label class="search">
      <Icon name="search" size={ICON_SIZE.inline} />
      <input type="search" placeholder="Search files" aria-label="Search files" bind:value={query} />
    </label>
    <button type="button" class="icon-button" aria-label="Refresh files" title="Refresh" disabled={loading} onclick={refresh}><Icon name="refresh" size={ICON_SIZE.list} /></button>
  </div>
  {#if categories.length > 1}
    <div class="chips" role="group" aria-label="File type">
      <button type="button" class="chip" aria-pressed={!category} onclick={() => { category = '' }}>All</button>
      {#each categories as item (item.id)}
        <button type="button" class="chip" aria-pressed={category === item.id} onclick={() => { category = category === item.id ? '' : item.id }}>
          <Icon name={item.icon} size={CHIP_ICON_SIZE} />{item.label}
        </button>
      {/each}
    </div>
  {/if}
  {#if error}<div class="error-box" role="alert">{error}</div>{/if}
  {#if loading && !files.length}
    <p class="empty" role="status">Loading your files…</p>
  {:else if !files.length && !error}
    <p class="empty">No files yet. Files you send in a chat and files your bots make show up here.</p>
  {:else if files.length && !rows.length}
    <p class="empty">No files match. <button type="button" class="text-button" onclick={clearFilters}>Clear search</button></p>
  {/if}
  <ul class="list" aria-label="Files">
    {#each rows as row (row.group.id)}
      <FileRow
        file={row.file} versionCount={row.group.items.length} confirming={confirmDelete === row.file.id} {deleting}
        onOpen={() => openRow(row)} onMenu={event => openMenu(event, row)}
        onDelete={() => deleteFile(row.file)} onKeep={() => { confirmDelete = '' }}
      />
    {/each}
  </ul>
</div>

<FileRowMenu
  {menu} attached={Boolean(menu && selectedIds.includes(menu.file.id))}
  attachDisabled={!canAttach || Boolean(deleting)} deleteDisabled={Boolean(deleting)}
  onClose={() => { menu = null }}
  onAttach={target => attach(target.file)}
  onExtract={target => { overlay = { mode: 'extract', file: target.file, fileIds: [target.file.id] } }}
  onPreviewRendered={target => showDocument(target.renderedPdf, `${target.file.name} (rendered PDF)`, [target.file.id])}
  onDetails={target => showDetails(target.group)}
  onDelete={target => { confirmDelete = target.file.id }}
/>

{#if overlay?.mode === 'image'}
  <ImageViewer images={overlay.images} bind:index={overlay.index} onClose={() => { overlay = null }} />
{:else if overlay?.mode === 'document'}
  <DocumentPreview file={overlay.file} title={overlay.title} onClose={() => { overlay = null }} />
{:else if overlay?.mode === 'extract'}
  <ExtractionView file={overlay.file} {sessionKey} onClose={() => { overlay = null }} />
{:else if detailsGroup}
  <FileDetails
    group={detailsGroup} file={shownVersion(detailsGroup, versions[detailsGroup.id])} {botName}
    onPickVersion={id => { versions = { ...versions, [detailsGroup.id]: id } }} onClose={() => { overlay = null }}
  />
{/if}

<style>
  .files { display: grid; gap: 10px; padding: 4px 16px 24px; }
  .toolbar { display: flex; align-items: center; gap: 6px; }
  .search {
    display: flex; flex: 1; align-items: center; gap: 8px; min-width: 0; height: 38px; padding: 0 12px;
    border: 1px solid var(--hairline); border-radius: var(--radius-pill); background: var(--page); color: var(--text-3);
  }
  .search:focus-within { border-color: var(--text-3); }
  .search input { flex: 1; min-width: 0; height: 100%; padding: 0; border: 0; outline: none; background: none; color: var(--text); font: 400 14px/1.3 var(--font); }
  .chips { display: flex; gap: 6px; overflow-x: auto; scrollbar-width: none; }
  .chip {
    display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; min-height: 32px; padding: 0 12px;
    border: 1px solid var(--hairline); border-radius: var(--radius-pill); background: var(--page);
    color: var(--text-2); font: 500 13px/1 var(--font); white-space: nowrap;
  }
  .chip:hover { color: var(--text); }
  .chip[aria-pressed='true'] { border-color: var(--ink); background: var(--ink); color: var(--on-ink); }
  .empty { padding: 12px 4px; color: var(--text-2); font: 400 13px/1.5 var(--font); }
  .list { display: grid; gap: 2px; margin: 0 -8px; padding: 0; list-style: none; }
  .error-box { margin-top: 0; }
  @media (max-width: 820px) { .search input { font-size: 16px; } }
</style>

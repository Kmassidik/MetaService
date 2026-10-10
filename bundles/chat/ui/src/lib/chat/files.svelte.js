import { untrack } from 'svelte'
import { MiB } from '../constants.js'
import { PANEL_TABS } from '../sidePanel.js'
import { fail } from '../format.js'
import { api } from './client.svelte.js'
import { seedFromUpload, thumbnails } from '../files/thumbnails.js'
import {
  chat,
  fileSession,
  uploadControllers,
  runCursors,
  refreshedRuns,
  selectedAgent,
} from './state.svelte.js'

export function attachmentLimit(id, incoming) {
  const reserved = [...(chat.attachments[id] || []), ...chat.uploads.filter(upload => upload.agentId === id)]
  if (incoming.some(file => file.size > 25 * MiB)) return 'Each attachment must be 25 MiB or smaller.'
  if (reserved.length + incoming.length > 10) return 'Attach at most 10 files per message.'
  if ([...reserved, ...incoming].reduce((sum, file) => sum + file.size, 0) > 100 * MiB) return 'Attachments must total 100 MiB or less per message.'
  return ''
}

function uploadLocked() {
  const active = selectedAgent()
  return Boolean(!active || chat.pending || chat.loggingOut || chat.environmentAction || chat.environment?.state === 'deleting')
}

export async function loadFiles() {
  const key = chat.session?.csrf
  if (!key) return
  const version = ++chat.fileVersion
  chat.filesLoading = true
  try {
    const data = await api('/api/files')
    if (!fileSession(key) || version !== chat.fileVersion) return
    chat.files = data.files
    chat.filesError = ''
  } catch (error) {
    if (fileSession(key) && version === chat.fileVersion) chat.filesError = fail(error)
  } finally {
    if (fileSession(key) && version === chat.fileVersion) chat.filesLoading = false
  }
}

export function attachFile(file) {
  const id = chat.selectedId
  if (uploadLocked() || file.state !== 'ready' || (chat.attachments[id] || []).some(item => item.id === file.id)) return
  const error = attachmentLimit(id, [file])
  chat.attachmentErrors = { ...chat.attachmentErrors, [id]: error }
  if (!error) chat.attachments = { ...chat.attachments, [id]: [...(chat.attachments[id] || []), file] }
}

export function uploadFiles(input) {
  if (uploadLocked()) return
  const incoming = [...input]
  if (!incoming.length) return
  const id = chat.selectedId
  const key = chat.session.csrf
  const error = attachmentLimit(id, incoming)
  chat.attachmentErrors = { ...chat.attachmentErrors, [id]: error }
  if (error) return
  for (const file of incoming) {
    const upload = { token: crypto.randomUUID(), agentId: id, name: file.name || 'pasted-image.png', size: file.size, received: 0, fileId: '', status: 'Uploading', error: '', sessionKey: key }
    chat.uploads = [...chat.uploads, upload]
    performUpload(upload.token, file, id, key)
  }
}

export function patchUpload(token, values) {
  chat.uploads = chat.uploads.map(upload => upload.token === token ? { ...upload, ...values } : upload)
}

// The finished file joins the next message; its picture comes from the local bytes, not a download.
function attachCompletedUpload(id, record, localFile) {
  seedFromUpload(record, localFile)
  chat.attachments = { ...chat.attachments, [id]: [...(chat.attachments[id] || []), record] }
}

export async function performUpload(token, file, id, key) {
  const controller = new AbortController()
  uploadControllers.set(token, controller)
  let remoteId = ''
  let completed = false
  try {
    const created = await api(`/api/agents/${encodeURIComponent(id)}/files`, { method: 'POST', body: JSON.stringify({ name: file.name || 'pasted-image.png', size: file.size }), signal: controller.signal })
    remoteId = created.file.id
    if (!fileSession(key)) return
    patchUpload(token, { fileId: remoteId })
    for (let offset = 0; offset < file.size; offset += 24576) {
      if (controller.signal.aborted) throw new DOMException('Cancelled', 'AbortError')
      const data = await api(`/api/files/${encodeURIComponent(remoteId)}/chunks`, {
        method: 'POST', headers: { 'Content-Type': 'application/octet-stream', 'X-Upload-Offset': String(offset) },
        body: file.slice(offset, offset + 24576), signal: controller.signal,
      })
      if (!fileSession(key)) return
      patchUpload(token, { received: data.file.received })
    }
    patchUpload(token, { status: 'Finalizing' })
    const data = await api(`/api/files/${encodeURIComponent(remoteId)}/complete`, { method: 'POST', signal: controller.signal })
    if (!fileSession(key) || controller.signal.aborted) return
    completed = true
    uploadControllers.delete(token)
    attachCompletedUpload(id, data.file, file)
    chat.uploads = chat.uploads.filter(upload => upload.token !== token)
    await loadFiles()
  } catch (error) {
    if (fileSession(key) && !controller.signal.aborted) patchUpload(token, { status: 'Upload failed', error: fail(error) })
  } finally {
    uploadControllers.delete(token)
    if (!completed && remoteId && (controller.signal.aborted || !fileSession(key))) {
      try { await cleanupUpload(remoteId, key) }
      catch (error) {
        if (fileSession(key)) {
          patchUpload(token, { status: 'Cleanup failed', error: `Cancellation could not delete the stored upload: ${fail(error)} Use Remove to retry.` })
          chat.attachmentErrors = { ...chat.attachmentErrors, [id]: `Upload cleanup failed: ${fail(error)} Refresh Results to remove the file.` }
        }
      }
    }
  }
}

export async function cleanupUpload(id, key) {
  const response = await fetch(`/api/files/${encodeURIComponent(id)}`, { method: 'DELETE', credentials: 'same-origin', keepalive: true, headers: { 'X-CSRF-Token': key, Accept: 'application/json' } })
  if (!response.ok && response.status !== 404) throw new Error(`Delete failed (${response.status}).`)
}

export async function cancelUpload(upload) {
  uploadControllers.get(upload.token)?.abort()
  patchUpload(upload.token, { status: 'Cancelling' })
  try {
    if (upload.fileId) await cleanupUpload(upload.fileId, upload.sessionKey)
    else if (fileSession(upload.sessionKey)) chat.attachmentErrors = { ...chat.attachmentErrors, [upload.agentId]: 'Upload cancelled before its file ID was received. Cleanup could not be confirmed; refresh Results and delete any unfinished upload. Abandoned chat.uploads expire automatically.' }
    if (fileSession(upload.sessionKey)) chat.uploads = chat.uploads.filter(item => item.token !== upload.token)
  } catch (error) {
    if (fileSession(upload.sessionKey)) patchUpload(upload.token, { status: 'Cleanup failed', error: fail(error) })
  }
}

export function resetFiles() {
  chat.agentRuns = {}; chat.runEvents = {}; chat.runErrors = {}; chat.runActionErrors = {}; chat.runBusy = {}; chat.runNotices = {}; chat.followUps = {}
  chat.runApprovals = {}; chat.reviewedApprovals = {}
  runCursors.clear(); refreshedRuns.clear()
  chat.fileVersion += 1
  for (const controller of uploadControllers.values()) controller.abort()
  for (const upload of chat.uploads) if (upload.fileId) cleanupUpload(upload.fileId, upload.sessionKey).catch(() => {})
  chat.files = []; chat.filesLoading = false; chat.filesError = ''; chat.attachments = {}; chat.attachmentErrors = {}; chat.uploads = []
  thumbnails.clear()
}

export async function deleteFile(file) {
  const key = chat.session?.csrf
  chat.deletingFile = file.id
  chat.filesError = ''
  try {
    await api(`/api/files/${encodeURIComponent(file.id)}`, { method: 'DELETE' })
    if (!fileSession(key)) return false
    thumbnails.forget(file.id)
    chat.files = chat.files.filter(item => item.id !== file.id)
    chat.attachments = Object.fromEntries(Object.entries(chat.attachments).map(([id, items]) => [id, items.filter(item => item.id !== file.id)]))
    chat.histories = Object.fromEntries(Object.entries(chat.histories).map(([id, items]) => [id, items.map(message => ({ ...message, attachments: (message.attachments || []).map(item => item.id === file.id ? { id: file.id, state: 'deleted', name: 'File no longer available' } : item) }))]))
    return true
  } catch (error) {
    if (fileSession(key)) chat.filesError = fail(error)
    return false
  } finally {
    if (fileSession(key)) chat.deletingFile = ''
  }
}

export function pasteImages(event) {
  const images = [...(event.clipboardData?.items || [])].filter(item => item.kind === 'file' && item.type.startsWith('image/')).map(item => item.getAsFile()).filter(Boolean)
  if (images.length) { event.preventDefault(); uploadFiles(images) }
}

export function dropFiles(event) {
  event.preventDefault()
  uploadFiles(event.dataTransfer.files)
}

/** Must run during App component init (not at module import). */
export function installFileEffects() {
  $effect(() => {
    if (chat.sidePanelOpen && chat.sidePanelTab === PANEL_TABS.files && chat.session) untrack(loadFiles)
  })
}

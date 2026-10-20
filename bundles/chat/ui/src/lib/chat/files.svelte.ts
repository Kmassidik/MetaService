import { untrack } from 'svelte'
import { MiB } from '../constants.ts'
import { PANEL_TABS } from '../sidePanel.ts'
import { parseFile, parseFiles, parseReceived } from '../answers/files.ts'
import { fail } from '../format.ts'
import type { ChatFile, Upload } from '../types.ts'
import { api } from './client.svelte.ts'
import { seedFromUpload, thumbnails } from '../files/thumbnails.ts'
import {
  chat,
  fileSession,
  uploadControllers,
  runCursors,
  refreshedRuns,
  requireSession,
  selectedAgent,
} from './state.svelte.ts'

const MAX_ATTACHMENT_BYTES = 25 * MiB
const MAX_ATTACHMENTS = 10
const MAX_TOTAL_ATTACHMENT_BYTES = 100 * MiB
// Files travel to the server in pieces of this many bytes.
const UPLOAD_CHUNK_BYTES = 24576
const PASTED_IMAGE_NAME = 'pasted-image.png'
const NOT_FOUND = 404

export function attachmentLimit(id: string, incoming: readonly { size: number }[]): string {
  const reserved = [...(chat.attachments[id] || []), ...chat.uploads.filter(upload => upload.agentId === id)]
  if (incoming.some(file => file.size > MAX_ATTACHMENT_BYTES)) return 'Each attachment must be 25 MiB or smaller.'
  if (reserved.length + incoming.length > MAX_ATTACHMENTS) return 'Attach at most 10 files per message.'
  if ([...reserved, ...incoming].reduce((sum, file) => sum + file.size, 0) > MAX_TOTAL_ATTACHMENT_BYTES) return 'Attachments must total 100 MiB or less per message.'
  return ''
}

function uploadLocked(): boolean {
  const active = selectedAgent()
  return Boolean(!active || chat.pending || chat.loggingOut || chat.environmentAction || chat.environment?.state === 'deleting')
}

export async function loadFiles(): Promise<void> {
  const key = chat.session?.csrf
  if (!key) return
  const version = ++chat.fileVersion
  chat.filesLoading = true
  try {
    const files = parseFiles(await api('/api/files'))
    if (!fileSession(key) || version !== chat.fileVersion) return
    chat.files = files
    chat.filesError = ''
  } catch (error) {
    if (fileSession(key) && version === chat.fileVersion) chat.filesError = fail(error)
  } finally {
    if (fileSession(key) && version === chat.fileVersion) chat.filesLoading = false
  }
}

export function attachFile(file: ChatFile): void {
  const id = chat.selectedId
  if (uploadLocked() || file.state !== 'ready' || (chat.attachments[id] || []).some(item => item.id === file.id)) return
  const error = attachmentLimit(id, [file])
  chat.attachmentErrors = { ...chat.attachmentErrors, [id]: error }
  if (!error) chat.attachments = { ...chat.attachments, [id]: [...(chat.attachments[id] || []), file] }
}

export function uploadFiles(input: Iterable<File>): void {
  if (uploadLocked()) return
  const incoming = [...input]
  if (!incoming.length) return
  const id = chat.selectedId
  const key = requireSession().csrf
  const error = attachmentLimit(id, incoming)
  chat.attachmentErrors = { ...chat.attachmentErrors, [id]: error }
  if (error) return
  for (const file of incoming) {
    const upload: Upload = { token: crypto.randomUUID(), agentId: id, name: file.name || PASTED_IMAGE_NAME, size: file.size, received: 0, fileId: '', status: 'Uploading', error: '', sessionKey: key }
    chat.uploads = [...chat.uploads, upload]
    performUpload(upload.token, file, id, key)
  }
}

export function patchUpload(token: string, values: Partial<Upload>): void {
  chat.uploads = chat.uploads.map(upload => upload.token === token ? { ...upload, ...values } : upload)
}

/** What a message shows in place of a file the owner deleted. */
function deletedFile(id: string): ChatFile {
  return { id, state: 'deleted', name: 'File no longer available', size: 0, mediaType: '', createdAt: '' }
}

// The finished file joins the next message; its picture comes from the local bytes, not a download.
function attachCompletedUpload(id: string, record: ChatFile, localFile: File): void {
  seedFromUpload(record, localFile)
  chat.attachments = { ...chat.attachments, [id]: [...(chat.attachments[id] || []), record] }
}

export async function performUpload(token: string, file: File, id: string, key: string): Promise<void> {
  const controller = new AbortController()
  uploadControllers.set(token, controller)
  let remoteId = ''
  let completed = false
  try {
    const created = parseFile(await api(`/api/agents/${encodeURIComponent(id)}/files`, { method: 'POST', body: JSON.stringify({ name: file.name || PASTED_IMAGE_NAME, size: file.size }), signal: controller.signal }))
    remoteId = created.id
    if (!fileSession(key)) return
    patchUpload(token, { fileId: remoteId })
    for (let offset = 0; offset < file.size; offset += UPLOAD_CHUNK_BYTES) {
      if (controller.signal.aborted) throw new DOMException('Cancelled', 'AbortError')
      const received = parseReceived(await api(`/api/files/${encodeURIComponent(remoteId)}/chunks`, {
        method: 'POST', headers: { 'Content-Type': 'application/octet-stream', 'X-Upload-Offset': String(offset) },
        body: file.slice(offset, offset + UPLOAD_CHUNK_BYTES), signal: controller.signal,
      }))
      if (!fileSession(key)) return
      patchUpload(token, { received })
    }
    patchUpload(token, { status: 'Finalizing' })
    const record = parseFile(await api(`/api/files/${encodeURIComponent(remoteId)}/complete`, { method: 'POST', signal: controller.signal }))
    if (!fileSession(key) || controller.signal.aborted) return
    completed = true
    uploadControllers.delete(token)
    attachCompletedUpload(id, record, file)
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

export async function cleanupUpload(id: string, key: string): Promise<void> {
  const response = await fetch(`/api/files/${encodeURIComponent(id)}`, { method: 'DELETE', credentials: 'same-origin', keepalive: true, headers: { 'X-CSRF-Token': key, Accept: 'application/json' } })
  if (!response.ok && response.status !== NOT_FOUND) throw new Error(`Delete failed (${response.status}).`)
}

export async function cancelUpload(upload: Upload): Promise<void> {
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

export function resetFiles(): void {
  chat.agentRuns = {}; chat.runEvents = {}; chat.runErrors = {}; chat.runActionErrors = {}; chat.runBusy = {}; chat.runNotices = {}; chat.followUps = {}
  chat.runApprovals = {}; chat.reviewedApprovals = {}
  runCursors.clear(); refreshedRuns.clear()
  chat.fileVersion += 1
  for (const controller of uploadControllers.values()) controller.abort()
  for (const upload of chat.uploads) if (upload.fileId) cleanupUpload(upload.fileId, upload.sessionKey).catch(() => {})
  chat.files = []; chat.filesLoading = false; chat.filesError = ''; chat.attachments = {}; chat.attachmentErrors = {}; chat.uploads = []
  thumbnails.clear()
}

export async function deleteFile(file: ChatFile): Promise<boolean> {
  const key = chat.session?.csrf
  chat.deletingFile = file.id
  chat.filesError = ''
  try {
    await api(`/api/files/${encodeURIComponent(file.id)}`, { method: 'DELETE' })
    if (!fileSession(key)) return false
    thumbnails.forget(file.id)
    chat.files = chat.files.filter(item => item.id !== file.id)
    chat.attachments = Object.fromEntries(Object.entries(chat.attachments).map(([id, items]) => [id, items.filter(item => item.id !== file.id)]))
    chat.histories = Object.fromEntries(Object.entries(chat.histories).map(([id, items]) => [id, items.map(message => ({ ...message, attachments: (message.attachments || []).map(item => item.id === file.id ? deletedFile(file.id) : item) }))]))
    return true
  } catch (error) {
    if (fileSession(key)) chat.filesError = fail(error)
    return false
  } finally {
    if (fileSession(key)) chat.deletingFile = ''
  }
}

export function pasteImages(event: ClipboardEvent): void {
  const images = [...(event.clipboardData?.items || [])].filter(item => item.kind === 'file' && item.type.startsWith('image/')).map(item => item.getAsFile()).filter((file): file is File => file !== null)
  if (images.length) { event.preventDefault(); uploadFiles(images) }
}

export function dropFiles(event: DragEvent): void {
  event.preventDefault()
  uploadFiles(event.dataTransfer?.files ?? [])
}

/** Must run during App component init (not at module import). */
export function installFileEffects(): void {
  $effect(() => {
    if (chat.sidePanelOpen && chat.sidePanelTab === PANEL_TABS.files && chat.session) untrack(loadFiles)
  })
}

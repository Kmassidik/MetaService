import type { Environment } from '../types.ts'
import { chat, historyVersions, computerVersions } from './state.svelte.ts'
import { cancelUpload } from './files.svelte.ts'

export function updateEnvironment(value: Environment | null | undefined): boolean {
  const deleted = chat.environment?.state === 'deleting' && !value
  chat.environment = value ?? null
  if (!chat.environment) {
    chat.confirmEnvironmentDeletion = false
    chat.environmentConfirmation = ''
  }
  if (deleted) {
    chat.environmentNotice = 'Your private computer, bots, and conversation histories have been deleted.'
    clearComputerWorkspace()
  }
  return deleted
}

export function clearComputerWorkspace(): void {
  for (const upload of chat.uploads) cancelUpload(upload)
  chat.attachments = {}
  for (const [id, version] of historyVersions) historyVersions.set(id, version + 1)
  for (const [id, version] of computerVersions) computerVersions.set(id, version + 1)
  chat.agents = []
  chat.selectedId = ''
  chat.histories = {}
  chat.drafts = {}
  chat.computers = {}
  chat.desktops = {}
  chat.errors = {}
  chat.computerErrors = {}
  chat.connectProbeError = ''
  chat.showComputer = false
}

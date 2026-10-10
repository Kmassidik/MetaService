import { chat, historyVersions, computerVersions } from './state.svelte.js'
import { cancelUpload } from './files.svelte.js'

export function updateEnvironment(value) {
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

export function clearComputerWorkspace() {
  for (const upload of chat.uploads) cancelUpload(upload)
  chat.attachments = {}
  for (const id of historyVersions.keys()) historyVersions.set(id, historyVersions.get(id) + 1)
  for (const id of computerVersions.keys()) computerVersions.set(id, computerVersions.get(id) + 1)
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

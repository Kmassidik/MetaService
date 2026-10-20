import { chat, requests } from './state.svelte.ts'
import { resetFiles, installFileEffects } from './files.svelte.ts'
import { initialize, installSessionEffects } from './session.svelte.ts'
import { installComputerEffects } from './computer.svelte.ts'
import { installSidePanelEffects, restoreSidePanel } from './sidePanel.svelte.ts'
import { installRunEffects } from './runs.svelte.ts'
import { installMessageEffects } from './messages.svelte.ts'
import { installAgentEffects } from './agents.svelte.ts'
import './profile.svelte.ts'
import { DRAWER_MAX_WIDTH } from '../constants.ts'

export { chat } from './state.svelte.ts'
export {
  uploadControllers,
  runCursors,
  refreshedRuns,
  terminalRunStates,
  computerVersions,
  requests,
  historyVersions,
  fileSession,
} from './state.svelte.ts'

export { api } from './client.svelte.ts'

export {
  onUnauthorized,
  initialize,
  saveOnboarding,
  redeemInvite,
  deleteAccount,
  logout,
  loadUsage,
  loadStorage,
  loadStorageGate,
} from './session.svelte.ts'

export {
  loadFiles,
  attachmentLimit,
  attachFile,
  uploadFiles,
  patchUpload,
  performUpload,
  cleanupUpload,
  cancelUpload,
  resetFiles,
  deleteFile,
  pasteImages,
  dropFiles,
} from './files.svelte.ts'

export {
  updateEnvironment,
  clearComputerWorkspace,
  openComputer,
  openTeachSheet,
  closeComputer,
  loadEnvironment,
  manageEnvironment,
  requestComputer,
  computerAction,
  clickComputer,
  deskKey,
} from './computer.svelte.ts'

export {
  loadApps,
  refreshApps,
  connectApp,
  finishAppConnect,
  cancelAppConnect,
  checkApp,
  disconnectApp,
} from './apps.svelte.ts'

export {
  updateRun,
  loadRuns,
  refreshRun,
  cancelRun,
  decideRunApproval,
  resolveCard,
  toggleAskOption,
  submitAsk,
  skipAsk,
  askKeydown,
} from './runs.svelte.ts'

export {
  trackScroll,
  findMessage,
  scrollToLatest,
  loadHistory,
  sendMessage,
  toggleReaction,
  sendThreadReply,
  toggleDictation,
  composerKey,
  pickSkill,
  openFindOnShortcut,
} from './messages.svelte.ts'

export { WorkspaceView } from './view.svelte.ts'
export { startNewBot } from './newBot.svelte.ts'

export {
  resetAgentForm,
  validateTeam,
  chooseLead,
  applyPreset,
  loadAgents,
  selectAgent,
  patchRoster,
  duplicateActive,
  duplicateAgent,
  openMentionPicker,
  mentionBot,
  openModal,
  closeModal,
  saveAgent,
  deleteAgent,
  shareTemplate,
  refreshMarketplaceConnections,
} from './agents.svelte.ts'

export {
  createWebhookRoutine,
  saveTitle,
  routineAction,
  toggleSkill,
  clearMemory,
  teachTask,
  loadSkills,
  saveProfile,
  saveAndLeave,
  discardAndLeave,
  patchProfileSetting,
  SAVED_TICK,
} from './profile.svelte.ts'

export { createdRoutineAction } from './routineWatch.svelte.ts'

export {
  SIDE_PANEL_ID,
  openSidePanel,
  closeSidePanel,
  toggleSidePanel,
  selectPanelTab,
  openProfile,
  openFiles,
} from './sidePanel.svelte.ts'

/** Call once from App.svelte during component init so $effect is not orphaned. */
export function installChatEffects(): void {
  installSessionEffects()
  installFileEffects()
  installComputerEffects()
  installSidePanelEffects()
  installRunEffects()
  installMessageEffects()
  installAgentEffects()
}

// Whenever the bot list is a drawer it is the home screen, and opening a bot slides to the chat.
const DRAWER_QUERY = `(max-width: ${DRAWER_MAX_WIDTH}px)`

function openPhoneHome(): void {
  if (!chat.agents.length) return
  if (!window.matchMedia(DRAWER_QUERY).matches) return
  chat.mobileRail = true
}

export function mountChatLifecycle(): () => void {
  restoreSidePanel()
  initialize().then(openPhoneHome)
  return () => {
    chat.alive = false
    resetFiles()
    clearTimeout(chat.provisioningPoll)
    for (const controller of requests) controller.abort()
  }
}

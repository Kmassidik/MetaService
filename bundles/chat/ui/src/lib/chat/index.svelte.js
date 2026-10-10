import { chat, requests } from './state.svelte.js'
import { resetFiles, installFileEffects } from './files.svelte.js'
import { initialize, installSessionEffects } from './session.svelte.js'
import { installComputerEffects } from './computer.svelte.js'
import { installSidePanelEffects, restoreSidePanel } from './sidePanel.svelte.js'
import { installRunEffects } from './runs.svelte.js'
import { installMessageEffects } from './messages.svelte.js'
import { installAgentEffects } from './agents.svelte.js'
import './profile.svelte.js'
import { DRAWER_MAX_WIDTH } from '../constants.js'

export { chat } from './state.svelte.js'
export {
  uploadControllers,
  runCursors,
  refreshedRuns,
  terminalRunStates,
  computerVersions,
  requests,
  historyVersions,
  fileSession,
} from './state.svelte.js'

export { api } from './client.svelte.js'

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
} from './session.svelte.js'

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
} from './files.svelte.js'

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
} from './computer.svelte.js'

export {
  loadApps,
  refreshApps,
  connectApp,
  finishAppConnect,
  cancelAppConnect,
  checkApp,
  disconnectApp,
} from './apps.svelte.js'

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
} from './runs.svelte.js'

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
} from './messages.svelte.js'

export { WorkspaceView } from './view.svelte.js'
export { startNewBot } from './newBot.svelte.js'

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
} from './agents.svelte.js'

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
} from './profile.svelte.js'

export { createdRoutineAction } from './routineWatch.svelte.js'

export {
  SIDE_PANEL_ID,
  openSidePanel,
  closeSidePanel,
  toggleSidePanel,
  selectPanelTab,
  openProfile,
  openFiles,
} from './sidePanel.svelte.js'

/** Call once from App.svelte during component init so $effect is not orphaned. */
export function installChatEffects() {
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

function openPhoneHome() {
  if (!chat.agents.length) return
  if (!window.matchMedia(DRAWER_QUERY).matches) return
  chat.mobileRail = true
}

export function mountChatLifecycle() {
  restoreSidePanel()
  initialize().then(openPhoneHome)
  return () => {
    chat.alive = false
    resetFiles()
    clearTimeout(chat.provisioningPoll)
    for (const controller of requests) controller.abort()
  }
}

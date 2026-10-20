/**
 * Connect apps on the computer's browser: one login per app per account, shared by every bot.
 * Connect opens the account computer (no bot needed) on the app's sign-in page; the owner signs
 * in there, and the app is Connected only after the server's login check says so. That check
 * runs on its own while the owner signs in, again whenever Connect apps opens, and after a bot
 * run that used the browser.
 */
import { parseEnvironmentAnswer } from '../answers/account.ts'
import { parseAppRecord, parseApps } from '../answers/profile.ts'
import { fail } from '../format.ts'
import type { AppRecord, RunEvent } from '../types.ts'
import { MODALS } from '../constants.ts'
import { type Plugin, isConnectable, pluginById } from '../marketplace.ts'
import {
  RECHECK_AFTER_RUN_MS,
  appsAfterRun,
  appsToRecheck,
  checkCanWait,
  connectPollDelay,
  isConnected,
  keepPolling,
  notSignedInMessage,
  runUsedBrowser,
} from '../apps.ts'
import { api } from './client.svelte.ts'
import { chat } from './state.svelte.ts'
import { updateEnvironment } from './environment.svelte.ts'
import { ACCOUNT_COMPUTER, openComputer, requestComputer } from './computer.svelte.ts'
import { closeModal, openModal } from './agents.svelte.ts'

const SETUP_POLL_MS = 3000
const SETUP_TIMEOUT_MS = 240000 // four minutes: a cold computer usually takes about 15 seconds
const SETTING_UP = 'provisioning'
const READY = 'ready'
const SETUP_STOPPED = new Set(['failed', 'deleting'])

const sleep = (ms: number): Promise<void> => new Promise(resolve => setTimeout(resolve, ms))

/** An app named by its id, or by the catalog entry. */
type AppRef = string | Pick<Plugin, 'id'>
const appIdOf = (plugin: AppRef): string => typeof plugin === 'string' ? plugin : plugin.id

// Each Connect starts a new sign-in watch; an older watch sees the change and stops.
let signInWatch = 0
let afterRunTimer: ReturnType<typeof setTimeout> | undefined

export async function loadApps(): Promise<void> {
  try {
    chat.computerApps = parseApps(await api('/api/apps'))
    chat.appsError = ''
  } catch (error) {
    chat.appsError = fail(error)
  }
}

/** Connect apps or Settings › Connected apps opened: load, then check every app not signed in. */
export async function refreshApps(): Promise<void> {
  await loadApps()
  await checkEach(appsToRecheck(chat.computerApps, chat.environment, isConnectable))
}

/** A finished run: when it used the browser, check the apps again once things settle. */
export function recheckAppsAfterRun(events: readonly RunEvent[] | undefined): void {
  if (!runUsedBrowser(events)) return
  clearTimeout(afterRunTimer)
  afterRunTimer = setTimeout(() => checkEach(appsAfterRun(chat.computerApps, chat.environment, isConnectable)), RECHECK_AFTER_RUN_MS)
}

/** Opens the computer on the app's sign-in page, hands the screen to the owner and watches for the sign-in. */
export async function connectApp(plugin: string | Plugin): Promise<void> {
  const target = typeof plugin === 'string' ? pluginById(plugin) : plugin
  if (!target?.loginUrl) throw new Error('That app has no sign-in page configured.')
  if (!isConnectable(target.id)) throw new Error(`${target.name} is coming soon.`)
  chat.connectingApp = { id: target.id, name: target.name, loginUrl: target.loginUrl }
  chat.connectProbeError = ''
  chat.computerUrl = target.loginUrl
  closeModal()
  await openComputer()
  await withComputerBusy(() => openSignInPage(target.loginUrl))
  void watchSignIn(target.id)
}

/** "I'm signed in": checks now; when the login is there, back to the app list. */
export async function finishAppConnect(): Promise<boolean> {
  const connecting = chat.connectingApp
  if (!connecting) return false
  chat.connectProbeError = ''
  try {
    const record = await checkApp(connecting.id)
    if (!isConnected(record)) {
      chat.connectProbeError = notSignedInMessage(connecting.name, record)
      return false
    }
  } catch (error) {
    chat.connectProbeError = fail(error)
    return false
  }
  await completeConnect()
  return true
}

export async function cancelAppConnect(): Promise<void> {
  chat.connectProbeError = ''
  await leaveAccountComputer()
}

/** Asks the server to check the computer's browser for this app, showing "Checking…" meanwhile. */
export async function checkApp(plugin: AppRef): Promise<AppRecord> {
  const appId = appIdOf(plugin)
  chat.checkingAppId = appId
  try {
    return await probeApp(appId)
  } finally {
    chat.checkingAppId = ''
  }
}

/** One login check on the server; the answer replaces the app's record. */
async function probeApp(appId: string): Promise<AppRecord> {
  const record = parseAppRecord(await api('/api/apps', { method: 'POST', body: JSON.stringify({ app: appId }) }))
  chat.computerApps = [record, ...chat.computerApps.filter(app => app.appId !== appId)]
  return record
}

/**
 * Background checks, one app at a time. A failed check keeps that app's last answer; a busy
 * computer (checkCanWait) is left for the next check, any other failure is shown.
 */
async function checkEach(appIds: readonly string[]): Promise<void> {
  for (const appId of appIds) await checkInBackground(appId)
}

async function checkInBackground(appId: string): Promise<void> {
  try {
    await checkApp(appId)
  } catch (error) {
    if (!checkCanWait(error)) chat.appsError = fail(error)
  }
}

/**
 * Checks the login on its own while the owner signs in (backing off, up to a limit), so the app
 * turns Connected without a tap. Stops when the flow closes, another Connect starts, the limit
 * passes, or a check fails for a reason other than a busy computer.
 */
async function watchSignIn(appId: string): Promise<void> {
  const watch = ++signInWatch
  const started = Date.now()
  const open = () => watch === signInWatch && chat.connectingApp?.id === appId
  let connected = false
  for (let attempt = 0; keepPolling({ open: open(), connected, elapsedMs: Date.now() - started }); attempt += 1) {
    await sleep(connectPollDelay(attempt))
    if (!open()) return
    connected = await signInSeen(appId)
  }
  if (connected && open()) await completeConnect()
}

/** One automatic check. A busy computer waits for the next one; any other failure stops the
 * watch and shows on the sign-in banner. */
async function signInSeen(appId: string): Promise<boolean> {
  try {
    return isConnected(await probeApp(appId))
  } catch (error) {
    if (checkCanWait(error)) return false
    chat.connectProbeError = fail(error)
    signInWatch += 1
    return false
  }
}

/** The login is confirmed: give the screen back and show Connect apps with the app Connected. */
async function completeConnect(): Promise<void> {
  await leaveAccountComputer()
  openModal(MODALS.marketplace)
}

export async function disconnectApp(plugin: AppRef): Promise<void> {
  const appId = appIdOf(plugin)
  await api(`/api/apps/${encodeURIComponent(appId)}`, { method: 'DELETE' })
  chat.computerApps = chat.computerApps.filter(app => app.appId !== appId)
}

async function withComputerBusy(task: () => Promise<void>): Promise<void> {
  chat.computerBusy = { ...chat.computerBusy, [ACCOUNT_COMPUTER]: true }
  try {
    await task()
  } catch (error) {
    chat.computerErrors = { ...chat.computerErrors, [ACCOUNT_COMPUTER]: fail(error) }
  } finally {
    chat.computerBusy = { ...chat.computerBusy, [ACCOUNT_COMPUTER]: false }
  }
}

/** With no computer yet (zero bots), the first open starts setting one up; wait, then open. */
async function openSignInPage(url: string): Promise<void> {
  const first = await requestComputer(ACCOUNT_COMPUTER, 'open', { url })
  if (first?.state !== SETTING_UP) return
  updateEnvironment(first.environment)
  await waitForComputer()
  await requestComputer(ACCOUNT_COMPUTER, 'open', { url })
}

async function waitForComputer(): Promise<void> {
  const deadline = Date.now() + SETUP_TIMEOUT_MS
  while (Date.now() < deadline) {
    await sleep(SETUP_POLL_MS)
    const { environment } = parseEnvironmentAnswer(await api('/api/environment'))
    updateEnvironment(environment)
    if (environment?.state === READY) return
    if (SETUP_STOPPED.has(environment?.state ?? '')) throw new Error(environment?.lastError || 'Your computer could not be set up. Please try again.')
  }
  throw new Error('Your computer is taking longer than usual to set up. Please try again in a minute.')
}

/** Gives the screen back and closes the account computer; a failed release shows on Connect apps. */
async function leaveAccountComputer(): Promise<void> {
  chat.connectingApp = null
  chat.showComputer = false
  try {
    await requestComputer(ACCOUNT_COMPUTER, 'release', {})
  } catch (error) {
    chat.appsError = fail(error)
  }
}

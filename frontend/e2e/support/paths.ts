// Where the programs, the built panel and the stand-in tools are, and the two settings a person may change from outside.
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
export const rootBinary = join(repo, 'control-plane/arm64/.build/debug/metaservice-root')
export const agentBinary = join(repo, 'agent/macos/.build/debug/metaservice-agent')
/** The built panel the Root serves; set PANEL_DIST to test a build made somewhere else. */
export const panelDist = process.env.PANEL_DIST ?? join(repo, 'frontend/dist')
export const fakesDir = join(repo, 'contract/root_tests/fakes')
export const chatService = join(repo, 'bundles/chat/service/chat.py')
export const chatBuilder = join(repo, 'bundles/chat/build.py')

const DEFAULT_CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
export const chromePath = process.env.CHROME_PATH ?? DEFAULT_CHROME
/** A folder for screenshots, or undefined when none were asked for (set SHOTS_DIR). */
export const screenshotDir: string | undefined = process.env.SHOTS_DIR

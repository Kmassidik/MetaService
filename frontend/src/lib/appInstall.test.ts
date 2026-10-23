import { expect, test } from 'bun:test'
import { appChip, appLogoName, appTitle, hasApp, parseAppView, shouldPollApp, shownLog, stateLine, type AppView } from './appInstall.ts'
import { UnreadableAnswer } from './unreadable.ts'

const view = (overrides: Partial<AppView> = {}): AppView => ({ app: 'openclaw', state: 'installing', message: null, logTail: [], version: null, startedAt: null, ...overrides })
const raw = { app: 'hermes', state: 'failed', message: 'apt failed', log_tail: ['a', 'b'], version: '1.2', started_at: 1_700_000_000 }

test('the answer is read into the panel\'s own names', () => {
  expect(parseAppView(raw)).toEqual({ app: 'hermes', state: 'failed', message: 'apt failed', logTail: ['a', 'b'], version: '1.2', startedAt: 1_700_000_000 })
  expect(parseAppView({ app: null, state: 'none', message: null, log_tail: [], version: null, started_at: null })).toEqual(view({ app: null, state: 'none' }))
})

test('an answer that is not the promised shape is refused, not guessed', () => {
  for (const bad of [null, [], { ...raw, state: 'done' }, { ...raw, log_tail: 'text' }, { ...raw, log_tail: [1] }, { ...raw, started_at: 1.5 }, { ...raw, message: 3 }]) {
    expect(() => parseAppView(bad)).toThrow(UnreadableAnswer)
  }
})

test('the chip says installing, ready, or failed, with the failure message as hover and as a visible line', () => {
  expect(appChip({ name: 'openclaw', state: 'installing', message: null })).toEqual({ tone: 'busy', text: 'Installing OpenClaw…', title: null, detail: null })
  expect(appChip({ name: 'hermes', state: 'ready', message: null })).toEqual({ tone: 'ok', text: 'Hermes ready', title: null, detail: null })
  expect(appChip({ name: 'openclaw', state: 'failed', message: 'no network' })).toEqual({ tone: 'bad', text: 'OpenClaw install failed', title: 'no network', detail: 'no network' })
})

test('a VM without an app has no chip', () => {
  expect(appChip(null)).toBeNull()
  expect(appChip(undefined)).toBeNull()
})

test('an app the panel does not know is named as it came, and has no logo', () => {
  expect(appTitle('openclaw')).toBe('OpenClaw')
  expect(appTitle('other')).toBe('other')
  expect(appTitle(null)).toBe('The app')
  expect(appLogoName('hermes')).toBe('hermes')
  expect(appLogoName('other')).toBeNull()
})

test('the state line is plain words for each state', () => {
  expect(stateLine(view())).toBe('Installing… about 2 minutes')
  expect(stateLine(view({ state: 'ready' }))).toBe('Ready')
  expect(stateLine(view({ state: 'failed', message: 'disk full' }))).toBe('disk full')
  expect(stateLine(view({ state: 'failed' }))).toBe('The install did not finish.')
  expect(stateLine(view({ state: 'none' }))).toBe('No app is installed on this VM.')
})

test('only the last 12 lines of the log are shown', () => {
  const lines = Array.from({ length: 20 }, (_, index) => `line ${index}`)
  expect(shownLog(view({ logTail: lines }))).toEqual(lines.slice(8))
  expect(shownLog(view({ logTail: ['one'] }))).toEqual(['one'])
})

test('the page polls only while installing, and has a block only for a VM with an app', () => {
  expect(shouldPollApp(view())).toBe(true)
  for (const state of ['ready', 'failed', 'none'] as const) expect(shouldPollApp(view({ state }))).toBe(false)
  expect(shouldPollApp(null)).toBe(false)
  expect(hasApp(view())).toBe(true)
  expect(hasApp(view({ app: null, state: 'none' }))).toBe(false)
  expect(hasApp(null)).toBe(false)
})

import { describe, expect, it } from 'vitest'
import { PANEL_OPEN_KEY, PANEL_TABS, PREVIEW_TONE, isPanelShown, panelTabs, previewStatus, readPanelOpen, resolveTab, savePanelOpen } from './sidePanel.js'

const bot = { id: 'b1', kind: 'bot', name: 'Atlas' }
const group = { id: 'g1', kind: 'team', name: 'Launch team' }

function memoryStorage(initial = {}) {
  const values = new Map(Object.entries(initial))
  return { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, String(value)), values }
}

const blockedStorage = {
  getItem() { throw new Error('blocked') },
  setItem() { throw new Error('blocked') },
}

describe('panel tabs', () => {
  it('gives a bot Details, Files and Computer in that order', () => {
    expect(panelTabs(bot).map(tab => tab.label)).toEqual(['Details', 'Files', 'Computer'])
  })

  it('gives a group no Computer tab', () => {
    expect(panelTabs(group).map(tab => tab.id)).toEqual([PANEL_TABS.details, PANEL_TABS.files])
  })

  it('has only Files without a conversation', () => {
    expect(panelTabs(null).map(tab => tab.id)).toEqual([PANEL_TABS.files])
  })
})

describe('tab routing', () => {
  it('keeps a tab the conversation has', () => {
    expect(resolveTab(PANEL_TABS.computer, bot)).toBe(PANEL_TABS.computer)
    expect(resolveTab(PANEL_TABS.files, group)).toBe(PANEL_TABS.files)
  })

  it('falls back to Details when a group is asked for its computer', () => {
    expect(resolveTab(PANEL_TABS.computer, group)).toBe(PANEL_TABS.details)
  })

  it('falls back to Details for an unknown tab', () => {
    expect(resolveTab('library', bot)).toBe(PANEL_TABS.details)
  })

  it('falls back to Files with no conversation selected', () => {
    expect(resolveTab(PANEL_TABS.details, null)).toBe(PANEL_TABS.files)
  })
})

describe('panel visibility', () => {
  it('shows for an open chat', () => {
    expect(isPanelShown({ open: true, active: bot, tab: PANEL_TABS.details })).toBe(true)
  })

  it('stays hidden when closed', () => {
    expect(isPanelShown({ open: false, active: bot, tab: PANEL_TABS.files })).toBe(false)
  })

  it('shows Files alone with no chat only when Files was asked for', () => {
    expect(isPanelShown({ open: true, active: null, tab: PANEL_TABS.files })).toBe(true)
    expect(isPanelShown({ open: true, active: null, tab: PANEL_TABS.details })).toBe(false)
  })
})

describe('remembered open state', () => {
  it('is closed when never saved', () => {
    expect(readPanelOpen(memoryStorage())).toBe(false)
  })

  it('round-trips open and closed', () => {
    const storage = memoryStorage()
    expect(savePanelOpen(true, storage)).toBe(true)
    expect(readPanelOpen(storage)).toBe(true)
    savePanelOpen(false, storage)
    expect(readPanelOpen(storage)).toBe(false)
    expect(storage.values.get(PANEL_OPEN_KEY)).toBe('closed')
  })

  it('reads closed and reports the failed write when storage is blocked', () => {
    expect(readPanelOpen(blockedStorage)).toBe(false)
    expect(savePanelOpen(true, blockedStorage)).toBe(false)
  })
})

describe('preview status line', () => {
  const ready = { botName: 'Atlas', environmentState: 'ready', takingOver: false, runActive: false }

  it('names the bot and the app while its run is active', () => {
    expect(previewStatus({ ...ready, runActive: true })).toEqual({ text: 'Atlas is using Chrome', tone: PREVIEW_TONE.busy, wake: false })
  })

  it('offers to wake a sleeping computer', () => {
    const line = previewStatus({ ...ready, environmentState: 'suspended', runActive: true })
    expect(line.text).toBe('Asleep · tap to wake')
    expect(line.wake).toBe(true)
  })

  it('says it is setting up while the computer is provisioned', () => {
    expect(previewStatus({ ...ready, environmentState: 'provisioning' }).text).toBe('Setting up…')
  })

  it('puts the owner in control ahead of a running bot', () => {
    expect(previewStatus({ ...ready, takingOver: true, runActive: true }).text).toBe('You have control')
  })

  it('is idle when nothing is running', () => {
    expect(previewStatus(ready).text).toBe('Idle')
  })

  it('says not set up when there is no computer yet', () => {
    expect(previewStatus({ ...ready, environmentState: undefined }).text).toBe('Not set up yet')
  })
})

import { describe, expect, it } from 'vitest'
import {
  DEFAULT_SETTINGS_SECTION, SETTINGS, SETTINGS_SECTIONS,
  backToSettingsList, isSettingsSection, openSettings, settingsSectionLabel, showSettingsSection,
} from './settingsSections.js'

describe('settings sections', () => {
  it('lists the six sections in order, General first', () => {
    expect(SETTINGS_SECTIONS.map(section => section.id)).toEqual(['general', 'computer', 'apps', 'notifications', 'usage', 'danger'])
    expect(DEFAULT_SETTINGS_SECTION).toBe('general')
  })

  it('knows its own ids only', () => {
    expect(isSettingsSection(SETTINGS.usage)).toBe(true)
    expect(isSettingsSection('profile')).toBe(false)
    expect(isSettingsSection(null)).toBe(false)
    expect(settingsSectionLabel(SETTINGS.danger)).toBe('Danger zone')
    expect(settingsSectionLabel('nope')).toBe('')
  })
})

describe('settings navigation', () => {
  it('a plain open starts at the list with General behind it', () => {
    expect(openSettings()).toEqual({ section: 'general', listFirst: true })
    expect(openSettings('unknown')).toEqual({ section: 'general', listFirst: true })
  })

  it('a named open (Usage, Manage storage) goes straight to that section', () => {
    expect(openSettings(SETTINGS.usage)).toEqual({ section: 'usage', listFirst: false })
    expect(openSettings(SETTINGS.computer)).toEqual({ section: 'computer', listFirst: false })
  })

  it('picking a section pushes it; an unknown id changes nothing', () => {
    const start = openSettings()
    expect(showSettingsSection(start, SETTINGS.apps)).toEqual({ section: 'apps', listFirst: false })
    expect(showSettingsSection(start, 'bogus')).toBe(start)
  })

  it('back returns to the list and keeps the section', () => {
    const pushed = showSettingsSection(openSettings(), SETTINGS.notifications)
    expect(backToSettingsList(pushed)).toEqual({ section: 'notifications', listFirst: true })
    expect(pushed.listFirst).toBe(false)
  })
})

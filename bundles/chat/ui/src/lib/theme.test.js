import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  DEFAULT_THEME, THEME_STORAGE_KEY, applyTheme, chooseTheme, normalizeTheme, readTheme, resolveTheme, themeAttribute,
} from './theme.js'

const memoryStorage = (initial = {}) => {
  const values = { ...initial }
  return { getItem: key => values[key] ?? null, setItem: (key, value) => { values[key] = String(value) }, values }
}
const blockedStorage = { getItem() { throw new Error('blocked') }, setItem() { throw new Error('blocked') } }
const fakeRoot = () => ({ dataset: {} })

describe('theme choice → data-theme', () => {
  it('system leaves the attribute off; light and dark set it', () => {
    expect(themeAttribute('system')).toBeNull()
    expect(themeAttribute('light')).toBe('light')
    expect(themeAttribute('dark')).toBe('dark')
  })

  it('anything unknown falls back to System', () => {
    expect(DEFAULT_THEME).toBe('system')
    expect(normalizeTheme('sepia')).toBe('system')
    expect(normalizeTheme(null)).toBe('system')
    expect(themeAttribute(undefined)).toBeNull()
  })

  it('resolves what shows: System follows the device, a forced choice ignores it', () => {
    expect(resolveTheme('system', true)).toBe('dark')
    expect(resolveTheme('system', false)).toBe('light')
    expect(resolveTheme('light', true)).toBe('light')
    expect(resolveTheme('dark', false)).toBe('dark')
  })

  it('applyTheme sets or removes the attribute', () => {
    const root = fakeRoot()
    applyTheme('dark', root)
    expect(root.dataset.theme).toBe('dark')
    applyTheme('system', root)
    expect('theme' in root.dataset).toBe(false)
  })
})

describe('saved on the device', () => {
  it('reads a saved choice and ignores junk', () => {
    expect(readTheme(memoryStorage({ [THEME_STORAGE_KEY]: 'dark' }))).toBe('dark')
    expect(readTheme(memoryStorage({ [THEME_STORAGE_KEY]: 'neon' }))).toBe('system')
    expect(readTheme(memoryStorage())).toBe('system')
  })

  it('blocked storage reads as System and reports a failed save', () => {
    expect(readTheme(blockedStorage)).toBe('system')
    globalThis.document = { documentElement: fakeRoot() }
    expect(chooseTheme('dark', blockedStorage)).toBe(false)
    expect(document.documentElement.dataset.theme).toBe('dark')
    const storage = memoryStorage()
    expect(chooseTheme('light', storage)).toBe(true)
    expect(storage.values[THEME_STORAGE_KEY]).toBe('light')
    delete globalThis.document
  })

  it('the system-dark and chosen-dark palettes are the same and override only light tokens', () => {
    const css = readFileSync(new URL('../theme-dark.css', import.meta.url), 'utf8')
    const light = readFileSync(new URL('../style.css', import.meta.url), 'utf8')
    const block = selector => css.slice(css.indexOf(selector)).match(/\{([^{}]*)\}/)[1]
    const declarations = text => text.split(';').map(part => part.trim()).filter(Boolean)
    const system = declarations(block(':root:not([data-theme="light"])'))
    const chosen = declarations(block(':root[data-theme="dark"]'))
    expect(chosen).toEqual(system)
    const names = system.map(line => line.split(':')[0]).filter(name => name.startsWith('--'))
    for (const name of names) expect(light).toContain(`${name}:`)
    expect(names).not.toContain('--brand-green')
  })

  it('the pre-paint script reads the same key and is a file, not inline (CSP allows only self scripts)', () => {
    const script = readFileSync(new URL('../../public/theme-init.js', import.meta.url), 'utf8')
    const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8')
    expect(script).toContain(`'${THEME_STORAGE_KEY}'`)
    expect(html).toContain('<script src="/theme-init.js"></script>')
    expect(html).not.toMatch(/<script>(?!\s*<\/script>)/)
  })
})

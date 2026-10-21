// Reads the colour tokens (CSS custom properties) out of the text of themes.css, so a test can check every colour set. Pure: no DOM, no files.

export type Tokens = Record<string, string>

/** The colours of one theme: the tokens of the default set, with the ones that theme sets itself on top. */
export interface ThemeSets {
  base: Tokens
  /** Keyed by the value of the data-theme attribute. */
  themes: Record<string, Tokens>
}

const COMMENT = /\/\*[\s\S]*?\*\//g
const BLOCK = /([^{}]+)\{([^{}]*)\}/g
const ROOT = ':root'
const THEME_SELECTOR = /^:root\[data-theme="([a-z-]+)"\]$/
const REFERENCE = /^var\((--[a-z0-9-]+)\)$/
const MAX_REFERENCE_DEPTH = 8

function declarations(body: string): Tokens {
  const found: Tokens = {}
  for (const line of body.split(';')) {
    const colon = line.indexOf(':')
    const name = line.slice(0, colon).trim()
    if (colon > 0 && name.startsWith('--')) found[name] = line.slice(colon + 1).trim()
  }
  return found
}

/** Reads the `:root` block as the base set and every `:root[data-theme="name"]` block as that theme's own tokens. A rule may list several selectors. */
export function readThemeSets(css: string): ThemeSets {
  const sets: ThemeSets = { base: {}, themes: {} }
  for (const [, selectors = '', body = ''] of css.replace(COMMENT, '').matchAll(BLOCK)) {
    const tokens = declarations(body)
    for (const selector of selectors.split(',').map((part) => part.trim())) {
      const theme = THEME_SELECTOR.exec(selector)?.[1]
      if (selector === ROOT) Object.assign(sets.base, tokens)
      if (theme !== undefined) sets.themes[theme] = { ...sets.themes[theme], ...tokens }
    }
  }
  return sets
}

/** Follows `var(--other)` until a real colour is reached. */
function follow(tokens: Tokens, name: string, depth: number): string {
  const value = tokens[name]
  if (value === undefined) throw new Error(`the token ${name} is not set`)
  const next = REFERENCE.exec(value)?.[1]
  if (next === undefined) return value
  if (depth >= MAX_REFERENCE_DEPTH) throw new Error(`the token ${name} points round in a circle`)
  return follow(tokens, next, depth + 1)
}

/** Every token of a theme with its final colour. Pass no theme for the default set. */
export function resolveTheme(sets: ThemeSets, theme?: string): Tokens {
  const own = theme === undefined ? {} : sets.themes[theme]
  if (own === undefined) throw new Error(`there is no theme "${theme}"`)
  const merged: Tokens = { ...sets.base, ...own }
  const resolved: Tokens = {}
  for (const name of Object.keys(merged)) resolved[name] = follow(merged, name, 0)
  return resolved
}

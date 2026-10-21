// Reads the colour tokens (CSS custom properties) out of the text of palette.css, so a test can check them. Pure: no DOM, no files.

export type Tokens = Record<string, string>

const COMMENT = /\/\*[\s\S]*?\*\//g
const BLOCK = /([^{}]+)\{([^{}]*)\}/g
const ROOT = ':root'
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

/** The tokens set in the `:root` rules of a style sheet. Rules of other selectors are ignored. */
export function readTokens(css: string): Tokens {
  const tokens: Tokens = {}
  for (const [, selectors = '', body = ''] of css.replace(COMMENT, '').matchAll(BLOCK)) {
    if (selectors.split(',').some((selector) => selector.trim() === ROOT)) Object.assign(tokens, declarations(body))
  }
  return tokens
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

/** Every token with its final value. */
export function resolveTokens(tokens: Tokens): Tokens {
  const resolved: Tokens = {}
  for (const name of Object.keys(tokens)) resolved[name] = follow(tokens, name, 0)
  return resolved
}

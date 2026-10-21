import { test, expect } from 'bun:test'
import { readThemeSets, resolveTheme } from './themeTokens.ts'

const CSS = `
/* the default set */
:root { --a: #111; --b: var(--a); --c: rgba(1,2,3,.5); --size: 4px }
.other { --not-a-token-block: 1 }
:root[data-theme="one"] { --a: #222 }
:root[data-theme="two"], :root[data-theme="three"] { --c: #333; --extra: var(--c) }
`

test('readThemeSets reads the default block and one block per theme', () => {
  const sets = readThemeSets(CSS)
  expect(sets.base).toEqual({ '--a': '#111', '--b': 'var(--a)', '--c': 'rgba(1,2,3,.5)', '--size': '4px' })
  expect(Object.keys(sets.themes)).toEqual(['one', 'two', 'three'])
  expect(sets.themes.one).toEqual({ '--a': '#222' })
})

test('a rule that lists several themes sets the tokens of each', () => {
  const sets = readThemeSets(CSS)
  expect(sets.themes.two).toEqual({ '--c': '#333', '--extra': 'var(--c)' })
  expect(sets.themes.three).toEqual(sets.themes.two)
})

test('comments and rules of other selectors are ignored', () => {
  const sets = readThemeSets('/* :root { --x: red } */ .box { --y: blue } :root { --z: #000 }')
  expect(sets.base).toEqual({ '--z': '#000' })
})

test('resolveTheme gives the default set when no theme is named', () => {
  const resolved = resolveTheme(readThemeSets(CSS))
  expect(resolved['--b']).toBe('#111')
  expect(resolved['--c']).toBe('rgba(1,2,3,.5)')
})

test('a theme changes what the tokens that point at its tokens show', () => {
  const resolved = resolveTheme(readThemeSets(CSS), 'one')
  expect(resolved['--a']).toBe('#222')
  expect(resolved['--b']).toBe('#222')
})

test('a theme can add a token that points at one of its own', () => {
  expect(resolveTheme(readThemeSets(CSS), 'two')['--extra']).toBe('#333')
})

test('an unknown theme, a missing token and a circle are errors', () => {
  expect(() => resolveTheme(readThemeSets(CSS), 'nope')).toThrow('there is no theme "nope"')
  expect(() => resolveTheme(readThemeSets(':root { --a: var(--gone) }'))).toThrow('the token --gone is not set')
  expect(() => resolveTheme(readThemeSets(':root { --a: var(--b); --b: var(--a) }'))).toThrow('in a circle')
})

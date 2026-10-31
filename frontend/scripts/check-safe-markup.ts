// Fails the build if the UI source contains anything that opens an XSS or CSP hole.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, extname } from 'node:path'

const FORBIDDEN: ReadonlyArray<readonly [RegExp, string]> = [
  [/\{@html/, 'raw HTML rendering ({@html})'],
  [/\.innerHTML\s*=/, 'innerHTML assignment'],
  [/\.outerHTML\s*=/, 'outerHTML assignment'],
  [/insertAdjacentHTML/, 'insertAdjacentHTML'],
  [/document\.write/, 'document.write'],
  [/\beval\s*\(/, 'eval'],
  [/new Function\s*\(/, 'new Function'],
  [/\son[a-z]+\s*=\s*["']/, 'inline event handler attribute'],
  [/<[^>]+\sstyle\s*=\s*["']/, 'inline style attribute (blocked by the page policy)'],
  [/javascript:/i, 'javascript: URL'],
  [/localStorage|sessionStorage/, 'browser storage (the CSRF token lives in memory only)'],
]
/** The one file that may use browser storage: it keeps only the page size a person chose for a list (never a token or any data from the parent). */
const STORAGE_ALLOWED = 'src/lib/pageSizeStore.ts'
const STORAGE_RULE = FORBIDDEN.findIndex(([pattern]) => pattern.test('localStorage'))
const EXTENSIONS = new Set(['.svelte', '.js', '.ts', '.html'])

function* files(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) yield* files(path)
    else if (EXTENSIONS.has(extname(path))) yield path
  }
}

const problems: string[] = []
for (const root of ['src', 'index.html']) {
  const list = statSync(root).isDirectory() ? [...files(root)] : [root]
  for (const path of list) {
    if (/\.test\.[jt]s$/.test(path)) continue
    const rules = path === STORAGE_ALLOWED ? FORBIDDEN.filter((_, index) => index !== STORAGE_RULE) : FORBIDDEN
    readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
      for (const [pattern, label] of rules) if (pattern.test(line)) problems.push(`${path}:${index + 1}: ${label}`)
    })
  }
}
if (problems.length) {
  console.error(problems.join('\n'))
  process.exit(1)
}
console.log('safe-markup check passed')

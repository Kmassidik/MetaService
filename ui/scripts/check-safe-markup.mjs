// Fails the build if the UI source contains anything that opens an XSS or CSP hole.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, extname } from 'node:path'

const FORBIDDEN = [
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
const EXTENSIONS = new Set(['.svelte', '.js', '.html'])

function* files(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) yield* files(path)
    else if (EXTENSIONS.has(extname(path))) yield path
  }
}

const problems = []
for (const root of ['src', 'index.html']) {
  const list = statSync(root).isDirectory() ? [...files(root)] : [root]
  for (const path of list) {
    if (path.endsWith('.test.js')) continue
    readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
      for (const [pattern, label] of FORBIDDEN) if (pattern.test(line)) problems.push(`${path}:${index + 1}: ${label}`)
    })
  }
}
if (problems.length) {
  console.error(problems.join('\n'))
  process.exit(1)
}
console.log('safe-markup check passed')

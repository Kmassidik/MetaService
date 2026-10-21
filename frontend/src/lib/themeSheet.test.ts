import { test, expect } from 'bun:test'
import { SHEET_WIDTH, escapeHtml, sheetHtml } from './themeSheet.ts'

const COLUMNS = [
  { label: 'Today', desktopFile: 'today-login-desktop.png', phoneFile: 'today-login-phone.png' },
  { label: 'A: Forest', desktopFile: 'forest-login-desktop.png', phoneFile: 'forest-login-phone.png' },
  { label: 'B: Forest soft', desktopFile: 'forest-soft-login-desktop.png', phoneFile: 'forest-soft-login-phone.png' },
]

test('escapeHtml makes text safe to put in a page', () => {
  expect(escapeHtml('<b>"a" & b</b>')).toBe('&lt;b&gt;&quot;a&quot; &amp; b&lt;/b&gt;')
  expect(escapeHtml('plain')).toBe('plain')
})

test('the sheet has one column per theme, with the label and both pictures', () => {
  const html = sheetHtml('Login', COLUMNS)
  expect(html.match(/<figure>/g)).toHaveLength(3)
  for (const entry of COLUMNS) {
    expect(html).toContain(`>${entry.label}</figcaption>`)
    expect(html).toContain(`src="${entry.desktopFile}"`)
    expect(html).toContain(`src="${entry.phoneFile}"`)
  }
  expect(html).toContain('grid-template-columns: repeat(3, 1fr)')
  expect(html).toContain(`width: ${SHEET_WIDTH}px`)
})

test('a title or label with markup is shown as text', () => {
  const html = sheetHtml('<script>x</script>', [{ label: '<i>', desktopFile: 'a.png', phoneFile: 'b.png' }])
  expect(html).not.toContain('<script>')
  expect(html).toContain('&lt;script&gt;x&lt;/script&gt;')
  expect(html).toContain('&lt;i&gt;')
})

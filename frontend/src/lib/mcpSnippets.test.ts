import { expect, test } from 'bun:test'
import { appTabs, bridgeLine, tabIndexForKey } from './mcpSnippets.ts'
import { jsonSnippet, TOKEN_PLACEHOLDER } from './mcpText.ts'

const ENDPOINT = 'https://meta.example/mcp'
const tabs = appTabs(ENDPOINT)
const byId = (id: string) => tabs.find((tab) => tab.id === id)!
const JSON_TABS = ['cursor', 'vscode', 'opencode', 'gemini', 'other']

test('the tabs come in the agreed order with unique ids', () => {
  expect(tabs.map((tab) => tab.label)).toEqual(['Claude Code', 'Cursor', 'VS Code', 'OpenCode', 'Gemini CLI', 'Other apps'])
  expect(new Set(tabs.map((tab) => tab.id)).size).toBe(tabs.length)
})

test('every snippet has the endpoint and the placeholder, and no real-looking token', () => {
  for (const tab of tabs) {
    const all = tab.snippet + (tab.extra?.text ?? '')
    expect(all).toContain(ENDPOINT)
    expect(all).toContain(`Bearer ${TOKEN_PLACEHOLDER}`)
    expect(all).not.toMatch(/msk_/)
    expect(all).not.toMatch(/Bearer (?!<YOUR_TOKEN>)/)
  }
})

test('the snippets that should be JSON are valid JSON with the app-specific shape', () => {
  for (const id of JSON_TABS) expect(() => JSON.parse(byId(id).snippet)).not.toThrow()
  const auth = { Authorization: `Bearer ${TOKEN_PLACEHOLDER}` }
  expect(JSON.parse(byId('cursor').snippet)).toEqual({ mcpServers: { metaservice: { url: ENDPOINT, headers: auth } } })
  expect(JSON.parse(byId('vscode').snippet)).toEqual({ servers: { metaservice: { type: 'http', url: ENDPOINT, headers: auth } } })
  expect(JSON.parse(byId('opencode').snippet)).toEqual({ mcp: { metaservice: { type: 'remote', url: ENDPOINT, headers: auth } } })
  expect(JSON.parse(byId('gemini').snippet)).toEqual({ mcpServers: { metaservice: { httpUrl: ENDPOINT, headers: auth } } })
})

test('Claude Code is one terminal line', () => {
  const claude = byId('claude-code')
  expect(claude.snippet).toBe(`claude mcp add --transport http metaservice ${ENDPOINT} --header "Authorization: Bearer <YOUR_TOKEN>"`)
  expect(claude.where).toBe('Run this in a terminal.')
  expect(claude.snippet).not.toContain('\n')
})

test('the generic JSON is the one the panel always had, with the bridge line and the OAuth note', () => {
  const other = byId('other')
  expect(other.snippet).toBe(jsonSnippet(ENDPOINT))
  expect(other.extra?.text).toBe(`npx mcp-remote ${ENDPOINT} --header "Authorization: Bearer <YOUR_TOKEN>"`)
  expect(other.extra?.text).toBe(bridgeLine(ENDPOINT))
  expect(other.footer).toContain('OAuth')
  expect(other.footer).toContain('ChatGPT')
})

test('each file tab says where it goes; tabs 2 to 5 carry the short honest line', () => {
  expect(byId('cursor').where).toBe('Put this in ~/.cursor/mcp.json')
  expect(byId('vscode').where).toBe('Put this in .vscode/mcp.json')
  expect(byId('opencode').where).toBe('Put this in opencode.json')
  expect(byId('gemini').where).toBe('Put this in ~/.gemini/settings.json')
  expect(byId('cursor').caution).toBe("Check Cursor's own docs if the setting names changed.")
  expect(byId('gemini').caution).toBe("Check Gemini CLI's own docs if the setting names changed.")
  expect(byId('claude-code').caution).toBeUndefined()
  expect(byId('other').caution).toBeUndefined()
})

test('arrow keys wrap, Home and End jump, other keys do nothing', () => {
  expect(tabIndexForKey(0, 6, 'ArrowRight')).toBe(1)
  expect(tabIndexForKey(5, 6, 'ArrowRight')).toBe(0)
  expect(tabIndexForKey(0, 6, 'ArrowLeft')).toBe(5)
  expect(tabIndexForKey(3, 6, 'Home')).toBe(0)
  expect(tabIndexForKey(3, 6, 'End')).toBe(5)
  expect(tabIndexForKey(3, 6, 'a')).toBeNull()
})

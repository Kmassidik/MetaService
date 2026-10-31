// The per-app connection snippets of the Connect box: one tab per app, each with where it goes and a ready-to-copy text. Pure, so the wording is tested.
// The token is always a placeholder: a real one is shown once, in the Create token window.
import { claudeLine, jsonSnippet, TOKEN_PLACEHOLDER } from './mcpText.ts'

export type AppTabId = 'claude-code' | 'cursor' | 'vscode' | 'opencode' | 'gemini' | 'other'

export interface ExtraSnippet {
  /** One plain sentence that says when this second snippet is the one to use. */
  intro: string
  text: string
}

export interface AppTab {
  id: AppTabId
  label: string
  /** One plain line: the file or the place the snippet goes. */
  where: string
  snippet: string
  extra?: ExtraSnippet
  /** A short honest line: the format comes from the app's docs and was not tried against this server. */
  caution?: string
  /** A closing sentence for the tab. */
  footer?: string
}

const bearer = `Bearer ${TOKEN_PLACEHOLDER}`
const headers = { Authorization: bearer }
const asJson = (value: unknown): string => JSON.stringify(value, null, 2)

export const bridgeLine = (endpoint: string): string => `npx mcp-remote ${endpoint} --header "Authorization: ${bearer}"`
export const cautionText = (app: string): string => `Check ${app}'s own docs if the setting names changed.`
export const OAUTH_NOTE = 'The claude.ai and ChatGPT connectors need OAuth, which this parent does not offer yet.'
export const BRIDGE_INTRO = 'Apps that can only run local programs or only speak the old SSE transport can use a bridge:'

/** The tabs in the order they are shown. */
export function appTabs(endpoint: string): AppTab[] {
  return [
    { id: 'claude-code', label: 'Claude Code', where: 'Run this in a terminal.', snippet: claudeLine(endpoint) },
    { id: 'cursor', label: 'Cursor', where: 'Put this in ~/.cursor/mcp.json', snippet: asJson({ mcpServers: { metaservice: { url: endpoint, headers } } }), caution: cautionText('Cursor') },
    { id: 'vscode', label: 'VS Code', where: 'Put this in .vscode/mcp.json', snippet: asJson({ servers: { metaservice: { type: 'http', url: endpoint, headers } } }), caution: cautionText('VS Code') },
    { id: 'opencode', label: 'OpenCode', where: 'Put this in opencode.json', snippet: asJson({ mcp: { metaservice: { type: 'remote', url: endpoint, headers } } }), caution: cautionText('OpenCode') },
    { id: 'gemini', label: 'Gemini CLI', where: 'Put this in ~/.gemini/settings.json', snippet: asJson({ mcpServers: { metaservice: { httpUrl: endpoint, headers } } }), caution: cautionText('Gemini CLI') },
    {
      id: 'other',
      label: 'Other apps',
      where: 'Any app that reads a JSON file of MCP servers takes this.',
      snippet: jsonSnippet(endpoint),
      extra: { intro: BRIDGE_INTRO, text: bridgeLine(endpoint) },
      footer: OAUTH_NOTE,
    },
  ]
}

const lastIndex = (count: number): number => count - 1

/** The tab a key press moves to, from the tab at `from` among `count` tabs; null when the key does nothing here. */
export function tabIndexForKey(from: number, count: number, key: string): number | null {
  if (key === 'ArrowRight') return from === lastIndex(count) ? 0 : from + 1
  if (key === 'ArrowLeft') return from === 0 ? lastIndex(count) : from - 1
  if (key === 'Home') return 0
  if (key === 'End') return lastIndex(count)
  return null
}

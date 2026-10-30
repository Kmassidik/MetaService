// A stand-in for the hub's public routes (CONTRACT section 4), just enough for the join script tests.
// The link's name picks the story: approve*, refuse*, expire*, badsha*. Any other link is unknown (404).
// Run: bun stub-hub.ts <join.sh> <log-folder>   It prints its port on the first line.
import { appendFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'

const [scriptPath, logDir] = process.argv.slice(2)
const AGENT_BODY = `#!/bin/sh
echo "$@" >> "$AGENT_LOG"
prev=
for word in "$@"; do
  [ "$prev" = --enrollment-token-file ] && echo "tokenmode $(stat -f %Lp "$word" 2>/dev/null || stat -c %a "$word")" >> "$AGENT_LOG"
  prev=$word
done
`
const AGENT_SHA = createHash('sha256').update(AGENT_BODY).digest('hex')
const WRONG_SHA = '0'.repeat(64)
const HUB_KEY = 'B'.repeat(43) + '='
const PENDING = 'p1'
const SECRET = 'secretvalue123'
const CODE = '482917'
const POLLS_BEFORE_ANSWER = 2
const STORIES = ['approve', 'lowered', 'refuse', 'expire', 'badsha']
const LOWERED_SHARE = { cores: 1, ram_mb: 2048, disk_gb: 10 }

type Link = { story: string; registered: boolean; polls: number; tokenGiven: boolean }
const links = new Map<string, Link>()

function story(link: string): string | undefined {
  return STORIES.find((name) => link.startsWith(name))
}
function linkFor(link: string): Link | undefined {
  const name = story(link)
  if (!name) return undefined
  if (!links.has(link)) links.set(link, { story: name, registered: false, polls: 0, tokenGiven: false })
  return links.get(link)
}
const json = (body: unknown, status = 200) => Response.json(body, { status })
const unknown = () => json({ error: 'unknown_link' }, 404)

function approved(state: Link) {
  const machine: Record<string, unknown> = { name: 'far-pc', parent_url: 'http://10.77.0.1:9102', helper_bind: '10.77.0.2', helper_port: 9101 }
  if (state.story === 'lowered') machine.share = LOWERED_SHARE
  if (!state.tokenGiven) machine.enrollment_token = 'tok-' + 'a'.repeat(40)
  state.tokenGiven = true
  const sha = state.story === 'badsha' ? WRONG_SHA : AGENT_SHA
  return {
    state: 'approved',
    wireguard: { address: '10.77.0.2/32', hub_public_key: HUB_KEY, endpoint: 'hub.example.test:51830', allowed_ips: '10.77.0.1/32', keepalive: 25 },
    machine,
    download: { url: `${server.url.origin}/dl/x/metaservice-agent?pending=${PENDING}&secret=${SECRET}`, sha256: sha },
  }
}

function status(state: Link) {
  state.polls += 1
  if (state.polls < POLLS_BEFORE_ANSWER) return { state: 'pending' }
  if (state.story === 'refuse') return { state: 'refused' }
  if (state.story === 'expire') return { state: 'expired' }
  return approved(state)
}

async function route(request: Request): Promise<Response> {
  const url = new URL(request.url)
  appendFileSync(`${logDir}/hub.log`, `${request.method} ${url.pathname}\n`)
  if (url.pathname.startsWith('/dl/')) return new Response(AGENT_BODY)
  const parts = url.pathname.split('/')
  const state = parts[1] === 'j' ? linkFor(parts[2] ?? '') : undefined
  if (!state) return unknown()
  if (parts.length === 3) return script(url, parts[2])
  if (parts[3] === 'register' && request.method === 'POST') return register(state, await request.text())
  return parts[3] === 'status' ? json(status(state)) : unknown()
}

async function script(url: URL, link: string): Promise<Response> {
  const template = await Bun.file(scriptPath).text()
  const filled = template.replace('@LINK@', link).replace('@PUBLIC_URL@', url.origin).replace('@OS@', url.searchParams.get('os') ?? '').replace('@CPU@', url.searchParams.get('cpu') ?? '')
  return new Response(filled, { headers: { 'content-type': 'text/x-shellscript' } })
}

function register(state: Link, body: string): Response {
  if (state.registered) return unknown()
  state.registered = true
  writeFileSync(`${logDir}/register.json`, body)
  return json({ pending: PENDING, secret: SECRET, code: CODE, expires_in: 900 })
}

const server = Bun.serve({ port: 0, hostname: '127.0.0.1', fetch: route })
console.log(server.port)

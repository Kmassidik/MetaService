// The admin page of the join-share hub. Plain script, no framework, no build step.
// Text from far PCs (host names) is only ever put on the page with textContent, never as HTML.
'use strict'

const REFRESH_MS = 4000
const COPIED_MS = 1800
const OS_NAMES = { mac: 'Mac', windows: 'Windows', linux: 'Linux' }
const CPU_NAMES = { arm64: 'Apple silicon / ARM (arm64)', x86_64: 'Intel / AMD (x86_64)' }
const STATE_TEXT = {
  ready: { tag: 'ready', kind: 'run', why: '' },
  untested: { tag: 'not tested yet', kind: 'warn', why: 'A build exists but has not been proven on this kind of computer yet. It may not work.' },
  missing: { tag: 'no build yet', kind: '', why: 'There is no helper build for this computer yet.' },
  soon: { tag: 'coming soon', kind: '', why: 'This system is coming soon.' },
}
const ERROR_TEXT = {
  unauthorized: 'The admin key is wrong.',
  network: 'The hub cannot be reached. Check that it is running.',
  rate_limited: 'Too many tries. Wait a minute and try again.',
  name_taken: 'That name is already used. Choose another name.',
  expired: 'This request has expired. The person has to run a new command.',
  not_pending: 'This request is no longer waiting.',
  unknown_pending: 'This request is gone.',
  unknown_peer: 'This machine is not in the list any more.',
  bad_name: 'The name may only have letters, digits, dot, dash and underscore.',
  bad_share: 'The share numbers must be whole numbers above zero.',
  share_too_high: 'You can lower the share the person offered, not raise it.',
  network_full: 'The WireGuard network has no free address left.',
  wireguard_failed: 'WireGuard on the hub failed. Look at the hub log.',
  locked: 'Too many wrong codes. This request was refused.',
  no_build: 'There is no helper build for this computer yet.',
  windows_soon: 'Windows is coming soon.',
}

const app = { key: '', supported: [], os: '', cpu: '', pending: [], peers: [], drafts: {}, shown: {} }

// ---- small tools ------------------------------------------------------------------------------

const $ = (id) => document.getElementById(id)

function el(tag, options = {}, ...children) {
  const node = document.createElement(tag)
  if (options.class) node.className = options.class
  if (options.text !== undefined) node.textContent = options.text
  for (const [name, value] of Object.entries(options.attrs ?? {})) node.setAttribute(name, value)
  for (const child of children) node.append(child)
  return node
}

function show(node, text) {
  node.textContent = text
  node.hidden = text === ''
}

function describeError(status, data) {
  const code = data && data.error
  const known = ERROR_TEXT[code]
  if (code === 'wrong_code') return `That code is wrong. ${data.tries_left} ${data.tries_left === 1 ? 'try' : 'tries'} left.`
  if (known) return known
  if (data && data.reason) return String(data.reason)
  return `The hub answered with an error (${code || 'HTTP ' + status}).`
}

/** One call to the admin API. Never throws: a failure comes back as { ok: false, status, data }. */
async function api(method, path, body) {
  const headers = { 'X-Admin-Key': app.key }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  try {
    const reply = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
    const data = await reply.json().catch(() => null)
    return { ok: reply.ok, status: reply.status, data }
  } catch {
    return { ok: false, status: 0, data: { error: 'network' } }
  }
}

function timeLeft(iso) {
  const seconds = Math.round((Date.parse(iso) - Date.now()) / 1000)
  if (!Number.isFinite(seconds)) return ''
  if (seconds <= 0) return 'expired'
  return seconds < 90 ? `${seconds} s left` : `${Math.round(seconds / 60)} min left`
}

function ago(seconds) {
  if (seconds === null || seconds === undefined) return 'never'
  if (seconds < 90) return `${seconds} s ago`
  if (seconds < 5400) return `${Math.round(seconds / 60)} min ago`
  return `${Math.round(seconds / 3600)} h ago`
}

function saneName(hostname) {
  const name = String(hostname).toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '')
  return name || 'far-pc'
}

// ---- the key ----------------------------------------------------------------------------------

/** The key may come in the URL fragment (#key=...). It is read once, then removed from the address bar; it is never in a query string. */
function takeKeyFromFragment() {
  const match = /(?:^#|&)key=([^&]*)/.exec(location.hash)
  if (!match) return ''
  history.replaceState(null, '', location.pathname + location.search)
  return decodeURIComponent(match[1])
}

async function tryKey(key) {
  app.key = key
  const reply = await api('GET', '/admin/supported')
  if (!reply.ok) return reply
  app.supported = Array.isArray(reply.data) ? reply.data : []
  $('gate').hidden = true
  $('app').hidden = false
  renderChoices()
  await refresh()
  setInterval(refresh, REFRESH_MS)
  return reply
}

async function submitKey(event) {
  event.preventDefault()
  const key = $('key-input').value.trim()
  if (!key) return show($('gate-error'), 'Type the admin key first.')
  const reply = await tryKey(key)
  if (reply.ok) return
  app.key = ''
  show($('gate-error'), describeError(reply.status, reply.data))
}

// ---- the three buttons, the CPU choices and the command ---------------------------------------

function stateOf(os, cpu) {
  const row = app.supported.find((entry) => entry.os === os)
  const found = row && row.cpus.find((entry) => entry.cpu === cpu)
  return found ? found.state : 'missing'
}

function choiceButton(label, pressed, onClick, stateName) {
  const spec = STATE_TEXT[stateName]
  const button = el('button', { class: 'choice', attrs: { type: 'button', 'aria-pressed': String(pressed) } }, el('span', { text: label }))
  if (spec) button.append(el('span', { class: 'tag ' + spec.kind, text: spec.tag }))
  button.disabled = stateName === 'missing' || stateName === 'soon'
  button.addEventListener('click', onClick)
  return button
}

function renderChoices() {
  const osBox = $('os-buttons')
  osBox.replaceChildren(...app.supported.map((row) => choiceButton(OS_NAMES[row.os] ?? row.os, app.os === row.os, () => pickOs(row.os))))
  const row = app.supported.find((entry) => entry.os === app.os)
  const cpus = row ? row.cpus : []
  $('cpu-buttons').replaceChildren(...cpus.map((entry) => choiceButton(CPU_NAMES[entry.cpu] ?? entry.cpu, app.cpu === entry.cpu, () => pickCpu(entry.cpu), entry.state)))
  $('cpu-buttons').hidden = !row
  $('cpu-note').textContent = row ? cpuNote(row) : 'Choose a system first.'
  $('make').disabled = !(app.os && app.cpu)
}

function cpuNote(row) {
  const chosen = row.cpus.find((entry) => entry.cpu === app.cpu)
  if (chosen) return STATE_TEXT[chosen.state].why
  const blocked = row.cpus.filter((entry) => STATE_TEXT[entry.state].why && (entry.state === 'missing' || entry.state === 'soon'))
  return blocked.length ? `${blocked.map((entry) => CPU_NAMES[entry.cpu] ?? entry.cpu).join(' and ')}: ${STATE_TEXT[blocked[0].state].why}` : ''
}

function pickOs(os) {
  app.os = os
  app.cpu = ''
  $('command-box').hidden = true
  renderChoices()
}

function pickCpu(cpu) {
  app.cpu = cpu
  $('command-box').hidden = true
  show($('make-error'), '')
  renderChoices()
}

async function makeCommand() {
  const button = $('make')
  button.disabled = true
  button.setAttribute('aria-busy', 'true')
  const reply = await api('POST', '/admin/links', { os: app.os, cpu: app.cpu })
  button.removeAttribute('aria-busy')
  button.disabled = false
  show($('make-error'), reply.ok ? '' : describeError(reply.status, reply.data))
  if (!reply.ok) return
  $('command').textContent = reply.data.command
  $('command-note').textContent = `Run it once on the ${OS_NAMES[app.os]} computer. ${timeLeft(reply.data.expires_at)}.`
  $('command-box').hidden = false
}

async function copyCommand() {
  const button = $('copy')
  const text = $('command').textContent
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    window.getSelection().selectAllChildren($('command'))
    button.textContent = 'Select and copy by hand'
    return
  }
  button.textContent = 'Copied'
  setTimeout(() => { button.textContent = 'Copy' }, COPIED_MS)
}

// ---- waiting machines -------------------------------------------------------------------------

function draftOf(machine) {
  if (!app.drafts[machine.id]) {
    app.drafts[machine.id] = { code: '', name: saneName(machine.hostname), cores: machine.share.cores, ram_mb: machine.share.ram_mb, disk_gb: machine.share.disk_gb, error: '' }
  }
  return app.drafts[machine.id]
}

function field(draft, key, options) {
  const input = el('input', options)
  input.value = draft[key]
  input.addEventListener('input', () => { draft[key] = input.value })
  return input
}

function shareInputs(draft) {
  const box = el('div', { class: 'share' })
  for (const [key, label] of [['cores', 'cores'], ['ram_mb', 'RAM MB'], ['disk_gb', 'disk GB']]) {
    box.append(el('label', {}, el('span', { text: label }), field(draft, key, { attrs: { type: 'number', min: '1', 'aria-label': label } })))
  }
  return box
}

function pendingRow(machine) {
  const draft = draftOf(machine)
  const codeInput = field(draft, 'code', { class: 'code', attrs: { inputmode: 'numeric', maxlength: '6', autocomplete: 'off', placeholder: '000000', 'aria-label': `Code from ${machine.hostname}` } })
  const error = el('p', { class: 'rowerror', text: draft.error, attrs: { role: 'alert' } })
  error.hidden = draft.error === ''
  const approve = el('button', { class: 'btn green sm', text: 'Approve', attrs: { type: 'button' } })
  const refuse = el('button', { class: 'btn danger sm', text: 'Refuse', attrs: { type: 'button' } })
  approve.addEventListener('click', () => approveMachine(machine, draft, error, approve))
  refuse.addEventListener('click', () => refuseMachine(machine, error))
  const who = el('td', { class: 'c-name', attrs: { 'data-label': 'Machine' } }, el('div', { text: machine.hostname }),
    el('div', { class: 'small', text: `${OS_NAMES[machine.os] ?? machine.os} ${machine.cpu} - ${timeLeft(machine.expires_at)} - ${machine.tries_left} tries left` }),
    field(draft, 'name', { class: 'name', attrs: { 'aria-label': `Name for ${machine.hostname}`, spellcheck: 'false' } }))
  return el('tr', {}, who,
    el('td', { attrs: { 'data-label': 'Share (you can lower it)' } }, shareInputs(draft)),
    el('td', { attrs: { 'data-label': 'Code from its screen' } }, codeInput),
    el('td', { attrs: { 'data-label': '' } }, el('div', { class: 'acts' }, approve, refuse), error))
}

function table(headings, rows) {
  const head = el('tr', {}, ...headings.map((text) => el('th', { text })))
  return el('div', { class: 'tablewrap' }, el('table', { class: 'restable' }, el('thead', {}, head), el('tbody', {}, ...rows)))
}

function renderPending() {
  const box = $('pending')
  if (app.pending.length === 0) return box.replaceChildren(el('p', { class: 'muted', text: 'Nobody is waiting. When a far PC runs the command, it shows up here.' }))
  box.replaceChildren(table(['Machine', 'Share (you can lower it)', 'Code from its screen', ''], app.pending.map(pendingRow)))
}

async function approveMachine(machine, draft, error, button) {
  const share = { cores: Number(draft.cores), ram_mb: Number(draft.ram_mb), disk_gb: Number(draft.disk_gb) }
  button.disabled = true
  const reply = await api('POST', `/admin/pending/${encodeURIComponent(machine.id)}/approve`, { code: draft.code.trim(), name: draft.name.trim(), share })
  button.disabled = false
  draft.error = reply.ok ? '' : describeError(reply.status, reply.data)
  if (reply.ok) delete app.drafts[machine.id]
  if (reply.status === 403 && reply.data.error === 'wrong_code') draft.code = ''
  await refresh(true)
}

async function refuseMachine(machine, error) {
  const reply = await api('POST', `/admin/pending/${encodeURIComponent(machine.id)}/refuse`)
  if (!reply.ok) return show(error, describeError(reply.status, reply.data))
  delete app.drafts[machine.id]
  await refresh(true)
}

// ---- joined machines --------------------------------------------------------------------------

function peerRow(peer) {
  const remove = el('button', { class: 'btn danger sm', text: 'Remove', attrs: { type: 'button', 'aria-label': `Remove ${peer.name}` } })
  const error = el('p', { class: 'rowerror', attrs: { role: 'alert' } })
  error.hidden = true
  remove.addEventListener('click', () => removePeer(peer, error))
  return el('tr', {},
    el('td', { class: 'c-name', text: peer.name, attrs: { 'data-label': 'Name' } }),
    el('td', { class: 'small', text: peer.address, attrs: { 'data-label': 'Address' } }),
    el('td', { text: `${OS_NAMES[peer.os] ?? peer.os} ${peer.cpu}`, attrs: { 'data-label': 'System' } }),
    el('td', { class: 'small', text: peer.public_key, attrs: { 'data-label': 'Key' } }),
    el('td', { text: ago(peer.last_handshake_secs_ago), attrs: { 'data-label': 'Last handshake' } }),
    el('td', { attrs: { 'data-label': '' } }, remove, error))
}

function renderPeers() {
  const box = $('peers')
  if (app.peers.length === 0) return box.replaceChildren(el('p', { class: 'muted', text: 'No machine has joined yet.' }))
  box.replaceChildren(table(['Name', 'Address', 'System', 'Key', 'Last handshake', ''], app.peers.map(peerRow)))
}

async function removePeer(peer, error) {
  const reply = await api('DELETE', `/admin/peers/${encodeURIComponent(peer.name)}`)
  if (!reply.ok) return show(error, describeError(reply.status, reply.data))
  await refresh(true)
}

// ---- refresh ----------------------------------------------------------------------------------

/** Loads both lists. A list is redrawn only when it changed (or when forced), so a half-typed code is not lost. */
async function refresh(force = false) {
  const [pending, peers] = await Promise.all([api('GET', '/admin/pending'), api('GET', '/admin/peers')])
  loadList('pending', pending, renderPending, force)
  loadList('peers', peers, renderPeers, force)
}

function loadList(name, reply, render, force) {
  if (!reply.ok) {
    $(name).replaceChildren(el('p', { class: 'note bad', text: describeError(reply.status, reply.data), attrs: { role: 'alert' } }))
    app.shown[name] = ''
    return
  }
  const signature = JSON.stringify(reply.data)
  app[name] = Array.isArray(reply.data) ? reply.data : []
  if (!force && app.shown[name] === signature) return
  app.shown[name] = signature
  render()
}

// ---- start ------------------------------------------------------------------------------------

async function start() {
  $('gate-form').addEventListener('submit', submitKey)
  $('make').addEventListener('click', makeCommand)
  $('copy').addEventListener('click', copyCommand)
  const key = takeKeyFromFragment()
  $('gate').hidden = false
  if (!key) return
  const reply = await tryKey(key)
  if (!reply.ok) show($('gate-error'), describeError(reply.status, reply.data))
}

start()

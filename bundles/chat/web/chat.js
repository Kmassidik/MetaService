// The access key arrives in the address after the #, never in a request. It is kept in memory only and removed from the address bar.
const key = new URLSearchParams(location.hash.slice(1)).get('k')
history.replaceState(null, '', location.pathname)

const scroller = document.getElementById('scroll')
const empty = document.getElementById('empty')
const log = document.getElementById('log')
const form = document.getElementById('form')
const input = document.getElementById('input')
const send = document.getElementById('send')
const state = document.getElementById('state')
const MAX_INPUT_HEIGHT = 160

function addRow(kind, node) {
  empty.hidden = true
  const row = document.createElement('li')
  row.className = `row ${kind}`
  row.append(node)
  log.append(row)
  scroller.scrollTop = scroller.scrollHeight
  return row
}

function addMessage(text, kind) {
  const bubble = document.createElement('div')
  bubble.className = 'bubble'
  bubble.textContent = text
  return addRow(kind, bubble)
}

function addTyping() {
  const dots = document.createElement('div')
  dots.className = 'typing'
  dots.setAttribute('aria-label', 'Ruvio is typing')
  dots.append(document.createElement('span'), document.createElement('span'), document.createElement('span'))
  return addRow('theirs', dots)
}

async function ask(message) {
  const response = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
    body: JSON.stringify({ message }),
    cache: 'no-store',
  })
  const data = await response.json().catch(() => null)
  if (!response.ok) throw new Error(data?.error?.message ?? 'Something went wrong.')
  return data.reply
}

function fitInput() {
  input.style.height = 'auto'
  input.style.height = `${Math.min(input.scrollHeight, MAX_INPUT_HEIGHT)}px`
}

async function submit() {
  const message = input.value.trim()
  if (!message || send.disabled) return
  input.value = ''
  fitInput()
  addMessage(message, 'mine')
  send.disabled = true
  const typing = addTyping()
  try {
    const reply = await ask(message)
    typing.remove()
    addMessage(reply, 'theirs')
  } catch (error) {
    typing.remove()
    addMessage(error.message, 'theirs problem')
  } finally {
    send.disabled = false
    input.focus()
  }
}

form.addEventListener('submit', (event) => {
  event.preventDefault()
  submit()
})
input.addEventListener('input', fitInput)
input.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return
  event.preventDefault()
  submit()
})

if (!key) {
  state.textContent = 'Open this chat from the MetaService panel.'
  send.disabled = true
  input.disabled = true
}

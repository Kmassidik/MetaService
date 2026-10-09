// The access key arrives in the address after the #, never in a request. It is kept in memory only and removed from the address bar.
const key = new URLSearchParams(location.hash.slice(1)).get('k')
history.replaceState(null, '', location.pathname)

const log = document.getElementById('log')
const form = document.getElementById('form')
const input = document.getElementById('input')
const state = document.getElementById('state')

function add(text, kind) {
  const item = document.createElement('li')
  item.className = kind
  item.textContent = text
  log.append(item)
  item.scrollIntoView({ block: 'end' })
}

async function send(message) {
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

form.addEventListener('submit', async (event) => {
  event.preventDefault()
  const message = input.value.trim()
  if (!message) return
  input.value = ''
  add(message, 'me')
  form.querySelector('button').disabled = true
  try {
    add(await send(message), 'them')
  } catch (error) {
    add(error.message, 'problem')
  } finally {
    form.querySelector('button').disabled = false
    input.focus()
  }
})

if (!key) {
  state.textContent = 'Open this chat from the MetaService panel.'
  form.querySelector('button').disabled = true
}

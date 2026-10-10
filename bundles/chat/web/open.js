// Opens the chat with the access key from the address (after the #). The key is sent once, kept nowhere, and removed from the address bar;
// the chat then runs on a session the server keeps.
const message = document.getElementById('message')
const key = new URLSearchParams(location.hash.slice(1)).get('k')
history.replaceState(null, '', location.pathname)

async function open() {
  if (!key) {
    message.textContent = 'Open this chat from the MetaService panel.'
    return
  }
  try {
    const response = await fetch('/auth/open', { method: 'POST', headers: { Authorization: `Bearer ${key}` }, cache: 'no-store' })
    if (response.ok) {
      location.replace('/')
      return
    }
    message.textContent = 'This link no longer works. Open the chat again from the MetaService panel.'
  } catch {
    message.textContent = 'Cannot reach the chat. Check that this machine is on, then open it again from the MetaService panel.'
  }
}

open()

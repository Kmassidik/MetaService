import { notificationsMuted } from './notifications.js'

export function notifyBrowser(title, body) {
  try {
    if (typeof Notification === 'undefined' || document.visibilityState === 'visible' || notificationsMuted()) return
    if (Notification.permission === 'granted') new Notification(title, { body, tag: 'ruvio-chat' })
    else if (Notification.permission === 'default') Notification.requestPermission()
  } catch {}
}

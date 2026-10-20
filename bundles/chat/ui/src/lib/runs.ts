import { notificationsMuted } from './notifications.ts'

export function notifyBrowser(title: string, body: string): void {
  try {
    if (typeof Notification === 'undefined' || document.visibilityState === 'visible' || notificationsMuted()) return
    if (Notification.permission === 'granted') new Notification(title, { body, tag: 'ruvio-chat' })
    else if (Notification.permission === 'default') Notification.requestPermission()
  } catch {
    // A browser that cannot notify must never break the run that asked.
  }
}

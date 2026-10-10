/**
 * Browser notifications for this device: the browser's permission plus Ruvio's own on/off
 * switch, so someone can mute Ruvio without digging through browser settings. Which events
 * notify ("needs input", "finished") is chosen per bot in its profile.
 */
import { readDevice, writeDevice } from './deviceStore.js'

export const NOTIFICATIONS_KEY = 'ruvio-notifications'
const MUTED = 'off'
const ON = 'on'
export const PERMISSION = Object.freeze({
  unsupported: 'unsupported',
  default: 'default',
  granted: 'granted',
  denied: 'denied',
})

export function notificationPermission() {
  if (typeof Notification === 'undefined') return PERMISSION.unsupported
  return Notification.permission
}

export function notificationsMuted(storage) {
  return readDevice(NOTIFICATIONS_KEY, storage) === MUTED
}

/** On only when the browser allows it and this device hasn't muted Ruvio. */
export function notificationsOn(permission, muted) {
  return permission === PERMISSION.granted && !muted
}

/** Turning on asks the browser once; returns the permission it ends with. */
export async function enableNotifications() {
  writeDevice(NOTIFICATIONS_KEY, ON)
  if (notificationPermission() !== PERMISSION.default) return notificationPermission()
  return Notification.requestPermission()
}

export function muteNotifications() {
  return writeDevice(NOTIFICATIONS_KEY, MUTED)
}

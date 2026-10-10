import { MiB } from './constants.js'

export function initials(name = '') {
  return name.trim().split(/\s+/).slice(0, 2).map(word => word[0]).join('').toUpperCase() || 'M'
}

export function number(value) {
  return typeof value === 'number' ? new Intl.NumberFormat().format(value) : '—'
}

export function time(value) {
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? '' : date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

export function fail(error) {
  return error.name === 'AbortError'
    ? 'The connection was interrupted. Reload the conversation to check whether your request completed.'
    : error.message || 'Something went wrong. Please try again.'
}

export function fileSize(size) {
  return size < 1024 ? `${size} B` : size < MiB ? `${(size / 1024).toFixed(1)} KiB` : `${(size / MiB).toFixed(1)} MiB`
}

export const bytes = value => new TextEncoder().encode(value).length

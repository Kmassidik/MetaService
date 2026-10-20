import { MiB } from './constants.ts'
import { errorMessage, errorName } from './errors.ts'

export function initials(name = ''): string {
  return name.trim().split(/\s+/).slice(0, 2).map(word => word[0]).join('').toUpperCase() || 'M'
}

export function number(value: unknown): string {
  return typeof value === 'number' ? new Intl.NumberFormat().format(value) : '—'
}

export function time(value: string | number | Date): string {
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? '' : date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

export function fail(error: unknown): string {
  return errorName(error) === 'AbortError'
    ? 'The connection was interrupted. Reload the conversation to check whether your request completed.'
    : errorMessage(error) || 'Something went wrong. Please try again.'
}

export function fileSize(size: number): string {
  return size < 1024 ? `${size} B` : size < MiB ? `${(size / 1024).toFixed(1)} KiB` : `${(size / MiB).toFixed(1)} MiB`
}

export const bytes = (value: string): number => new TextEncoder().encode(value).length

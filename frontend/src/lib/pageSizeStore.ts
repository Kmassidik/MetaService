// Remembers the page size a person chose for each list, in localStorage. Storage can be missing or refuse (private window, blocked site data); then the
// default is used and nothing is remembered. Nothing else is ever read from or written to storage here.
import { DEFAULT_PAGE_SIZE, isPageSize } from './paging.ts'

const KEY_PREFIX = 'metaservice.pageSize.'

/** The saved page size of a list, or null when there is none, it is not an offered size, or storage cannot be read. */
export function readPageSize(list: string): number | null {
  try {
    const saved = Number(localStorage.getItem(KEY_PREFIX + list))
    return isPageSize(saved) ? saved : null
  } catch {
    return null
  }
}

/** Saves the page size of a list. Returns false when storage refused (the choice then holds only until the page is closed). */
export function savePageSize(list: string, size: number): boolean {
  try {
    localStorage.setItem(KEY_PREFIX + list, String(size))
    return true
  } catch {
    return false
  }
}

export const sizeOrDefault = (saved: number | null, fallback: number = DEFAULT_PAGE_SIZE): number => saved ?? fallback

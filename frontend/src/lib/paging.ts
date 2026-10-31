// Paging of long lists, as pure functions: how many pages there are, which page is shown, which rows belong to it, the "Showing 51 to 100 of 340" line and the
// short row of page numbers with gaps ("1 … 4 5 6 … 20"). No DOM, no storage; the Pager (pager.svelte.ts) and the Pagination component use these.

/** The page sizes a person may choose, and the one used until they choose. */
export const PAGE_SIZES = [25, 50, 100] as const
export const DEFAULT_PAGE_SIZE = 50
/** How many page numbers on each side of the current page are always shown. */
const NEIGHBOURS = 1

export type PageItem = { kind: 'page'; page: number } | { kind: 'gap'; after: number }

/** True when `value` is one of the offered page sizes. */
export const isPageSize = (value: unknown): value is (typeof PAGE_SIZES)[number] => PAGE_SIZES.some((size) => size === value)

/** The number of pages for `total` rows; an empty list still has one (empty) page. */
export const pageCount = (total: number, size: number): number => Math.max(1, Math.ceil(total / size))

/** A page number brought into 1 .. last page. A value that is not a whole number gives page 1. */
export function clampPage(page: number, total: number, size: number): number {
  if (!Number.isInteger(page)) return 1
  return Math.min(Math.max(page, 1), pageCount(total, size))
}

/** Where a page starts and ends in the list (end is exclusive), after the page was brought into range. */
export function pageBounds(page: number, total: number, size: number): { page: number; start: number; end: number } {
  const current = clampPage(page, total, size)
  const start = (current - 1) * size
  return { page: current, start, end: Math.min(start + size, total) }
}

/** The rows of one page. The row objects are the same ones as in the list. */
export function slicePage<T>(rows: readonly T[], page: number, size: number): T[] {
  const { start, end } = pageBounds(page, rows.length, size)
  return rows.slice(start, end)
}

/** "Showing 51 to 100 of 340", or "Showing 0 of 0" for an empty list. */
export function showingText(page: number, total: number, size: number): string {
  if (total === 0) return 'Showing 0 of 0'
  const { start, end } = pageBounds(page, total, size)
  return `Showing ${(start + 1).toLocaleString('en-US')} to ${end.toLocaleString('en-US')} of ${total.toLocaleString('en-US')}`
}

/** The first page, the last page, the current page and its neighbours; a gap where pages are left out. One missing page is shown, not hidden behind a gap. */
export function pageItems(page: number, count: number): PageItem[] {
  const wanted = new Set([1, count])
  for (let near = page - NEIGHBOURS; near <= page + NEIGHBOURS; near += 1) wanted.add(near)
  const pages = [...wanted].filter((number) => number >= 1 && number <= count).sort((a, b) => a - b)
  const items: PageItem[] = []
  pages.forEach((number, index) => {
    const before = pages[index - 1]
    if (before !== undefined && number - before === 2) items.push({ kind: 'page', page: before + 1 })
    if (before !== undefined && number - before > 2) items.push({ kind: 'gap', after: before })
    items.push({ kind: 'page', page: number })
  })
  return items
}

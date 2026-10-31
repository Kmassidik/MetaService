// The paging state of one list: the current page and the page size (remembered per list). A list makes one Pager, asks it for the window of its rows and
// shows <Pagination>. The page is brought into range every time it is read, so rows that disappear while someone is on page 5 land them on the last page;
// resetWhen() sends the person back to page 1 when a filter, search or the data set changes.
import { DEFAULT_PAGE_SIZE, pageBounds, slicePage } from './paging.ts'
import { readPageSize, savePageSize, sizeOrDefault } from './pageSizeStore.ts'

export interface PageWindow {
  page: number
  start: number
  end: number
}

export class Pager {
  size = $state(DEFAULT_PAGE_SIZE)
  #wanted = $state(1)
  readonly list: string

  /** `list` names the list for the saved page size; `fallbackSize` is used when nothing was saved (the process list starts at 25). */
  constructor(list: string, fallbackSize = DEFAULT_PAGE_SIZE) {
    this.list = list
    this.size = sizeOrDefault(readPageSize(list), fallbackSize)
  }

  /** The page asked for, not yet brought into range (a list that fetches one page at a time asks the server for this one). */
  get wanted(): number {
    return this.#wanted
  }

  /** Where the page is in a list of `total` rows, the page brought into range. */
  window(total: number): PageWindow {
    return pageBounds(this.#wanted, total, this.size)
  }

  /** The rows of the page being shown. */
  slice<T>(rows: readonly T[]): T[] {
    return slicePage(rows, this.#wanted, this.size)
  }

  go(page: number): void {
    this.#wanted = page
  }

  /** A new page size; the person goes back to page 1 and the choice is remembered. */
  resize(size: number): void {
    this.size = size
    this.#wanted = 1
    savePageSize(this.list, size)
  }

  reset(): void {
    this.#wanted = 1
  }

  /** Back to page 1 whenever the key changes (not at the first run). Call it while the component is being made. */
  resetWhen(key: () => string): void {
    let last: string | null = null
    $effect(() => {
      const now = key()
      if (last !== null && last !== now) this.reset()
      last = now
    })
  }
}

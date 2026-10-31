import { describe, expect, test } from 'bun:test'
import { DEFAULT_PAGE_SIZE, PAGE_SIZES, clampPage, isPageSize, pageBounds, pageCount, pageItems, showingText, slicePage, type PageItem } from './paging.ts'

const shape = (items: PageItem[]): string => items.map((item) => (item.kind === 'gap' ? '…' : String(item.page))).join(' ')

describe('page sizes', () => {
  test('25, 50 and 100, with 50 as the default', () => {
    expect([...PAGE_SIZES]).toEqual([25, 50, 100])
    expect(DEFAULT_PAGE_SIZE).toBe(50)
  })
  test('only an offered size is a page size', () => {
    expect(isPageSize(25)).toBe(true)
    expect(isPageSize(30)).toBe(false)
    expect(isPageSize('50')).toBe(false)
  })
})

describe('pageCount and clampPage', () => {
  test('counts pages, an empty list has one', () => {
    expect(pageCount(0, 50)).toBe(1)
    expect(pageCount(50, 50)).toBe(1)
    expect(pageCount(51, 50)).toBe(2)
    expect(pageCount(340, 50)).toBe(7)
  })
  test('brings a page into range', () => {
    expect(clampPage(0, 340, 50)).toBe(1)
    expect(clampPage(-3, 340, 50)).toBe(1)
    expect(clampPage(99, 340, 50)).toBe(7)
    expect(clampPage(Number.NaN, 340, 50)).toBe(1)
    expect(clampPage(2.5, 340, 50)).toBe(1)
  })
  test('a list that shrank under the page lands on the last page', () => {
    expect(clampPage(5, 120, 50)).toBe(3)
    expect(clampPage(5, 0, 50)).toBe(1)
  })
})

describe('slicePage and pageBounds', () => {
  const rows = Array.from({ length: 120 }, (_, index) => index)
  test('cuts the page and keeps the same row values', () => {
    expect(slicePage(rows, 1, 50)).toEqual(rows.slice(0, 50))
    expect(slicePage(rows, 3, 50)).toEqual(rows.slice(100, 120))
  })
  test('an out of range page gives the nearest one', () => {
    expect(slicePage(rows, 9, 50)).toEqual(rows.slice(100, 120))
    expect(slicePage(rows, 0, 50)).toEqual(rows.slice(0, 50))
  })
  test('bounds', () => {
    expect(pageBounds(2, 120, 50)).toEqual({ page: 2, start: 50, end: 100 })
    expect(pageBounds(1, 0, 50)).toEqual({ page: 1, start: 0, end: 0 })
  })
})

describe('showingText', () => {
  test('says which rows of how many', () => {
    expect(showingText(2, 340, 50)).toBe('Showing 51 to 100 of 340')
    expect(showingText(7, 340, 50)).toBe('Showing 301 to 340 of 340')
    expect(showingText(1, 5000, 100)).toBe('Showing 1 to 100 of 5,000')
  })
  test('an empty list', () => {
    expect(showingText(1, 0, 50)).toBe('Showing 0 of 0')
  })
})

describe('pageItems', () => {
  test('few pages are all shown', () => {
    expect(shape(pageItems(1, 1))).toBe('1')
    expect(shape(pageItems(2, 4))).toBe('1 2 3 4')
  })
  test('gaps at the far side of the current page', () => {
    expect(shape(pageItems(1, 20))).toBe('1 2 … 20')
    expect(shape(pageItems(10, 20))).toBe('1 … 9 10 11 … 20')
    expect(shape(pageItems(20, 20))).toBe('1 … 19 20')
  })
  test('a gap of exactly one page shows that page instead', () => {
    expect(shape(pageItems(4, 20))).toBe('1 2 3 4 5 … 20')
    expect(shape(pageItems(17, 20))).toBe('1 … 16 17 18 19 20')
  })
})

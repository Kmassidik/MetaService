// Takes the pictures of the page that is open now: one at desktop width (the window) and one at phone width (the whole page).
import type { Page } from 'puppeteer-core'
import { SIZES, shotName, type PageId, type SizeId } from '../../src/lib/shotNames.ts'

const SIZE_IDS: readonly SizeId[] = ['desktop', 'phone']

export async function capture(page: Page, dir: string, pageId: PageId): Promise<void> {
  for (const size of SIZE_IDS) {
    await page.setViewport(SIZES[size])
    await page.screenshot({ path: `${dir}/${shotName(pageId, size)}`, fullPage: size === 'phone' })
  }
  await page.setViewport(SIZES.desktop)
}

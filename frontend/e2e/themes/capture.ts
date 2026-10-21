// Takes the pictures of the page that is open now in every colour set and size, and builds the side-by-side sheets from them.
import { writeFileSync } from 'node:fs'
import type { Browser, Page } from 'puppeteer-core'
import { PAGES, SIZES, THEMES, compareName, shotName, type PageId, type SizeId } from '../../src/lib/themeShots.ts'
import { SHEET_WIDTH, sheetHtml } from '../../src/lib/themeSheet.ts'

const REPAINT_MS = 150
const SHEET_HEIGHT = 900
const SIZE_IDS: readonly SizeId[] = ['desktop', 'phone']

/** Switches the colour set of the open page. An empty attribute is today's colours. */
async function useTheme(page: Page, attribute: string): Promise<void> {
  await page.evaluate((value) => {
    if (value === '') delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = value
  }, attribute)
  await new Promise((done) => setTimeout(done, REPAINT_MS))
}

/** Pictures of the open page: each colour set at each size. A phone picture is the whole page, a desktop picture is the window. */
export async function captureAllThemes(page: Page, dir: string, pageId: PageId): Promise<void> {
  for (const size of SIZE_IDS) {
    await page.setViewport(SIZES[size])
    for (const theme of THEMES) {
      await useTheme(page, theme.attribute)
      await page.screenshot({ path: `${dir}/${shotName(theme.id, pageId, size)}`, fullPage: size === 'phone' })
    }
  }
  await page.setViewport(SIZES.desktop)
  await useTheme(page, '')
}

/** One picture per page that puts today, A and B side by side, made from the pictures already saved in `dir`. */
export async function buildComparisons(browser: Browser, dir: string): Promise<void> {
  const page = await browser.newPage()
  await page.setViewport({ width: SHEET_WIDTH, height: SHEET_HEIGHT })
  for (const entry of PAGES) {
    const columns = THEMES.map((theme) => ({ label: theme.label, desktopFile: shotName(theme.id, entry.id, 'desktop'), phoneFile: shotName(theme.id, entry.id, 'phone') }))
    const sheet = `${dir}/compare-${entry.id}.html`
    writeFileSync(sheet, sheetHtml(entry.label, columns))
    await page.goto(`file://${sheet}`, { waitUntil: 'load' })
    await page.screenshot({ path: `${dir}/${compareName(entry.id)}`, fullPage: true })
  }
  await page.close()
}

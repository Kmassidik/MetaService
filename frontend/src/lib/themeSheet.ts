// The page that puts today, A and B of one panel page side by side (desktop pictures on top, phone pictures below), to be opened in a browser and photographed.

export interface SheetColumn {
  label: string
  desktopFile: string
  phoneFile: string
}

/** The width of the finished sheet; every desktop picture is shrunk to a third of it. */
export const SHEET_WIDTH = 3300
const GAP = 24

const ESCAPES: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }
export const escapeHtml = (text: string): string => text.replace(/[&<>"]/g, (char) => ESCAPES[char] ?? char)

const column = (entry: SheetColumn): string => `<figure>
  <figcaption>${escapeHtml(entry.label)}</figcaption>
  <img class="desktop" src="${escapeHtml(entry.desktopFile)}" alt="${escapeHtml(entry.label)}, desktop">
  <img class="phone" src="${escapeHtml(entry.phoneFile)}" alt="${escapeHtml(entry.label)}, phone">
</figure>`

/** The sheet as a page of HTML. The picture files are named relative to the page, so it must be saved next to them. */
export function sheetHtml(title: string, columns: readonly SheetColumn[]): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>${escapeHtml(title)}</title>
<style>
  body { margin: 0; padding: ${GAP}px; width: ${SHEET_WIDTH}px; box-sizing: border-box; background: #d8d8d8; font: 20px/1.3 system-ui, sans-serif; color: #111; }
  h1 { margin: 0 0 ${GAP}px; font-size: 30px; }
  .row { display: grid; grid-template-columns: repeat(${columns.length}, 1fr); gap: ${GAP}px; align-items: start; }
  figure { margin: 0; display: flex; flex-direction: column; align-items: center; gap: ${GAP}px; }
  figcaption { align-self: stretch; padding: 10px 14px; background: #111; color: #fff; font-weight: 700; font-size: 24px; }
  img { display: block; background: #fff; box-shadow: 0 2px 12px rgba(0, 0, 0, .25); }
  img.desktop { width: 100%; height: auto; }
  img.phone { width: 400px; height: auto; }
</style></head>
<body><h1>${escapeHtml(title)}</h1><div class="row">
${columns.map(column).join('\n')}
</div></body></html>
`
}

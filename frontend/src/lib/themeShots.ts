// The colour sets, pages and sizes of the theme pictures, and what each picture file is called.
// Today's colours have no data-theme attribute; the two owl sets are chosen with data-theme="forest" and data-theme="forest-soft".

export const THEMES = [
  { id: 'today', attribute: '', label: 'Today: neon green' },
  { id: 'forest', attribute: 'forest', label: 'A: Forest' },
  { id: 'forest-soft', attribute: 'forest-soft', label: 'B: Forest soft' },
] as const

export const PAGES = [
  { id: 'login', label: 'Login' },
  { id: 'overview', label: 'Overview' },
  { id: 'machines', label: 'Machines list' },
  { id: 'live', label: "A machine's Live tab (online, with a GPU)" },
  { id: 'vms-tab', label: "A machine's VMs tab (Building view)" },
  { id: 'all-vms-create', label: 'All VMs with the Create VM window open' },
  { id: 'add-machine-check', label: 'Add machine, step 3 (Check)' },
  { id: 'offline-machine', label: 'An offline machine' },
] as const

export const SIZES = {
  desktop: { width: 1280, height: 800 },
  phone: { width: 400, height: 844 },
} as const

export type ThemeId = (typeof THEMES)[number]['id']
export type PageId = (typeof PAGES)[number]['id']
export type SizeId = keyof typeof SIZES

/** The file of one picture: `<theme>-<page>-<desktop|phone>.png`. */
export const shotName = (theme: ThemeId, page: PageId, size: SizeId): `${string}.png` => `${theme}-${page}-${size}.png`

/** The picture that puts today, A and B of one page side by side. */
export const compareName = (page: PageId): `${string}.png` => `compare-${page}.png`

// The pages and sizes of the regression pictures (e2e/theme-shots.e2e.ts), and what each picture file is called.

export const PAGES = [
  'login',
  'overview',
  'machines',
  'live',
  'vms-tab',
  'all-vms-create',
  'add-machine-check',
  'offline-machine',
] as const

export const SIZES = {
  desktop: { width: 1280, height: 800 },
  phone: { width: 400, height: 844 },
} as const

export type PageId = (typeof PAGES)[number]
export type SizeId = keyof typeof SIZES

/** The file of one picture: `<page>-<desktop|phone>.png`. */
export const shotName = (page: PageId, size: SizeId): `${string}.png` => `${page}-${size}.png`

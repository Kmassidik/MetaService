// The rows of the two image dropdowns of the Create VM window: "Server image" (operating systems) and "Install on top" (frameworks and agents).
// The machine's own catalog decides what is really available; the preview rows are a fixed list of what is planned, always greyed out, and are never sent to the parent.
// Pure functions, no DOM, no network.
import { LOGOS, type LogoName } from './logos.ts'
import { STOCK_DESCRIPTION, STOCK_IMAGE, STOCK_TITLE, type ImageOption } from './images.ts'

/** The small outline picture for a row that has no logo. */
export type Glyph = 'none' | 'container' | 'vm'

/** One row of a rich dropdown: a name, one short line under it, a small tag, and a logo or an outline picture. */
export interface RichCard {
  id: string
  title: string
  caption: string
  disabled: boolean
  /** The small chip on the right; null when there is nothing to say. */
  tag: string | null
  /** The address of the row's bundled logo. */
  logo?: string
  /** The outline picture shown when the row has no logo. */
  glyph?: Glyph
}

export const NO_FRAMEWORK = 'none'
const NO_FRAMEWORK_TITLE = 'None — just the server'
const NO_FRAMEWORK_CAPTION = 'Nothing extra is installed.'
const NOT_YET = 'not available yet'
const TAG_DEFAULT = 'Default'
const TAG_COMING_SOON = 'Coming soon'
const TAG_WAITING = 'Waiting'
const PREVIEW_SYSTEM_CAPTION = 'Coming soon: not tested on this machine yet'
const PREVIEW_FRAMEWORK_CAPTION = 'Coming soon'
const PREVIEW_PREFIX = 'preview-'

interface Preview {
  id: string
  title: string
  logo: LogoName
}

/** The operating systems that are planned. They are shown, never offered. */
export const SERVER_PREVIEWS: readonly Preview[] = [
  { id: 'debian', title: 'Debian 12', logo: 'debian' },
  { id: 'fedora', title: 'Fedora Server', logo: 'fedora' },
  { id: 'rockylinux', title: 'Rocky Linux', logo: 'rockylinux' },
  { id: 'almalinux', title: 'AlmaLinux', logo: 'almalinux' },
  { id: 'alpinelinux', title: 'Alpine Linux', logo: 'alpinelinux' },
]

/** The frameworks that are planned. They are shown, never offered. */
export const FRAMEWORK_PREVIEWS: readonly Preview[] = [
  { id: 'docker', title: 'Docker', logo: 'docker' },
  { id: 'ollama', title: 'Ollama', logo: 'ollama' },
  { id: 'python', title: 'Python + Jupyter', logo: 'python' },
  { id: 'nodejs', title: 'Node.js', logo: 'nodejs' },
]

/** The logos of the catalog's own images, by id. */
const CATALOG_LOGOS: Readonly<Record<string, LogoName>> = { [STOCK_IMAGE]: 'ubuntu', openclaw: 'openclaw', hermes: 'hermes' }

const logoOf = (id: string): string | undefined => {
  const name = CATALOG_LOGOS[id]
  return name === undefined ? undefined : LOGOS[name]
}

const previewCard = (preview: Preview, caption: string): RichCard => ({ id: `${PREVIEW_PREFIX}${preview.id}`, title: preview.title, caption, disabled: true, tag: TAG_COMING_SOON, logo: LOGOS[preview.logo] })

function catalogTag(entry: ImageOption): string | null {
  if (!entry.disabled) return null
  return entry.planned ? TAG_COMING_SOON : TAG_WAITING
}

const catalogCaption = (entry: ImageOption): string => (entry.disabled ? (entry.reason ?? NOT_YET) : entry.description)

function catalogCard(entry: ImageOption): RichCard {
  const logo = logoOf(entry.id)
  return { id: entry.id, title: entry.title, caption: catalogCaption(entry), disabled: entry.disabled, tag: catalogTag(entry), ...(logo === undefined ? {} : { logo }) }
}

/** The stock image as the machine's catalog has it, under the panel's own name; greyed out with the catalog's reason when the machine does not offer it. */
function stockCard(options: ImageOption[]): RichCard {
  const entry = options.find((option) => option.id === STOCK_IMAGE)
  const offered = entry !== undefined && !entry.disabled
  return {
    id: STOCK_IMAGE,
    title: STOCK_TITLE,
    caption: offered ? STOCK_DESCRIPTION : (entry?.reason ?? NOT_YET),
    disabled: !offered,
    tag: offered ? TAG_DEFAULT : TAG_WAITING,
    logo: LOGOS.ubuntu,
  }
}

/** "Server image": the stock image first, then the planned operating systems (greyed out). */
export const serverCards = (options: ImageOption[]): RichCard[] => [stockCard(options), ...SERVER_PREVIEWS.map((preview) => previewCard(preview, PREVIEW_SYSTEM_CAPTION))]

/** "Install on top": None first, then the catalog's frameworks (as it says they are), then the planned ones (greyed out). */
export const frameworkCards = (options: ImageOption[]): RichCard[] => [
  { id: NO_FRAMEWORK, title: NO_FRAMEWORK_TITLE, caption: NO_FRAMEWORK_CAPTION, disabled: false, tag: null, glyph: 'none' },
  ...options.filter((option) => option.id !== STOCK_IMAGE).map(catalogCard),
  ...FRAMEWORK_PREVIEWS.map((preview) => previewCard(preview, PREVIEW_FRAMEWORK_CAPTION)),
]

/** The row of "Install on top" that stands for the form's bundle: None for the stock image. */
export const frameworkOfBundle = (bundle: string | undefined): string => (bundle === undefined || bundle === '' || bundle === STOCK_IMAGE ? NO_FRAMEWORK : bundle)

/** The form's bundle for a row of "Install on top": the stock image for None. A preview row never becomes a bundle. */
export const bundleOfFramework = (row: string): string => (row === NO_FRAMEWORK || row.startsWith(PREVIEW_PREFIX) ? STOCK_IMAGE : row)

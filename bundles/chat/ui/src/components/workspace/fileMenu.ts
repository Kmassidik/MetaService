import type { FileGroup } from '../../lib/files/fileList.ts'
import type { ChatFile } from '../../lib/types.ts'

/** The row a file's ⋯ menu is open for, with where it opens. */
export interface FileMenuTarget {
  group: FileGroup
  file: ChatFile
  renderedPdf: ChatFile | null
  x: number
  y: number
}

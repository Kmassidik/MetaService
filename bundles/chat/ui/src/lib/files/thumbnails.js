/** The session's picture cache, shared by the composer, messages, the Files tab and the viewer. */
import { fetchImageBlob } from './download.js'
import { isViewableImage } from './preview.js'
import { createThumbnailCache } from './thumbnailCache.js'

export const thumbnails = createThumbnailCache({ load: fetchImageBlob })

/** A finished upload's own bytes become its picture, so the composer never downloads them back. */
export function seedFromUpload(record, localFile) {
  if (!isViewableImage(record) || localFile.size !== record.size) return
  thumbnails.seed(record.id, new Blob([localFile], { type: record.mediaType }))
}

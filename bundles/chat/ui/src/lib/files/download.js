/** Fetching a saved file's bytes for a preview: streamed, capped, and checked for completeness. */
import { PREVIEW_LIMITS, downloadUrl, isViewableImage } from './preview.js'

async function collectChunks(reader, limit) {
  const chunks = []
  let length = 0
  for (let chunk = await reader.read(); !chunk.done; chunk = await reader.read()) {
    length += chunk.value.byteLength
    if (length > limit) {
      await reader.cancel()
      throw new Error('Preview exceeded its byte limit. Download the original instead.')
    }
    chunks.push(chunk.value)
  }
  return { chunks, length }
}

function joinChunks({ chunks, length }) {
  const data = new Uint8Array(length)
  let offset = 0
  for (const chunk of chunks) {
    data.set(chunk, offset)
    offset += chunk.byteLength
  }
  return data
}

/** Reads at most `limit` bytes of the body, failing as soon as the stream goes past it. */
export async function readLimitedBytes(response, limit) {
  if (!response.body) throw new Error('This browser cannot stream the preview safely. Download the original instead.')
  const reader = response.body.getReader()
  try {
    return joinChunks(await collectChunks(reader, limit))
  } finally {
    reader.releaseLock()
  }
}

/** The whole file, or an error if it is bigger than `limit` or arrives short. */
export async function fetchFileBytes(file, limit, signal) {
  const response = await fetch(downloadUrl(file.id), { credentials: 'same-origin', signal })
  if (!response.ok) throw new Error(`Preview failed (${response.status}).`)
  const data = await readLimitedBytes(response, Math.min(file.size, limit))
  if (data.byteLength !== file.size) throw new Error('Preview download was incomplete. Download or retry the original file.')
  return data
}

/** A picture as a Blob typed with the server-detected image type (the download is octet-stream). */
export async function fetchImageBlob(file, signal) {
  if (!isViewableImage(file)) throw new Error('This file cannot be shown as a picture.')
  const data = await fetchFileBytes(file, PREVIEW_LIMITS.image, signal)
  return new Blob([data], { type: file.mediaType })
}

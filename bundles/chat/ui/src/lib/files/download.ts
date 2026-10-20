/** Fetching a saved file's bytes for a preview: streamed, capped, and checked for completeness. */
import type { ChatFile } from '../types.ts'
import { PREVIEW_LIMITS, downloadUrl, isViewableImage } from './preview.ts'

type Bytes = Uint8Array<ArrayBuffer>
interface Collected {
  chunks: Uint8Array[]
  length: number
}

async function collectChunks(reader: ReadableStreamDefaultReader<Uint8Array>, limit: number): Promise<Collected> {
  const chunks: Uint8Array[] = []
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

function joinChunks({ chunks, length }: Collected): Bytes {
  const data = new Uint8Array(length)
  let offset = 0
  for (const chunk of chunks) {
    data.set(chunk, offset)
    offset += chunk.byteLength
  }
  return data
}

/** Reads at most `limit` bytes of the body, failing as soon as the stream goes past it. */
export async function readLimitedBytes(response: Response, limit: number): Promise<Bytes> {
  if (!response.body) throw new Error('This browser cannot stream the preview safely. Download the original instead.')
  const reader = response.body.getReader()
  try {
    return joinChunks(await collectChunks(reader, limit))
  } finally {
    reader.releaseLock()
  }
}

/** The whole file, or an error if it is bigger than `limit` or arrives short. */
export async function fetchFileBytes(file: Pick<ChatFile, 'id' | 'size'>, limit: number, signal?: AbortSignal): Promise<Bytes> {
  const response = await fetch(downloadUrl(file.id), { credentials: 'same-origin', signal: signal ?? null })
  if (!response.ok) throw new Error(`Preview failed (${response.status}).`)
  const data = await readLimitedBytes(response, Math.min(file.size, limit))
  if (data.byteLength !== file.size) throw new Error('Preview download was incomplete. Download or retry the original file.')
  return data
}

/** A picture as a Blob typed with the server-detected image type (the download is octet-stream). */
export async function fetchImageBlob(file: ChatFile, signal?: AbortSignal): Promise<Blob> {
  if (!isViewableImage(file)) throw new Error('This file cannot be shown as a picture.')
  const data = await fetchFileBytes(file, PREVIEW_LIMITS.image, signal)
  return new Blob([data], { type: file.mediaType })
}

/** Checks for the answers about saved and uploaded files. */
import { type Check, arrayOf, isNumber, isString, objectOf, objectWithOptional, parseAnswer } from '../check.ts'
import type { ChatFile } from '../types.ts'

export const isChatFile = objectWithOptional<ChatFile>(
  { id: isString, name: isString, size: isNumber, mediaType: isString, state: isString, createdAt: isString },
  {
    version: isNumber, artifactId: isString, sourceFileId: isString, previewFileId: isString,
    sha256: isString, agentId: isString, received: isNumber,
  },
)

const DELETED_STATE = 'deleted'
const DELETED_NAME = 'File no longer available'

/** What a message holds for a file the owner deleted: the server keeps only these three fields. */
export interface RemovedFile {
  id: string
  name: string
  state: string
}

const isDeletedState: Check<string> = (value): value is string => value === DELETED_STATE
const isRemovedFile = objectOf<RemovedFile>({ id: isString, name: isString, state: isDeletedState })

/** A file in a message: a saved file, or the stub of a deleted one. */
export const isMessageFile: Check<ChatFile | RemovedFile> = (value): value is ChatFile | RemovedFile => isChatFile(value) || isRemovedFile(value)

/** What a message shows in place of a file the owner deleted. */
export function deletedFile(id: string, name: string = DELETED_NAME): ChatFile {
  return { id, state: DELETED_STATE, name, size: 0, mediaType: '', createdAt: '' }
}

/** A message's file as a whole file record: a deleted file's stub gets empty details. */
export function messageFile(file: ChatFile | RemovedFile): ChatFile {
  return 'size' in file ? file : deletedFile(file.id, file.name)
}

interface FileAnswer {
  file: ChatFile
}

interface FileList {
  files: ChatFile[]
}

interface ChunkAnswer {
  file: { received: number }
}

const isFileAnswer = objectOf<FileAnswer>({ file: isChatFile })
const isFileList = objectOf<FileList>({ files: arrayOf(isChatFile) })
const isChunkAnswer = objectOf<ChunkAnswer>({ file: objectOf<{ received: number }>({ received: isNumber }) })

export const parseFile = (answer: unknown): ChatFile => parseAnswer(isFileAnswer, answer, 'file').file
export const parseFiles = (answer: unknown): ChatFile[] => parseAnswer(isFileList, answer, 'file list').files
export const parseReceived = (answer: unknown): number => parseAnswer(isChunkAnswer, answer, 'upload').file.received

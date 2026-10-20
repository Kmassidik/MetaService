/** Checks for the answers about saved and uploaded files. */
import { arrayOf, isNumber, isString, objectOf, objectWithOptional, parseAnswer } from '../check.ts'
import type { ChatFile } from '../types.ts'

export const isChatFile = objectWithOptional<ChatFile>(
  { id: isString, name: isString, size: isNumber, mediaType: isString, state: isString, createdAt: isString },
  {
    version: isNumber, artifactId: isString, sourceFileId: isString, previewFileId: isString,
    sha: isString, agentId: isString, received: isNumber,
  },
)

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

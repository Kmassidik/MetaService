/** What a failed request or a thrown value says, read without trusting its type. */
import { isRecord } from './check.ts'

/** A request the server answered with an error; `status` is the HTTP status. */
export class ApiError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

export function errorStatus(error: unknown): number | undefined {
  return isRecord(error) && typeof error.status === 'number' ? error.status : undefined
}

export function errorName(error: unknown): string {
  return isRecord(error) && typeof error.name === 'string' ? error.name : ''
}

export function errorMessage(error: unknown): string {
  return isRecord(error) && typeof error.message === 'string' ? error.message : ''
}

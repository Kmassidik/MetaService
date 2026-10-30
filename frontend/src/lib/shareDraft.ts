// What the person types for one waiting machine (code, name, share) and the checks before Approve is sent.
// A wrong code uses up one of its few tries, so a code that is plainly not six digits is never sent.
import type { PendingMachine, Share } from './share.ts'
import { saneName } from './shareText.ts'

export interface ApproveDraft {
  code: string
  name: string
  /** The share fields are text while typed. */
  cores: string
  ram_mb: string
  disk_gb: string
}

export interface ApproveBody {
  code: string
  name: string
  share: Share
}

const CODE = /^\d{6}$/
const NAME = /^[A-Za-z0-9._-]{1,64}$/
const WHOLE = /^\d+$/
export const CODE_PROBLEM = 'Type the 6-digit code shown on the far PC.'
export const NAME_PROBLEM = 'The name may only have letters, digits, dot, dash and underscore (up to 64).'
export const SHARE_PROBLEM = 'The share numbers must be whole numbers above zero.'
export const SHARE_TOO_HIGH_PROBLEM = 'You can lower the share the person offered, not raise it.'

/** The starting values: the machine's own host name and what it asked to share. */
export const draftFor = (machine: PendingMachine): ApproveDraft => ({
  code: '',
  name: saneName(machine.hostname),
  cores: String(machine.share.cores),
  ram_mb: String(machine.share.ram_mb),
  disk_gb: String(machine.share.disk_gb),
})

const SHARE_KEYS = ['cores', 'ram_mb', 'disk_gb'] as const

function shareProblem(draft: ApproveDraft, asked: Share): string | null {
  const values = SHARE_KEYS.map((key) => draft[key].trim())
  if (!values.every((value) => WHOLE.test(value) && Number(value) > 0)) return SHARE_PROBLEM
  return SHARE_KEYS.some((key, index) => Number(values[index]) > asked[key]) ? SHARE_TOO_HIGH_PROBLEM : null
}

/** The first thing wrong with the draft, in plain words, or null when it can be sent. */
export function draftProblem(draft: ApproveDraft, asked: Share): string | null {
  if (!CODE.test(draft.code.trim())) return CODE_PROBLEM
  if (!NAME.test(draft.name.trim())) return NAME_PROBLEM
  return shareProblem(draft, asked)
}

/** The body of the approve call. Only for a draft that has no problem. */
export const approveBody = (draft: ApproveDraft): ApproveBody => ({
  code: draft.code.trim(),
  name: draft.name.trim(),
  share: { cores: Number(draft.cores), ram_mb: Number(draft.ram_mb), disk_gb: Number(draft.disk_gb) },
})

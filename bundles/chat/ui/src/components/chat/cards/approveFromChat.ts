import type { Approval } from '../../../lib/types.ts'
import { chat } from '../../../lib/chatApp.svelte.ts'

// The in-chat Approve button is itself the review of what the card shows (action,
// destination, tool). It records that review against the exact parameters' hash, which the
// existing decision handler requires, then approves once. No parameters, no approval.
export function approveFromChat(approval: Approval, decide: (approval: Approval, decision: string) => unknown): unknown {
  if (!approval.parametersJSON || !approval.parametersSHA256) return
  chat.reviewedApprovals = { ...chat.reviewedApprovals, [approval.id]: approval.parametersSHA256 }
  return decide(approval, 'approve')
}

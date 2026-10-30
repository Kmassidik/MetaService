// A waiting request in plain words ("wants to create a medium VM on rtx-pc with a 4 GB GPU limit"), and the words of a decided one.
import type { McpRequest, RequestParams, RequestState } from './mcpRequests.ts'

const ANY_MACHINE = 'the least loaded machine that fits'

function sizeText(params: RequestParams): string {
  if (params.size === 'custom' || (params.size === null && params.vcpu !== null)) {
    const parts = [params.vcpu !== null ? `${params.vcpu} vCPU` : '', params.ramMb !== null ? `${Math.round(params.ramMb / 1024)} GB RAM` : '', params.diskGb !== null ? `${params.diskGb} GB disk` : '']
    return `a custom VM (${parts.filter(Boolean).join(', ') || 'size not given'})`
  }
  return params.size ? `a ${params.size} VM` : 'a VM'
}

function createText(params: RequestParams): string {
  const gpu = params.gpuMemoryGb === null ? '' : ` with a ${params.gpuMemoryGb} GB GPU limit`
  const named = params.vm ? ` called ${params.vm}` : ''
  return `create ${sizeText(params)}${named} on ${params.machine ?? ANY_MACHINE}${gpu}`
}

function actionText(verb: string, params: RequestParams): string {
  return `${verb} VM ${params.vm ?? '(unnamed)'} on ${params.machine ?? 'an unknown machine'}`
}

/** What the AI client wants, after "<token name> wants to". */
export function wantsText(request: Pick<McpRequest, 'kind' | 'params'>): string {
  switch (request.kind) {
    case 'create':
      return createText(request.params)
    case 'delete':
      return actionText('delete', request.params)
    case 'start':
      return actionText('start', request.params)
    case 'stop':
      return actionText('stop', request.params)
  }
}

const STATE_WORDS: Record<RequestState, string> = {
  pending_approval: 'waiting',
  approved: 'approved',
  denied: 'denied',
  running: 'approved, running',
  done: 'approved, done',
  failed: 'approved, but it failed',
  expired: 'expired, nobody decided',
}

export const stateWords = (state: RequestState): string => STATE_WORDS[state]

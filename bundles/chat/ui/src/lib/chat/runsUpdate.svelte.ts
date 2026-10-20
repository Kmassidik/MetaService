import type { Run } from '../types.ts'
import { chat, terminalRunStates } from './state.svelte.ts'

export function updateRun(run: Run): void {
  chat.agentRuns = { ...chat.agentRuns, [run.agentId]: [run, ...(chat.agentRuns[run.agentId] || []).filter(item => item.id !== run.id)] }
  if (!terminalRunStates.has(run.state)) chat.agents = chat.agents.map(agent => agent.id === run.agentId ? { ...agent, status: 'running' } : agent)
}

import { chat, terminalRunStates } from './state.svelte.js'

export function updateRun(run) {
  chat.agentRuns = { ...chat.agentRuns, [run.agentId]: [run, ...(chat.agentRuns[run.agentId] || []).filter(item => item.id !== run.id)] }
  if (!terminalRunStates.has(run.state)) chat.agents = chat.agents.map(agent => agent.id === run.agentId ? { ...agent, status: 'running' } : agent)
}

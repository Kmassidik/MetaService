// The Machines page's query tab: filters the machines array in memory. Plain substring match plus
// `os:`, `state:`, `ip:` prefix filters. Multiple words are AND-ed. No server round-trip.
import type { Machine } from './types.ts'

export interface ParsedQuery {
  terms: string[]
  os?: string | undefined
  state?: string | undefined
  ip?: string | undefined
}

export function parseQuery(raw: string): ParsedQuery {
  const terms: string[] = []
  let os: string | undefined, state: string | undefined, ip: string | undefined
  for (const word of raw.trim().split(/\s+/).filter(Boolean)) {
    if (word.startsWith('os:')) os = word.slice(3).toLowerCase()
    else if (word.startsWith('state:')) state = word.slice(6).toLowerCase()
    else if (word.startsWith('ip:')) ip = word.slice(3).toLowerCase()
    else terms.push(word.toLowerCase())
  }
  return { terms, os, state, ip }
}

function machineText(machine: Machine): string {
  return [machine.id, machine.name, machine.os, machine.arch, machine.ip ?? '', machine.state].join(' ').toLowerCase()
}

export function matchesQuery(machine: Machine, parsed: ParsedQuery): boolean {
  if (parsed.os && !machine.os.toLowerCase().includes(parsed.os)) return false
  if (parsed.state && !machine.state.toLowerCase().includes(parsed.state)) return false
  if (parsed.ip && !(machine.ip ?? '').toLowerCase().includes(parsed.ip)) return false
  const text = machineText(machine)
  return parsed.terms.every((term) => text.includes(term))
}

export function queryMachines(machines: Machine[], raw: string): Machine[] {
  if (!raw.trim()) return machines
  const parsed = parseQuery(raw)
  return machines.filter((m) => matchesQuery(m, parsed))
}

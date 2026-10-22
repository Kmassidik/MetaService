// Which action buttons a VM row shows and in which order. A new action is one line in RULES (and its button in components/vms/VmActions.svelte).
import { RUNNING_STATE, STOPPED_STATE } from './vm.ts'
import type { Machine, Workload } from './types.ts'

export type VmActionId = 'terminal' | 'start' | 'stop' | 'open-chat' | 'install-chat' | 'delete'

export interface VmActionFacts {
  state: string
  chatInstalled: boolean
}

export interface VmActionLayout {
  /** The everyday buttons, left to right. */
  main: VmActionId[]
  /** Set apart after a gap, last, in red. */
  danger: VmActionId[]
}

interface Rule {
  id: VmActionId
  group: keyof VmActionLayout
  shown: (facts: VmActionFacts) => boolean
}

/** The order of this list is the order on screen. */
const RULES: Rule[] = [
  { id: 'terminal', group: 'main', shown: () => true },
  { id: 'start', group: 'main', shown: (facts) => facts.state === STOPPED_STATE },
  { id: 'stop', group: 'main', shown: (facts) => facts.state === RUNNING_STATE },
  { id: 'open-chat', group: 'main', shown: (facts) => facts.chatInstalled },
  { id: 'install-chat', group: 'main', shown: (facts) => facts.state === RUNNING_STATE },
  { id: 'delete', group: 'danger', shown: () => true },
]

export function vmActions(facts: VmActionFacts): VmActionLayout {
  const shown = RULES.filter((rule) => rule.shown(facts))
  return {
    main: shown.filter((rule) => rule.group === 'main').map((rule) => rule.id),
    danger: shown.filter((rule) => rule.group === 'danger').map((rule) => rule.id),
  }
}

export const vmActionFacts = (workload: Pick<Workload, 'state' | 'bundle_version'>): VmActionFacts => ({ state: workload.state, chatInstalled: Boolean(workload.bundle_version) })

/** What a VM row does when a button is pressed; the page that owns the data answers each. */
export interface VmActionHandlers {
  onAct: (machine: Machine, workload: Workload, action: 'start' | 'stop') => Promise<void>
  onInstall: (machine: Machine, workload: Workload | null) => Promise<unknown>
  onOpenChat: (machine: Machine, workload: Workload | null) => void
  onDelete: (machine: Machine, workload: Workload) => void
}

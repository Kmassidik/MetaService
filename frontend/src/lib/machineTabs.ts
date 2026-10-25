// The tabs of a machine's page (Storage: what fills the disk, drawn like disktree): which there are, what they are called, which old names still work, and which key moves where. Pure functions, no DOM.
export type MachineTab = 'live' | 'vms' | 'storage' | 'environment' | 'activity'

export interface TabInfo {
  id: MachineTab
  label: string
}

export const DEFAULT_TAB: MachineTab = 'live'

const ORDER: readonly MachineTab[] = ['live', 'vms', 'storage', 'environment', 'activity']
const LABELS: Record<MachineTab, string> = { live: 'Live', vms: 'VMs', storage: 'Storage', environment: 'Environment', activity: 'Activity' }

/** Names that older links and older versions of the page used. */
const OLD_NAMES: Record<string, MachineTab> = { overview: 'environment', deployments: 'vms' }

/** The tabs in order. VMs carries how many VMs the machine has, counting the ones being made. */
export function machineTabs(vmCount: number): TabInfo[] {
  return ORDER.map((id) => ({ id, label: id === 'vms' ? `${LABELS.vms} (${vmCount})` : LABELS[id] }))
}

const isTab = (name: string): name is MachineTab => ORDER.some((id) => id === name)

/** The tab a name in a link stands for. An old name lands on its new home; no name or an unknown one opens Live. */
export function tabFromName(name: string | null): MachineTab {
  const lower = (name ?? '').toLowerCase()
  if (isTab(lower)) return lower
  return OLD_NAMES[lower] ?? DEFAULT_TAB
}

const lastIndex = ORDER.length - 1

function targetIndex(current: number, key: string): number | null {
  if (key === 'ArrowRight') return current === lastIndex ? 0 : current + 1
  if (key === 'ArrowLeft') return current === 0 ? lastIndex : current - 1
  if (key === 'Home') return 0
  if (key === 'End') return lastIndex
  return null
}

/** The tab a key press moves to from `from`, or null when the key does nothing here. */
export function nextTab(from: MachineTab, key: string): MachineTab | null {
  const index = targetIndex(ORDER.indexOf(from), key)
  return index === null ? null : (ORDER[index] ?? null)
}

/** Only Live shows numbers that change, so only Live asks the parent for them. */
export const pollsLive = (tab: MachineTab): boolean => tab === 'live'

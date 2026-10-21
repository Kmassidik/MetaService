// Which VM's terminal is open. One window for the whole panel (App draws it over the current page), so every Terminal button opens the same one and none keeps its own copy.
export interface ConsoleTarget {
  machine: string
  workload: string
  /** The VM's name in the window title. */
  name: string
}

let target = $state<ConsoleTarget | null>(null)

export const consoleTarget = (): ConsoleTarget | null => target

export function openConsole(next: ConsoleTarget): void {
  target = next
}

export function closeConsole(): void {
  target = null
}

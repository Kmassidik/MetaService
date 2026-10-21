// Which cards the Live tab draws: CPU and Memory on top, then Disk and Network, and GPU only when the machine could say. Pure functions, no DOM.
export type LowerCard = 'disk' | 'network' | 'gpu'

export function lowerRowCards(hasGpu: boolean): LowerCard[] {
  return hasGpu ? ['disk', 'network', 'gpu'] : ['disk', 'network']
}

/** How many equal columns the lower row has. */
export const lowerRowColumns = (hasGpu: boolean): number => lowerRowCards(hasGpu).length

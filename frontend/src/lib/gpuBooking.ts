// The GPU memory a machine's card has booked for VMs ("shared partition"), and the limit of one VM. Both come from the Root: read them here, never trust their shape.
// Pure functions, no DOM, no network.

/** How much of the card's memory is promised to VMs, in GB. */
export interface GpuBooking {
  total_gb: number
  booked_gb: number
  free_gb: number
}

const PERCENT = 100
export const LIMIT_CHIP_TITLE = 'GPU memory limit, booked for this VM'
export const LIMIT_ROW_LABEL = 'GPU memory limit'

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)
const isGb = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0

/** The booking in the promised shape, or null when the machine has none or the value is not one. */
export function readGpuBooking(value: unknown): GpuBooking | null {
  if (!isRecord(value)) return null
  const { total_gb: total, booked_gb: booked, free_gb: free } = value
  if (!isGb(total) || !isGb(booked) || !isGb(free)) return null
  return { total_gb: total, booked_gb: booked, free_gb: free }
}

/** A VM's limit in whole GB, or null when it has none (or the value is not a positive whole number). */
export const readGpuMemoryGb = (value: unknown): number | null => (typeof value === 'number' && Number.isInteger(value) && value >= 1 ? value : null)

/** "Booked for VMs: 8 of 31 GB · free 23 GB", or "Booked for VMs: none · 31 GB free" at 0 booked. */
export function bookingText(booking: GpuBooking): string {
  if (booking.booked_gb === 0) return `Booked for VMs: none · ${booking.free_gb} GB free`
  return `Booked for VMs: ${booking.booked_gb} of ${booking.total_gb} GB · free ${booking.free_gb} GB`
}

/** How full the bar is, 0 to 100. */
export const bookingPercent = (booking: GpuBooking): number => (booking.total_gb > 0 ? Math.min(PERCENT, (booking.booked_gb / booking.total_gb) * PERCENT) : 0)

/** "GPU 4 GB", the chip next to a VM's status. */
export const limitChipText = (gb: number): string => `GPU ${gb} GB`

/** "4 GB (booked)", the value of the VM page row. */
export const limitRowText = (gb: number): string => `${gb} GB (booked)`

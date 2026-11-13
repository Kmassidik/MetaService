/** Machines that joined through Share a PC reach the parent from this network (same prefix as the parent's McpShared). */
const SHARED_PREFIX = '10.77.0.'
const PRIVATE_PREFIXES = ['192.168.', '10.', '172.16.', '172.17.', '172.18.', '172.19.', '172.2', '172.30.', '172.31.']

export type NetworkTag = 'Shared' | 'Same network' | 'Other network'

/** Where a machine sits compared with the parent: joined through Share a PC, on the office network, or reached some other way. */
export function networkTag(ip: string | undefined): NetworkTag | null {
  if (!ip) return null
  if (ip.startsWith(SHARED_PREFIX)) return 'Shared'
  if (PRIVATE_PREFIXES.some((prefix) => ip.startsWith(prefix))) return 'Same network'
  return 'Other network'
}

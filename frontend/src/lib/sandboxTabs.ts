export type SandboxTab = 'live' | 'keys' | 'usage'

export const SANDBOX_TABS: { id: SandboxTab; label: string; href: string }[] = [
  { id: 'live', label: 'Live', href: '#/sandboxes' },
  { id: 'keys', label: 'API keys', href: '#/sandboxes/keys' },
  { id: 'usage', label: 'Usage', href: '#/sandboxes/usage' },
]

export function sandboxTabFromRoute(route: string): SandboxTab {
  if (route === '/sandboxes/keys' || route === '/keys') return 'keys'
  if (route === '/sandboxes/usage') return 'usage'
  return 'live'
}

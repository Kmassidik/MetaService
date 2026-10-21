<script lang="ts">
  interface NavPage {
    id: string
    label: string
    href: string
    icon: string
  }

  import { machinesMenu } from '../lib/sidebar.ts'
  import type { Machine } from '../lib/types.ts'

  let { active = 'overview', route = '/', machines = [], username, onSignOut }: { active?: string; route?: string; machines?: Machine[]; username: string; onSignOut: () => void } = $props()
  // Machines is a dropdown: it opens by itself when a machines page is shown, and the person can close or open it.
  let open = $state(false)
  $effect(() => { if (active === 'machines') open = true })
  const isOn = (page: NavPage) => active === page.id
  const menu = $derived(machinesMenu(route, machines))
  // The same groups and names as the MAAS panel. The pages behind them show what MetaService has: machines of any kind, and their VMs.
  const operator: NavPage[] = [
    { id: 'overview', label: 'Overview', href: '#/', icon: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z' },
    { id: 'usage', label: 'Token ledger', href: '#/usage', icon: 'M5 3h14v18H5z M8 7h8 M8 11h8 M8 15h5' },
    { id: 'settings', label: 'Settings', href: '#/settings', icon: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9l2.1 2.1 M17 17l2.1 2.1 M4.9 19.1 7 17 M17 7l2.1-2.1' },
    { id: 'health', label: 'Health & alerts', href: '#/health', icon: 'M2 12h5l3-8 4 16 3-8h5' },
  ]
  const infrastructure: NavPage[] = [
    { id: 'machines', label: 'Machines', href: '#/machines', icon: 'M4 5h16v10H4z M2 19h20 M9 15v4 M15 15v4' },
  ]
  const groups: [string, NavPage[]][] = [['Operator', operator], ['Infrastructure', infrastructure]]
</script>

<aside class="side">
  <a class="logo" href="#/" aria-label="MetaService overview"><span class="sq"></span><b>MetaService</b></a>
  <nav aria-label="Panel navigation">
    {#each groups as [title, pages] (title)}
      <div>
        <h3>{title}</h3>
        {#each pages as page (page.id)}
          {#if page.id === 'machines'}
            <button class="group" class:here={isOn(page)} type="button" aria-expanded={open} aria-controls="machines-menu" onclick={() => (open = !open)}>
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d={page.icon} /></svg>{page.label}
              <svg class="chev" class:turned={open} viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" /></svg>
            </button>
            {#if open}
              <div class="sub" id="machines-menu">
                {#each menu as item (item.key)}
                  <a class:on={item.on} href={item.href} aria-current={item.on ? 'page' : undefined}>{item.label}</a>
                {/each}
              </div>
            {/if}
          {:else}
            <a class:on={isOn(page)} href={page.href} aria-current={isOn(page) ? 'page' : undefined}>
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d={page.icon} /></svg>{page.label}
            </a>
          {/if}
        {/each}
      </div>
    {/each}
    <div>
      <h3>External monitoring</h3>
      <span class="nav-unavailable">Beszel not configured</span>
    </div>
  </nav>
  <div class="usr">
    <div class="row"><span>{username}</span><span class="on">ONLINE</span></div>
    <button type="button" onclick={onSignOut}>Sign out</button>
  </div>
</aside>

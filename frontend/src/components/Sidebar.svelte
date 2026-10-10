<script>
  let { active = 'overview', username, onSignOut } = $props()
  // The same groups and names as the MAAS panel. The pages behind them show what MetaService has: machines of any kind, and their VMs.
  const operator = [
    { id: 'overview', label: 'Overview', href: '#/', icon: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z' },
    { id: 'usage', label: 'Token ledger', href: '#/usage', icon: 'M5 3h14v18H5z M8 7h8 M8 11h8 M8 15h5' },
    { id: 'settings', label: 'Settings', href: '#/settings', icon: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9l2.1 2.1 M17 17l2.1 2.1 M4.9 19.1 7 17 M17 7l2.1-2.1' },
    { id: 'health', label: 'Health & alerts', href: '#/health', icon: 'M2 12h5l3-8 4 16 3-8h5' },
  ]
  const infrastructure = [
    { id: 'machines', label: 'Machines', href: '#/machines', icon: 'M4 5h16v10H4z M2 19h20 M9 15v4 M15 15v4' },
  ]
  const groups = [['Operator', operator], ['Infrastructure', infrastructure]]
</script>

<aside class="side">
  <a class="logo" href="#/" aria-label="MetaService overview"><span class="sq"></span><b>MetaService</b></a>
  <nav aria-label="Panel navigation">
    {#each groups as [title, pages] (title)}
      <div>
        <h3>{title}</h3>
        {#each pages as page (page.id)}
          <a class:on={active === page.id} href={page.href} aria-current={active === page.id ? 'page' : undefined}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d={page.icon} /></svg>{page.label}
          </a>
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

<script>
  let { active = 'machines', username, onSignOut } = $props()
  const pages = [
    { id: 'machines', label: 'Machines', href: '#/', icon: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z' },
    { id: 'scan', label: 'Find machines', href: '#/scan', icon: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z M20 20l-4-4' },
    { id: 'activity', label: 'Activity', href: '#/activity', icon: 'M2 12h5l3-8 4 16 3-8h5' },
  ]
  const settings = [
    { id: 'bundle', label: 'Chat bundle', href: '#/bundle', icon: 'M4 7h16v13H4z M12 3v4 M8 12h1 M15 12h1 M8 16h8' },
    { id: 'ai', label: 'AI provider', href: '#/ai', icon: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3' },
  ]
</script>

<aside class="side">
  <a class="logo" href="#/" aria-label="MetaService machines"><span class="sq"></span><b>MetaService</b></a>
  <nav aria-label="Panel navigation">
    <div>
      <h3>Fleet</h3>
      {#each pages as page}
        <a class:on={active === page.id} href={page.href} aria-current={active === page.id ? 'page' : undefined}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d={page.icon} /></svg>{page.label}
        </a>
      {/each}
    </div>
    <div>
      <h3>Settings</h3>
      {#each settings as page}
        <a class:on={active === page.id} href={page.href} aria-current={active === page.id ? 'page' : undefined}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d={page.icon} /></svg>{page.label}
        </a>
      {/each}
    </div>
  </nav>
  <div class="usr">
    <div class="row"><span>{username}</span><span class="on">ONLINE</span></div>
    <button type="button" onclick={onSignOut}>Sign out</button>
  </div>
</aside>

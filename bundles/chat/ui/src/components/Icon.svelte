<script>
  let { name, size = 20, ...rest } = $props()
  const paths = {
    plus: 'M12 5v14M5 12h14',
    search: 'M21 21l-4.4-4.4M19 10.5a8.5 8.5 0 1 1-17 0 8.5 8.5 0 0 1 17 0',
    arrow: 'M12 19V5M5 12l7-7 7 7',
    chevron: 'm9 5 7 7-7 7',
    down: 'm6 9 6 6 6-6',
    up: 'm6 15 6-6 6 6',
    close: 'm6 6 12 12M6 18 18 6',
    computer: 'M4 3h16a1 1 0 0 1 1 1v12H3V4a1 1 0 0 1 1-1ZM8 21h8M12 16v5',
    chat: 'M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5Z',
    edit: 'm16 3 5 5M4 20l4-1L21 6l-4-4L4 15l-1 6 1-1Z',
    trash: 'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7',
    logout: 'M9 4H4v16h5M10 12h11m-4-4 4 4-4 4',
    menu: 'M4 6h16M4 12h16M4 18h16',
    refresh: 'M20 7v5h-5M4 17v-5h5M6.1 6.1A8 8 0 0 1 19.5 9M4.5 15a8 8 0 0 0 13.4 2.9',
    shield: 'M12 3 3 7v5c0 5 9 9 9 9s9-4 9-9V7l-9-4Zm-4 9 3 3 5-6',
    spark: 'm12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z',
    check: 'm5 12 4 4L19 6',
    copy: 'M8 8h11v13H8zM5 3h11v3',
    code: 'm8 8-4 4 4 4M16 8l4 4-4 4',
    download: 'M12 4v11M7 11l5 5 5-5M5 20h14',
    eye: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Zm10 3.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z',
    heart: 'M12 20s-7-4.4-9.2-8.2A5.2 5.2 0 0 1 12 5.2a5.2 5.2 0 0 1 9.2 6.6C19 15.6 12 20 12 20Z',
    smile: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM8.5 10h.01M15.5 10h.01M8.2 14.5s1.5 2 3.8 2 3.8-2 3.8-2',
    reply: 'M9 14 4 9l5-5M4 9h10a6 6 0 0 1 6 6v4',
    folder: 'M3 7V5h6l2 2h10v13H3V7Z',
    activity: 'M3 12h4l3-8 4 16 3-8h4',
    team: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
    settings: 'M4 7h16M4 17h16M8 4v6M16 14v6',
    more: 'M12 6.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2ZM12 13a1 1 0 1 1 0-2 1 1 0 0 1 0 2ZM12 19.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z',
    apps: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM17 14v6M14 17h6',
    info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 10v6M12 7.5h.01',
    expand: 'M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7',
    fullscreen: 'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5',
    'fullscreen-exit': 'M9 4v5H4M15 4v5h5M20 15h-5v5M4 15h5v5',
    panel: 'M4 4h16v16H4zM15 4v16',
    mic: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3ZM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21',
    attach: 'm20.5 11.5-8.3 8.3a5.3 5.3 0 0 1-7.5-7.5l8.4-8.4a3.5 3.5 0 0 1 5 5l-8.4 8.4a1.8 1.8 0 0 1-2.5-2.5l7.7-7.7',
    at: 'M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Zm0 0v1.5a2.5 2.5 0 0 0 5 0V12a9 9 0 1 0-3.5 7.1',
    pointer: 'm5 3 13.5 6.5-5.8 1.9-1.9 5.8L5 3ZM13 13l6 6',
    plug: 'M9 3v4M15 3v4M6.5 7h11v4a5.5 5.5 0 0 1-11 0V7ZM12 16.5V21',
    lock: 'M6 11h12v10H6V11ZM8.5 11V7.5a3.5 3.5 0 0 1 7 0V11',
    clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 7.5V12l3 2',
    back: 'm15 5-7 7 7 7',
    bell: 'M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15L6 16ZM10 20.5a2 2 0 0 0 4 0',
    image: 'M4 5h16v14H4zM4 16l4.5-4.5 3.5 3.5 2.5-2.5L20 18M15.5 9.5h.01',
    file: 'M14 3H6v18h12V7l-4-4ZM14 3v4h4M9 13h6M9 17h6',
    sheet: 'M4 4h16v16H4zM4 10h16M4 15h16M10 4v16',
    map: 'M9 4 3 6.5V20l6-2.5L15 20l6-2.5V4L15 6.5 9 4Zm0 0v13.5M15 6.5V20',
  }
  const FILLED = new Set(['more'])
  const filled = $derived(FILLED.has(name))
</script>

<!-- Round caps and joins read softer at 16–20 px. -->
<svg width={size} height={size} viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke={filled ? 'none' : 'currentColor'} stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" {...rest}>
  <path d={paths[name] || paths.spark} />
</svg>

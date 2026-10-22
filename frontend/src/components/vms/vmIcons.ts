// Line icons for the VM row buttons, drawn like the sidebar's: 24 x 24 grid, path data only (the button gives them stroke 1.5 and square caps).
export const VM_ICONS = {
  terminal: 'M3 4h18v16H3z M7 9l3 3-3 3 M12 15h5',
  key: 'M8 15a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M11 11h10 M18 11v4 M21 11v3',
  start:'M7 4l13 8-13 8z',
  stop: 'M6 6h12v12H6z',
  chat: 'M4 4h16v12h-9l-5 4v-4H4z',
  install: 'M12 4v11 M7 11l5 5 5-5 M4 20h16',
  trash: 'M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13 M10 11v5 M14 11v5',
  copy: 'M9 9h11v11H9z M5 15H4V4h11v1',
} as const

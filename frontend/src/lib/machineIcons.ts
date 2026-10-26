// Line icons for the machine buttons, drawn like the sidebar's: 24 x 24 grid, path data only (the button gives them stroke 1.5 and square caps).
export const MACHINE_ICONS = {
  /** A pencil: the nib at the lower left, the body going up to the right, and the line where the nib meets the body. */
  pencil: 'M4 20l1-5L16 4l4 4L9 19z M13 7l4 4',
  /** An arrow leaving a box towards the upper right: open the machine's page. */
  open: 'M14 4h6v6 M20 4L10 14 M18 14v6H4V6h6',
  /** A bin: remove the machine. The same drawing as the VM list's delete icon. */
  trash: 'M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13 M10 11v5 M14 11v5',
} as const

// The small line icons of the machine card's rows, drawn the same way. Each sits next to the row's label and is decoration only (the label says the word).
export const CARD_ICONS = {
  /** A globe on a stand: the machine's address on the network. */
  network: 'M12 3a9 9 0 100 18 9 9 0 000-18 M3 12h18 M12 3c2.6 2.5 4 5.6 4 9s-1.4 6.5-4 9c-2.6-2.5-4-5.6-4-9s1.4-6.5 4-9',
  /** A screen on a stand: the machine's system, and the name of its main chip. */
  computer: 'M3 4h18v12H3z M9 20h6 M12 16v4',
  /** A tag with its hole: the profile the person saved for the machine. */
  tag: 'M3 4h7l11 11-6 6L4 10z M7.5 7.5h.01',
  /** A board with a fan: the machine's own graphics card. */
  gpu: 'M3 7h17v10H3z M22 11h1 M22 14h1 M6 17v3 M18 17v3 M15 12a2.5 2.5 0 10-5 0 2.5 2.5 0 005 0',
  /** A chip with its pins: the CPU as it is running now. */
  cpu: 'M6 6h12v12H6z M9 9h6v6H9z M9 3v3 M15 3v3 M9 18v3 M15 18v3 M3 9h3 M3 15h3 M18 9h3 M18 15h3',
  /** A memory stick with its pins: the RAM. */
  memory: 'M3 7h18v8H3z M7 10v2 M11 10v2 M15 10v2 M6 15v3 M12 15v3 M18 15v3',
  /** A drive with its slot: the disk. */
  disk: 'M3 6h18v12H3z M3 14h18 M7 17h2',
  /** A box: the VMs on the machine. */
  vms: 'M12 3l8 4.5v9L12 21l-8-4.5v-9z M4 7.5l8 4.5 8-4.5 M12 12v9',
  /** A clock: when the machine was last seen. */
  clock: 'M12 3a9 9 0 100 18 9 9 0 000-18 M12 7.5V12l3.5 2',
} as const

export const RENAME_LABEL = 'Rename machine'
export const OPEN_LABEL = 'Open machine'
export const REMOVE_LABEL = 'Remove'

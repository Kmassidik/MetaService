// Line icons for the machine buttons, drawn like the sidebar's: 24 x 24 grid, path data only (the button gives them stroke 1.5 and square caps).
export const MACHINE_ICONS = {
  /** A pencil: the nib at the lower left, the body going up to the right, and the line where the nib meets the body. */
  pencil: 'M4 20l1-5L16 4l4 4L9 19z M13 7l4 4',
  /** An arrow leaving a box towards the upper right: open the machine's page. */
  open: 'M14 4h6v6 M20 4L10 14 M18 14v6H4V6h6',
  /** A bin: remove the machine. The same drawing as the VM list's delete icon. */
  trash: 'M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13 M10 11v5 M14 11v5',
} as const

export const RENAME_LABEL = 'Rename machine'
export const OPEN_LABEL = 'Open machine'
export const REMOVE_LABEL = 'Remove'

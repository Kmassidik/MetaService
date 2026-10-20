/** One entry of the computer view's ⋯ menu. */
export interface DeskMenuItem {
  id: string
  label: string
  icon: string
  disabled: boolean
  onSelect: () => void
}

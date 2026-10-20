/** The composer tools the plus menu offers besides Attach (the composer wires Attach itself). */
export interface MenuActions {
  onFiles: () => unknown
  onSkills: () => unknown
  onMention: () => unknown
  onTeach: () => unknown
  onFind: () => unknown
  onConnect: () => unknown
  onHelp: () => unknown
}

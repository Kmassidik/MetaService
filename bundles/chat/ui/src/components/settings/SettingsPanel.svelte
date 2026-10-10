<script>
  /**
   * Settings: the section list on the left and the chosen section on the right (desktop), or one
   * screen at a time with a back arrow (phone). Lives inside the shared workspace <dialog>.
   */
  import Icon from '../Icon.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'
  import SettingsNav from './SettingsNav.svelte'
  import GeneralSection from './GeneralSection.svelte'
  import ComputerSection from './ComputerSection.svelte'
  import ConnectedAppsSection from './ConnectedAppsSection.svelte'
  import NotificationsSection from './NotificationsSection.svelte'
  import UsageSection from './UsageSection.svelte'
  import DangerSection from './DangerSection.svelte'
  import { chat, closeModal, openComputer, openFiles } from '../../lib/chatApp.svelte.js'
  import { SETTINGS, backToSettingsList, settingsSectionLabel, showSettingsSection } from '../../lib/settingsSections.js'

  const SECTION_VIEWS = {
    [SETTINGS.general]: GeneralSection,
    [SETTINGS.computer]: ComputerSection,
    [SETTINGS.apps]: ConnectedAppsSection,
    [SETTINGS.notifications]: NotificationsSection,
    [SETTINGS.usage]: UsageSection,
    [SETTINGS.danger]: DangerSection,
  }

  let { view, closeLocked = false } = $props()

  const locked = $derived(chat.loggingOut || Boolean(chat.environmentAction) || chat.deletingAccount)
  const Section = $derived(SECTION_VIEWS[chat.settings.section])
  const title = $derived(settingsSectionLabel(chat.settings.section))

  // Leaving a section abandons any half-typed delete confirmation in it.
  function select(id) {
    chat.confirmAccountDeletion = false
    chat.accountConfirmation = ''
    chat.accountDeletionError = ''
    chat.confirmEnvironmentDeletion = false
    chat.environmentConfirmation = ''
    chat.settings = showSettingsSection(chat.settings, id)
  }

  function back() {
    chat.settings = backToSettingsList(chat.settings)
  }

  // Settings rows open the big computer view or the side panel's Files tab.
  const OPENERS = { computer: openComputer, files: openFiles }

  function openPanel(panel) {
    closeModal()
    return OPENERS[panel]?.()
  }
</script>

{#snippet close()}
  <button class="icon-button" aria-label="Close settings" disabled={closeLocked} onclick={closeModal}><Icon name="close" size={ICON_SIZE.header} /></button>
{/snippet}

<div class="settings" class:list-first={chat.settings.listFirst}>
  <aside class="settings-side">
    <header class="side-head"><h2>Settings</h2><span class="phone-close">{@render close()}</span></header>
    <SettingsNav current={chat.settings.section} {locked} onSelect={select} />
  </aside>
  <div class="settings-main">
    <header class="main-head">
      <button class="icon-button back" aria-label="Back to settings" disabled={locked} onclick={back}><Icon name="back" size={ICON_SIZE.header} /></button>
      <h2 id="settings-section-title">{title}</h2>
      {@render close()}
    </header>
    <section class="main-body" aria-labelledby="settings-section-title">
      <Section {view} onSection={select} onOpen={openPanel} />
    </section>
  </div>
</div>

<style>
  .settings { display: grid; grid-template-columns: 224px minmax(0, 1fr); height: 100%; min-height: 0; }
  .settings-side { display: flex; flex-direction: column; gap: 14px; min-height: 0; padding: 18px 12px; overflow-y: auto; border-right: 1px solid var(--sidebar-line); background: var(--sidebar); }
  .side-head { display: flex; align-items: center; justify-content: space-between; min-height: 32px; padding: 0 6px 0 10px; }
  .side-head h2 { font: 600 17px/1.3 var(--font); }
  .phone-close, .back { display: none; }
  .settings-main { display: flex; flex-direction: column; min-width: 0; min-height: 0; background: var(--page); }
  .main-head { display: flex; align-items: center; gap: 8px; min-height: 60px; padding: 12px 14px 8px 28px; }
  .main-head h2 { flex: 1; min-width: 0; font: 600 20px/1.3 var(--font); }
  .main-body { flex: 1; min-height: 0; overflow-y: auto; padding: 8px 28px 28px; }
  /* Phone: one screen at a time. The list first; a section slides in over it with a back arrow. */
  @media (max-width: 520px) {
    .settings { grid-template-columns: minmax(0, 1fr); }
    .settings-side { padding: max(12px, env(safe-area-inset-top)) 16px 24px; border-right: 0; background: var(--page); }
    .side-head { padding: 0 0 0 4px; }
    .side-head h2 { font-size: 28px; font-weight: 700; }
    .phone-close, .back { display: inline-flex; }
    .main-head { min-height: 52px; padding: max(8px, env(safe-area-inset-top)) 8px 4px; }
    .main-head h2 { font-size: 17px; text-align: center; }
    .main-body { padding: 8px 16px max(24px, env(safe-area-inset-bottom)); }
    .list-first .settings-main, .settings:not(.list-first) .settings-side { display: none; }
    .settings:not(.list-first) .settings-main { animation: push-in .22s ease-out; }
  }
  @keyframes push-in { from { transform: translateX(24px); opacity: 0; } }
</style>

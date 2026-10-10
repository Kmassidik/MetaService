<script>
  /** Settings › General: who is signed in, Appearance, and Sign out. */
  import AppearancePicker from './AppearancePicker.svelte'
  import SettingsGroup from './SettingsGroup.svelte'
  import SettingsRow from './SettingsRow.svelte'
  import { chat, logout } from '../../lib/chatApp.svelte.js'
  import UserAvatar from '../UserAvatar.svelte'

  const SIGN_IN_PROVIDER = 'Google'
  const APPEARANCE_NOTE = 'System follows your device’s light or dark setting. Saved on this device.'
  const PENDING_NOTE = 'Wait for your current request to finish before signing out.'

  const user = $derived(chat.session.user)
  const signOutLocked = $derived(chat.loggingOut || Boolean(chat.environmentAction) || chat.deletingAccount || Boolean(chat.pending))
</script>

<div class="identity">
  <UserAvatar {user} class="avatar identity-avatar" />
  <div class="identity-text"><strong>{user.name}</strong><span>{user.email}</span></div>
</div>

<SettingsGroup title="Account">
  <SettingsRow label="Name" value={user.name} />
  <SettingsRow label="Email" value={user.email} />
  <SettingsRow label="Signed in with" value={SIGN_IN_PROVIDER} />
</SettingsGroup>

<SettingsGroup title="Appearance" note={APPEARANCE_NOTE}>
  <AppearancePicker />
</SettingsGroup>

<SettingsGroup note={chat.pending ? PENDING_NOTE : ''}>
  <SettingsRow label={chat.loggingOut ? 'Signing out…' : 'Sign out'} tone="danger" disabled={signOutLocked} onclick={logout} />
</SettingsGroup>
{#if chat.formError}<div class="error-box" role="alert">{chat.formError}</div>{/if}

<style>
  .identity { display: flex; align-items: center; gap: 14px; margin: 0 0 22px 4px; }
  :global(.identity-avatar) { width: 52px; height: 52px; font-size: 17px; }
  .identity-text { display: grid; min-width: 0; }
  .identity-text strong { font: 600 17px/1.3 var(--font); overflow-wrap: anywhere; }
  .identity-text span { color: var(--text-2); font: 400 var(--fs-preview)/1.4 var(--font); overflow-wrap: anywhere; }
</style>

<script>
  /**
   * Settings › Notifications: browser notifications on this device. Which events notify
   * ("needs input", "finished") stays per bot, in each bot's profile; there is no account-wide
   * default on the server, so this section only explains where those live.
   */
  import SettingsGroup from './SettingsGroup.svelte'
  import SettingsRow from './SettingsRow.svelte'
  import Switch from '../Switch.svelte'
  import {
    PERMISSION, enableNotifications, muteNotifications, notificationPermission, notificationsMuted, notificationsOn,
  } from '../../lib/notifications.js'

  const PERMISSION_DETAILS = {
    [PERMISSION.unsupported]: 'This browser can’t show notifications.',
    [PERMISSION.denied]: 'Blocked by your browser. Allow notifications for this site in your browser’s site settings.',
    [PERMISSION.default]: 'Your browser will ask once.',
    [PERMISSION.granted]: 'Shown while Ruvio is in a background tab.',
  }
  const NOTE = 'Ruvio tells you when a bot needs you or finishes a task while you’re in another tab. Saved on this device.'
  const PER_BOT_NOTE = 'Choose “needs input” and “finishes” alerts for each bot in its profile, under Notifications.'

  let permission = $state(notificationPermission())
  let muted = $state(notificationsMuted())
  let saveFailed = $state(false)

  const blocked = $derived(permission === PERMISSION.unsupported || permission === PERMISSION.denied)

  async function toggle(on) {
    if (!on) {
      saveFailed = !muteNotifications()
      muted = true
      return
    }
    muted = false
    permission = await enableNotifications()
  }
</script>

<SettingsGroup title="This device" note={NOTE}>
  <SettingsRow label="Browser notifications" detail={PERMISSION_DETAILS[permission]}>
    <Switch label="Browser notifications" checked={notificationsOn(permission, muted)} disabled={blocked} onChange={toggle} />
  </SettingsRow>
</SettingsGroup>
{#if saveFailed}<p class="form-help" role="status">This browser won’t save the setting, so it lasts for this visit only.</p>{/if}

<SettingsGroup title="Per bot" note={PER_BOT_NOTE}>
  <SettingsRow label="Needs input" value="Each bot" />
  <SettingsRow label="Finished a task" value="Each bot" />
</SettingsGroup>

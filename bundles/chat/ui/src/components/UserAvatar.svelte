<script>
  import { initials } from '../lib/format.js'

  /** The signed-in person: their Google photo, or their initials if there is none or it fails to load. */
  let { user, class: className = '' } = $props()

  let failed = $state(false)
  const photo = $derived(failed ? '' : user?.picture || '')
</script>

<span class="user-avatar {className}">
  {#if photo}
    <img src={photo} alt="" referrerpolicy="no-referrer" draggable="false" onerror={() => failed = true} />
  {:else}
    {initials(user?.name)}
  {/if}
</span>

<style>
  .user-avatar { overflow: hidden; }
  .user-avatar img { display: block; width: 100%; height: 100%; object-fit: cover; border-radius: inherit; }
</style>

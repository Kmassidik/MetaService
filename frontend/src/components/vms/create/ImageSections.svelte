<script lang="ts">
  // The two image sections of the Create VM window: "Server image" (the operating system) and "Install on top" (an optional framework or agent).
  // The request carries one bundle: the stock image for None, or the chosen framework's catalog id. The planned rows are shown and never picked, so they never reach the request.
  import { bundleOfFramework, frameworkCards, frameworkOfBundle, serverCards } from '../../../lib/imageChoices.ts'
  import { STOCK_IMAGE, type ImageOption } from '../../../lib/images.ts'
  import RichDropdown from './RichDropdown.svelte'

  interface Props {
    serverId: string
    frameworkId: string
    options: ImageOption[]
    /** The form's bundle: the stock image, or the framework's catalog id. */
    bundle: string | undefined
    /** True when the parent's list of images could not be read, so only the stock image is offered. */
    unreadable: boolean
    onpick: (bundle: string) => void
  }

  const UNREADABLE_NOTE = 'The list of images could not be read, so only the plain Ubuntu server is offered.'
  const OPTIONAL_NOTE = '(optional)'

  let { serverId, frameworkId, options, bundle, unreadable, onpick }: Props = $props()
</script>

<!-- The stock image is the only server that can be picked, so choosing it changes nothing. -->
<RichDropdown id={serverId} label="Server image" cards={serverCards(options)} chosen={STOCK_IMAGE} onpick={() => undefined}>
  {#if unreadable}<p class="note">{UNREADABLE_NOTE}</p>{/if}
</RichDropdown>
<RichDropdown id={frameworkId} label="Install on top" note={OPTIONAL_NOTE} cards={frameworkCards(options)} chosen={frameworkOfBundle(bundle)} onpick={(row) => onpick(bundleOfFramework(row))} />

<style>
  .note { margin: 0; font-size: 12px; color: var(--m50); }
</style>

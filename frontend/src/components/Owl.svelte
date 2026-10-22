<script lang="ts">
  // The owl picture for one place. It is decoration: the text next to it says the same. The pictures have a white background, so "multiply" lets it blend into any light surface. Its "white" is 254 of 255, so a tiny brightness lift makes it exact and no faint box shows.
  import { owlFor, type OwlName } from '../lib/owls.ts'

  /** `eager` for the owl that is the whole screen (login, loading, error): nothing below the fold to wait for. */
  let { name, eager = false }: { name: OwlName; eager?: boolean } = $props()
  const owl = $derived(owlFor(name))
</script>

<img class="owl" data-owl={name} src={owl.src} width={owl.size} height={owl.size} alt="" aria-hidden="true" loading={eager ? 'eager' : 'lazy'} decoding="async" />

<style>
  .owl { max-width: 100%; height: auto; flex: none; mix-blend-mode: multiply; filter: brightness(1.02); }
</style>

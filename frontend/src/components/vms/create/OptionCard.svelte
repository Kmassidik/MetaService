<script lang="ts">
  // One selectable card of a Create VM group: a real (hidden) radio inside a label, so the arrow keys, Space and the group's name work as the browser knows them.
  // A card that cannot be picked is greyed out, marked disabled, and its reason is read out with it.
  interface Props {
    /** The radio group's name: the cards of one group share it. */
    group: string
    value: string
    label: string
    caption: string
    /** Why the card cannot be picked, shown under the caption; null when there is nothing to add. */
    reason?: string | null
    selected: boolean
    disabled?: boolean
    /** A letter or two shown in a small square before the name. */
    badge?: string
    onpick: (value: string) => void
  }

  let { group, value, label, caption, reason = null, selected, disabled = false, badge, onpick }: Props = $props()
  const captionId = $derived(`${group}-${value}-caption`)
  const reasonId = $derived(`${group}-${value}-reason`)
  const describedBy = $derived(reason === null ? captionId : `${captionId} ${reasonId}`)
</script>

<label class="card" class:selected class:disabled>
  <input class="sr-only" type="radio" name={group} {value} checked={selected} {disabled} aria-disabled={disabled} aria-describedby={describedBy} onchange={() => onpick(value)} />
  <span class="head">
    {#if badge}<span class="badge" aria-hidden="true">{badge}</span>{/if}
    <span class="name">{label}</span>
  </span>
  <span class="caption" id={captionId}>{caption}</span>
  {#if reason !== null}<span class="reason" id={reasonId}>{reason}</span>{/if}
</label>

<style>
  .card { position: relative; display: flex; flex-direction: column; gap: 4px; min-width: 0; padding: 11px 12px; border: 1px solid var(--line); background: var(--surface); cursor: pointer; font-family: var(--mono); }
  .card.selected { border-color: var(--line-strong); box-shadow: inset 0 0 0 1px var(--line-strong); }
  .card:has(input:focus-visible) { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .card.disabled { cursor: not-allowed; background: var(--surface-2); color: var(--m40); }
  .head { display: flex; align-items: center; gap: 8px; min-width: 0; }
  .badge { flex: none; display: inline-grid; place-items: center; width: 20px; height: 20px; background: var(--inverse-bg); color: var(--inverse-text); font-size: 11px; font-weight: 700; }
  .disabled .badge { background: var(--reserve-bg); color: var(--m60); }
  .name { font-size: 13px; font-weight: 700; overflow-wrap: anywhere; }
  .caption, .reason { font-size: 11px; line-height: 1.4; color: var(--m50); overflow-wrap: anywhere; }
  .disabled .caption { color: var(--m60); }
  .reason { color: var(--m60); }
</style>

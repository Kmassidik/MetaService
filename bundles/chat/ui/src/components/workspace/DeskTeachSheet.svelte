<script>
  import Icon from '../Icon.svelte'

  const NAME_MAX = 80
  const DESCRIPTION_MAX = 4000

  let { name = $bindable(''), description = $bindable(''), locked = false, onTeach, onClose } = $props()

  const ready = $derived(!locked && Boolean(name.trim()) && Boolean(description.trim()))
</script>

<section class="desk-teach" aria-label="Teach a task">
  <header>
    <h3>Teach a task</h3>
    <button type="button" class="icon-button" aria-label="Close teach a task" onclick={onClose}><Icon name="close" size={16} /></button>
  </header>
  <input class="form-input" placeholder="Skill name" maxlength={NAME_MAX} bind:value={name} disabled={locked} aria-label="Skill name" />
  <textarea class="form-input" rows="2" maxlength={DESCRIPTION_MAX} placeholder="Describe the result you want…" bind:value={description} disabled={locked} aria-label="Task description"></textarea>
  <div class="desk-teach-actions">
    <p>Click recording comes later.</p>
    <button type="button" class="primary-button" disabled={!ready} onclick={onTeach}><Icon name="spark" size={15} />Teach</button>
  </div>
</section>

<style>
  .desk-teach {
    display: grid;
    gap: 8px;
    margin: 8px 12px 0;
    padding: 12px 14px 14px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-card);
    background: var(--surface);
    box-shadow: var(--shadow-float);
  }
  .desk-teach header { display: flex; align-items: center; justify-content: space-between; }
  .desk-teach h3 { color: var(--text); font: 600 var(--fs-name)/1.3 var(--font); }
  .desk-teach-actions { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
  .desk-teach-actions p { color: var(--text-2); font: 400 var(--fs-time)/1.4 var(--font); }
  .desk-teach-actions .primary-button { min-height: 34px; padding: 6px 16px; }
</style>

<script>
  let { counts } = $props()
</script>

<dl class="strip">
  <div><dt>Machines</dt><dd class="nums">{counts.machines}</dd></div>
  <div><dt>Online</dt><dd class="nums">{counts.online}</dd></div>
  <div><dt>Workloads</dt><dd class="nums">{counts.workloads}</dd></div>
</dl>

<style>
  .strip { display: flex; gap: 28px; margin: 0; flex-wrap: wrap; }
  div { display: grid; gap: 0; }
  dt { font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: var(--muted); font-weight: 600; }
  dd { margin: 0; font-size: 28px; font-weight: 700; letter-spacing: -0.02em; }
</style>

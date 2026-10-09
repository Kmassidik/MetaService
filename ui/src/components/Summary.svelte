<script>
  let { counts } = $props()
</script>

<div class="caps">
  <div class="m">Machines <b class="nums">{counts.machines}</b></div>
  <div class="m">Online <b class="nums">{counts.online}</b></div>
  <div class="m">Workloads <b class="nums">{counts.workloads}</b></div>
</div>

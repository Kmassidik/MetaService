<script lang="ts">
  // One small row icon of a machine card, drawn inline like the sidebar's: a 24 x 24 grid, path data only, stroked in the row's own colour.
  // It is decoration beside a word, so it is hidden from screen readers; the word it sits next to is the label.
  let { path }: { path: string } = $props()
</script>

<svg class="glyph" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d={path} /></svg>

<style>
  .glyph { width: 14px; height: 14px; flex: none; stroke: currentColor; fill: none; stroke-width: 1.6; stroke-linecap: square; stroke-linejoin: miter; }
</style>

<script lang="ts">
  // Shown for as long as the sample data is on screen. It sticks to the top of the page, so it never scrolls out of sight and never covers the page's own header.
  import { securityHref, type SecurityView } from '../../lib/securityRoute.ts'

  let { view }: { view: SecurityView } = $props()
</script>

<div class="banner-loud" role="alert" data-testid="preview-banner">
  <b>SAMPLE DATA. These numbers are made up to show the page. Nothing here is real.</b>
  <a href={securityHref({ ...view, preview: false })}>Leave the preview</a>
</div>

<style>
  .banner-loud {
    position: sticky; top: 0; z-index: 90; display: flex; align-items: center; justify-content: center; gap: 8px 18px; flex-wrap: wrap;
    padding: 10px 16px; background: var(--danger-d); color: #fff; font-family: var(--mono); font-size: 12px; letter-spacing: 0.04em; text-align: center;
  }
  a { color: #fff; text-decoration: underline; white-space: nowrap; }
</style>

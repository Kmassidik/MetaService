/** DOM helpers for file components: Svelte attachments, no state of their own. */

// Start downloading a picture a little before it scrolls into view.
const VISIBLE_MARGIN = '200px'

/** Moves the node to <body> so a full-screen overlay escapes panels, transforms and their keys. */
export function portal(node) {
  document.body.appendChild(node)
  return () => node.remove()
}

/** Calls `onVisible` once, when the node first comes near the viewport. */
export function whenVisible(onVisible) {
  return node => {
    if (typeof IntersectionObserver === 'undefined') {
      onVisible()
      return undefined
    }
    const observer = new IntersectionObserver(entries => {
      if (!entries.some(entry => entry.isIntersecting)) return
      observer.disconnect()
      onVisible()
    }, { rootMargin: VISIBLE_MARGIN })
    observer.observe(node)
    return () => observer.disconnect()
  }
}

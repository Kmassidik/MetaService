// Applies the saved theme before first paint, so dark mode never flashes white.
// Same storage key and values as src/lib/theme.js. Plain script (not a module) so it runs at once.
try {
  var savedTheme = localStorage.getItem('ruvio-theme')
  if (savedTheme === 'light' || savedTheme === 'dark') document.documentElement.dataset.theme = savedTheme
} catch (error) { /* storage blocked: follow the system */ }

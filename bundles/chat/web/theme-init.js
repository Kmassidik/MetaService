// Applies the saved theme before first paint, so dark mode never flashes white. Same storage key as the Ruvio chat on the chat platform.
try {
  var savedTheme = localStorage.getItem('ruvio-theme')
  if (savedTheme === 'light' || savedTheme === 'dark') document.documentElement.dataset.theme = savedTheme
} catch (error) { /* storage blocked: follow the system */ }

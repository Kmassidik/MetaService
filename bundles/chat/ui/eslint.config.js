import js from '@eslint/js'
import globals from 'globals'
import svelte from 'eslint-plugin-svelte'

// Structure guardrails (docs/product/PLAN-code-structure.md §3). Warn-only until the existing
// offenders are split; `npm run lint` still passes. For .svelte, max-lines counts the whole
// component (markup and style too).
const SOFT_CAP_LINES = 400
const MAX_FUNCTION_LINES = 40
const MAX_BLOCK_DEPTH = 2 // depth 3 = an `if` nested inside an `if`
const MAX_COMPLEXITY = 10
const structureRules = {
  'max-lines': ['warn', { max: SOFT_CAP_LINES, skipBlankLines: true, skipComments: true }],
  'max-lines-per-function': ['warn', { max: MAX_FUNCTION_LINES, skipBlankLines: true, skipComments: true }],
  'max-depth': ['warn', MAX_BLOCK_DEPTH],
  'complexity': ['warn', MAX_COMPLEXITY],
  'no-magic-numbers': ['warn', {
    ignore: [-1, 0, 1, 2],
    ignoreArrayIndexes: true,
    ignoreDefaultValues: true,
    ignoreClassFieldInitialValues: true,
  }],
}

export default [
  { ignores: ['dist/**', 'node_modules/**', 'landing/**'] },
  js.configs.recommended,
  ...svelte.configs['flat/recommended'],
  {
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
      globals: { ...globals.browser },
    },
    rules: {
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-empty': ['error', { allowEmptyCatch: true }],
      'prefer-const': 'error',
      'no-var': 'error',
      'eqeqeq': ['error', 'always'],
      'svelte/prefer-svelte-reactivity': 'off',
      'svelte/require-each-key': 'warn',
      'preserve-caught-error': 'off',
      ...structureRules,
    },
  },
  {
    files: ['**/*.test.js'],
    rules: {
      // describe/it callbacks and fixture values are long and literal by nature.
      'max-lines-per-function': 'off',
      'no-magic-numbers': 'off',
    },
  },
  {
    files: ['**/*.svelte'],
    rules: {
      // Svelte 5 `$props()` / `$bindable` destructuring trips prefer-const.
      'prefer-const': 'off',
    },
  },
  {
    files: ['src/components/Markdown.svelte'],
    rules: {
      // Markdown is sanitized server/client-side before {@html}.
      'svelte/no-at-html-tags': 'off',
    },
  },
]

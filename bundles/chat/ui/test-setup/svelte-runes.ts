import { plugin } from 'bun'
import { compileModule } from 'svelte/compiler'

const transpiler = new Bun.Transpiler({ loader: 'ts' })

plugin({
  name: 'svelte-runes',
  setup(build) {
    build.onLoad({ filter: /\.svelte\.(ts|js)$/ }, async ({ path }) => {
      const source = await Bun.file(path).text()
      const js = path.endsWith('.ts') ? transpiler.transformSync(source) : source
      const compiled = compileModule(js, { filename: path, generate: 'client' })
      return { contents: compiled.js.code, loader: 'js' }
    })
  },
})

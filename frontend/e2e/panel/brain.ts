// The AI provider card, its test button, the Token ledger, and the old address that still lands on Settings.
import { check } from '../support/check.ts'
import type { Browse } from '../support/page.ts'
import { AI_KEY, type World } from './world.ts'

const ANSWER_WAIT_MS = 15000

export async function brainScenario(b: Browse, world: World): Promise<void> {
  await b.go('#/settings')
  await b.until(() => /ai provider/i.test(document.body.innerText), {})
  const shown = await b.text()
  check('the AI card says configured with the model and host but never the key', shown.includes('Configured') && shown.includes('fake-model') && shown.includes('127.0.0.1') && !shown.includes(AI_KEY))
  await b.click('Test connection')
  await b.until(() => document.body.innerText.includes('Connected: the provider answered'), { timeout: ANSWER_WAIT_MS })
  await b.until(() => /root[\s\S]*1 reply[\s\S]*9 tokens in/.test(document.body.innerText), { timeout: ANSWER_WAIT_MS })
  check('a good test says so and the use shows up', true)
  world.provider.failing = true
  await b.click('Test connection')
  await b.until(() => document.body.innerText.includes('did not answer'), { timeout: ANSWER_WAIT_MS })
  check('a failing provider is reported in plain words without its details', !(await b.text()).includes('nope'))
  await b.shot('brain.png', true)
  world.provider.failing = false
  await b.go('#/usage')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Token ledger', {})
  await b.shot('ledger.png')
  check('the Token ledger lists the use per machine with totals', await b.run(() => [...document.querySelectorAll('tbody tr')].some((row) => row instanceof HTMLElement && /root/.test(row.innerText) && /9/.test(row.innerText)) && /TOKENS IN\s*9/i.test(document.body.innerText)))
  await b.go('#/ai')
  await b.until(() => document.querySelector('.phead h1')?.textContent === 'Settings', {})
  const settings = await b.text()
  check('an older address (the AI provider) still lands on Settings', /ai provider/i.test(settings) && /chat bundle/i.test(settings))
}

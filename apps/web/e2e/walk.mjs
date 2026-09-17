// Прогон интерфейса в браузере: скриншоты страниц по ролям и ошибки консоли. node e2e-walk.mjs <outDir>
import { chromium } from '@playwright/test'

const out = process.argv[2] ?? '/tmp'
const base = process.env.WEB_URL ?? 'http://127.0.0.1:5173'
const pages = [
  { role: 'regulator', path: '/gov', wait: 'Индекс за' },
  { role: 'regulator', path: '/gov/regions/75', wait: 'Сигналы региона' },
  { role: 'regulator', path: '/gov/simulator', wait: 'Результат для' },
  { role: 'regulator', path: '/gov/insight', wait: 'Вопрос' },
  { role: 'regulator', path: '/gov/organizations/028B?kato=75&profile=381', wait: 'Сигналы организации' },
  { role: 'regulator', path: '/quality', wait: 'Качество' },
  { role: 'regulator', path: '/doctor/decisions', wait: 'Журнал решений' },
  { role: 'doctor', path: '/doctor/referral', wait: 'Альтернативы в регионе' },
  { role: 'doctor', path: '/doctor/worklist', wait: 'Приоритет' },
  { role: 'doctor', path: '/doctor/decisions', wait: 'Журнал решений' },
  { role: 'doctor', path: '/doctor/scribe', wait: 'AI-скрайб приёма' },
  { role: 'steward', path: '/steward', wait: 'Партии' },
  { role: null, path: '/wait', wait: 'В среднем по региону' },
  { role: null, path: '/medicines', wait: 'Покрытие' },
]
const browser = await chromium.launch()
const context = await browser.newContext({ viewport: { width: 1360, height: 900 }, locale: 'ru-RU' })
const page = await context.newPage()
const errors = []
page.on('console', (m) => { if (m.type() === 'error') errors.push(`${m.location().url}: ${m.text()}`) })
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`))
for (const step of pages) {
  await page.goto(base + '/', { waitUntil: 'networkidle' })
  await page.evaluate((role) => { if (role) localStorage.setItem('darumen.role', role); else localStorage.removeItem('darumen.role') }, step.role)
  await page.goto(base + step.path, { waitUntil: 'networkidle' })
  let ok = true
  try {
    await page.getByText(step.wait, { exact: false }).first().waitFor({ timeout: 20000 })
  } catch {
    ok = false
  }
  await page.waitForTimeout(1500)
  const name = step.path.replace(/\W+/g, '_').replace(/^_/, '') || 'home'
  await page.screenshot({ path: `${out}/${name}.png`, fullPage: false })
  const problem = await page.locator('.p-message-error').allTextContents()
  console.log(`${ok ? 'OK ' : 'MISS'} ${step.role ?? 'guest'} ${step.path} ${problem.length ? 'problem: ' + problem.join(' | ').slice(0, 160) : ''}`)
}
console.log(errors.length ? 'console errors:\n' + [...new Set(errors)].slice(0, 12).join('\n') : 'no console errors')
await browser.close()

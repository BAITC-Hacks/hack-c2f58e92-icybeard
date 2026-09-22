// Прогон интерфейса в браузере: вход через Keycloak по ролям, скриншоты страниц (RU и KK, светлая и тёмная тема)
// и ошибки консоли. Предпосылки: make serve (Keycloak :8080 + API :8000) и npm run dev (:5173).
// node e2e/walk.mjs <outDir>; WEB_URL и WALK_PASSWORD — переопределение стенда и пароля realm.
import { chromium } from '@playwright/test'

const out = process.argv[2] ?? '/tmp'
const base = process.env.WEB_URL ?? 'http://localhost:5173'
const password = process.env.WALK_PASSWORD ?? 'darumen'
const users = { citizen: 'citizen1', doctor: 'doctor1', chief: 'chief1', regulator: 'regulator1', steward: 'steward1' }
const pages = [
  { role: null, path: '/', wait: 'Войти через eGov mobile', variants: true },
  { role: null, path: '/wait', wait: 'В среднем по региону', variants: true },
  { role: null, path: '/medicines', wait: 'Покрытие' },
  { role: 'citizen', path: '/me/route', wait: 'Мой путь', variants: true },
  { role: 'doctor', path: '/doctor/patients/SYN-75-028B-381-01', wait: 'Маршрут пациента' },
  { role: 'regulator', path: '/gov', wait: 'Индекс за', variants: true },
  { role: 'regulator', path: '/gov/regions/75', wait: 'Сигналы региона' },
  { role: 'regulator', path: '/gov/simulator', wait: 'Результат для' },
  { role: 'regulator', path: '/gov/insight', wait: 'Вопрос' },
  { role: 'regulator', path: '/gov/organizations/028B?kato=75&profile=381', wait: 'Сигналы организации' },
  { role: 'regulator', path: '/quality', wait: 'Качество' },
  { role: 'regulator', path: '/doctor/decisions', wait: 'Журнал решений' },
  { role: 'doctor', path: '/doctor/referral', wait: 'Альтернативы в регионе', variants: true },
  { role: 'doctor', path: '/doctor/worklist', wait: 'Приоритет' },
  { role: 'doctor', path: '/doctor/decisions', wait: 'Журнал решений' },
  { role: 'doctor', path: '/doctor/scribe', wait: 'AI-скрайб приёма' },
  { role: 'steward', path: '/steward', wait: 'Партии' },
]
// Дополнительные проходы для страниц с variants: казахский и тёмная тема (ключи localStorage приложения)
const variants = [
  { suffix: '', storage: { 'darumen.locale': 'ru', 'darumen.theme': 'light' } },
  { suffix: '_kk', storage: { 'darumen.locale': 'kk', 'darumen.theme': 'light' } },
  { suffix: '_dark', storage: { 'darumen.locale': 'ru', 'darumen.theme': 'dark' } },
]

const browser = await chromium.launch()
const errors = []
const contexts = new Map()

/** Один контекст браузера на роль: вход через форму Keycloak, тот же путь, что у login-check.mjs. */
async function pageFor(role) {
  if (contexts.has(role)) return contexts.get(role)
  const context = await browser.newContext({ viewport: { width: 1360, height: 900 }, locale: 'ru-RU' })
  const page = await context.newPage()
  page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('GL Driver')) errors.push(`${m.location().url}: ${m.text()}`) })
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`))
  await page.goto(base + '/', { waitUntil: 'networkidle' })
  if (role) {
    await page.getByTestId('login-primary').click()
    await page.waitForURL(/realms\/darumen/, { timeout: 30000 })
    await page.fill('#username', users[role])
    await page.fill('#password', password)
    await page.click('#kc-login')
    await page.waitForURL(base + '/**', { timeout: 30000 })
    await page.waitForTimeout(1000)
  }
  contexts.set(role, page)
  return page
}

for (const step of pages) {
  const page = await pageFor(step.role)
  for (const variant of step.variants ? variants : variants.slice(0, 1)) {
    await page.evaluate((storage) => { for (const [key, value] of Object.entries(storage)) localStorage.setItem(key, value) }, variant.storage)
    await page.goto(base + step.path, { waitUntil: 'networkidle' })
    // маркеры готовности — русские; в казахском проходе ждём заголовок страницы
    const ready = variant.storage['darumen.locale'] === 'kk' ? page.locator('main h1').first() : page.getByText(step.wait, { exact: false }).first()
    let ok = true
    try {
      await ready.waitFor({ timeout: 20000 })
    } catch {
      ok = false
    }
    await page.waitForTimeout(1500)
    const name = (step.path.replace(/\W+/g, '_').replace(/^_/, '') || 'home') + variant.suffix
    await page.screenshot({ path: `${out}/${name}.png`, fullPage: false })
    const problem = await page.locator('.p-message-error').allTextContents()
    console.log(`${ok ? 'OK ' : 'MISS'} ${step.role ?? 'guest'} ${step.path}${variant.suffix} ${problem.length ? 'problem: ' + problem.join(' | ').slice(0, 160) : ''}`)
  }
}
console.log(errors.length ? 'console errors:\n' + [...new Set(errors)].slice(0, 12).join('\n') : 'no console errors')
await browser.close()

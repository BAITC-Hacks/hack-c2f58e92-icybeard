// Проверка входа через Keycloak в Docker-сборке: http://localhost:3000 → Войти → regulator1 → карта регионов
import { chromium } from '@playwright/test'
const out = process.argv[2] ?? '/tmp'
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } })
const errors = []
const api = []
page.on('pageerror', (e) => errors.push(e.message))
page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('GL Driver')) errors.push(m.text().slice(0, 160)) })
page.on('response', (r) => { if (r.url().includes('/api/v1/')) api.push(`${r.status()} ${r.url().replace('http://localhost:3000', '')}`) })
try {
  await page.goto('http://localhost:3000/', { waitUntil: 'networkidle' })
  console.log('home has login panel:', await page.getByTestId('login-egov').count())
  await page.getByTestId('login-primary').click()
  await page.waitForURL(/realms\/darumen/, { timeout: 30000 })
  await page.fill('#username', 'regulator1')
  await page.fill('#password', 'darumen')
  await page.click('#kc-login')
  await page.waitForURL('http://localhost:3000/**', { timeout: 30000 })
  await page.waitForTimeout(2500)
  console.log('after login url:', page.url(), '| user shown:', await page.getByText('regulator1').count(), '| nav map:', await page.locator('nav a', { hasText: 'Карта регионов' }).count())
  await page.locator('nav a', { hasText: 'Карта регионов' }).click()
  await page.getByText('Индекс за', { exact: false }).first().waitFor({ timeout: 60000 })
  await page.waitForTimeout(3000)
  console.log('markers:', await page.locator('.region-marker').count())
} catch (e) {
  console.log('FAILED:', String(e).split('\n')[0])
} finally {
  await page.screenshot({ path: `${out}/docker_gov_keycloak.png` })
  console.log('api calls:', api.slice(-8))
  console.log('errors:', errors)
  await browser.close()
}

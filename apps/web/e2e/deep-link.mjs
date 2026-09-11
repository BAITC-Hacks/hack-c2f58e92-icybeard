// Прямая ссылка на защищённую страницу после входа через Keycloak: страница должна открыться, а не уйти на главную.
// Запуск: node e2e/deep-link.mjs [путь] [профиль]; снимки в e2e/shots/.
import { chromium } from '@playwright/test'
import { mkdirSync } from 'node:fs'

const base = process.env.WEB_URL ?? 'http://localhost:3000'
const path = process.argv[2] ?? '/gov/regions/19'
const profileFilter = process.argv[3]
mkdirSync('e2e/shots', { recursive: true })

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } })
await page.goto(base + '/', { waitUntil: 'networkidle' })
await page.getByRole('button', { name: 'Войти' }).click()
await page.waitForURL(/realms\/darumen/, { timeout: 30000 })
await page.fill('#username', 'regulator1')
await page.fill('#password', 'darumen')
await page.click('#kc-login')
await page.waitForURL(base + '/**', { timeout: 30000 })

await page.goto(base + path, { waitUntil: 'networkidle' })
await page.waitForTimeout(3000)
const url = page.url()
if (!url.startsWith(base + path)) {
  console.error(`FAIL: ожидали ${base + path}, получили ${url}`)
  await browser.close()
  process.exit(1)
}
await page.waitForSelector('canvas', { timeout: 30000 })
await page.screenshot({ path: 'e2e/shots/deep-link.png', fullPage: true })
console.log(`OK ${url}; заголовок: ${await page.locator('h1').first().innerText()}`)

if (profileFilter) {
  const select = page.locator('.p-select').first()
  await select.click()
  await page.locator('.p-select-filter').fill(profileFilter)
  await page.locator('.p-select-option').first().click()
  await page.waitForTimeout(4000)
  await page.screenshot({ path: `e2e/shots/deep-link-${profileFilter}.png`, fullPage: true })
  console.log(`OK профиль ${profileFilter}: ${(await page.locator('.muted').nth(1).innerText()).slice(0, 160)}`)
}
await browser.close()

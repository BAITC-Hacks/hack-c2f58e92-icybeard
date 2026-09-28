import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia, type Pinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import App from '@/App.vue'
import EmailOutageBanner from '@/components/app/EmailOutageBanner.vue'
import StateEmailOff from '@/components/states/StateEmailOff.vue'
import { i18n } from '@/i18n'
import { EMAIL_BANNER_KEY } from '@/lib/serviceStatus'
import { useAuthStore } from '@/stores/auth'
import { useServiceStatusStore } from '@/stores/serviceStatus'
import { memoryStorage, plugins, statusBody, UP } from './serviceFixtures'

const BANNER_RU = 'Почтовый сервер недоступен. Письма — приглашения, сброс пароля, уведомления — сейчас не отправляются.'
let pinia: Pinia

function withStatus(status: ReturnType<typeof statusBody> | null) {
  useServiceStatusStore().status = status
}

describe('email outage banner', () => {
  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    Object.defineProperty(window, 'sessionStorage', { value: memoryStorage(), configurable: true })
    i18n.global.locale.value = 'ru'
  })
  afterEach(() => {
    i18n.global.locale.value = 'ru'
    document.body.innerHTML = ''
  })

  it('is shown only while the API says email is unavailable', async () => {
    const wrapper = mount(EmailOutageBanner, { global: { plugins: [...plugins(pinia)] } })
    expect(wrapper.find('[data-testid="email-outage-banner"]').exists()).toBe(false) // статус неизвестен

    withStatus(statusBody())
    await flushPromises()
    const banner = wrapper.get('[data-testid="email-outage-banner"]')
    expect(banner.text()).toContain(BANNER_RU)
    expect(banner.attributes('role')).toBe('status')

    withStatus(statusBody({ email: UP }))
    await flushPromises()
    expect(wrapper.find('[data-testid="email-outage-banner"]').exists()).toBe(false)
  })

  it('speaks Kazakh', async () => {
    i18n.global.locale.value = 'kk'
    withStatus(statusBody())
    const wrapper = mount(EmailOutageBanner, { global: { plugins: [...plugins(pinia)] } })
    expect(wrapper.text()).toContain('Пошта сервері қолжетімсіз')
  })

  it('is dismissed for the browser session', async () => {
    withStatus(statusBody())
    const wrapper = mount(EmailOutageBanner, { global: { plugins: [...plugins(pinia)] } })
    await wrapper.get('[data-testid="email-outage-dismiss"]').trigger('click')
    expect(wrapper.find('[data-testid="email-outage-banner"]').exists()).toBe(false)
    expect(window.sessionStorage.getItem(EMAIL_BANNER_KEY)).toBe('smtp_not_configured')

    // новая сессия — баннер вернулся
    Object.defineProperty(window, 'sessionStorage', { value: memoryStorage(), configurable: true })
    pinia = createPinia()
    setActivePinia(pinia)
    withStatus(statusBody())
    const again = mount(EmailOutageBanner, { global: { plugins: [...plugins(pinia)] } })
    expect(again.find('[data-testid="email-outage-banner"]').exists()).toBe(true)
  })

  it('email notices in flows follow the same status', async () => {
    const wrapper = mount(StateEmailOff, { props: { text: 'письмо не уйдёт' }, global: { plugins: [...plugins(pinia)] } })
    expect(wrapper.find('[data-testid="email-off"]').exists()).toBe(false)
    withStatus(statusBody())
    await flushPromises()
    expect(wrapper.get('[data-testid="email-off"]').text()).toBe('письмо не уйдёт')
  })
})

describe('app shell', () => {
  const Page = defineComponent({ render: () => h('main', { class: 'page' }, 'page') })

  async function mountApp(path: string, signedIn: boolean) {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', component: Page },
        { path: '/signup', component: Page, meta: { public: true } },
        { path: '/leaflet', component: Page, meta: { bare: true } },
      ],
    })
    await router.push(path)
    await router.isReady()
    if (signedIn) useAuthStore().actor = 'doctor1'
    withStatus(statusBody())
    return mount(App, {
      global: { plugins: [...plugins(pinia), router], stubs: { AppSidebar: true, AppTopbar: true, PublicBar: true, Toast: true } },
    })
  }

  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    Object.defineProperty(window, 'sessionStorage', { value: memoryStorage(), configurable: true })
  })

  it('shows the banner to a signed-in user above the page', async () => {
    const wrapper = await mountApp('/', true)
    const main = wrapper.get('.shell-main').element
    const banner = wrapper.get('[data-testid="email-outage-banner"]').element
    expect(banner.compareDocumentPosition(wrapper.get('.page').element) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(main.contains(banner)).toBe(true)
  })

  it('does not show the banner on the login page, public and bare pages', async () => {
    expect((await mountApp('/', false)).find('[data-testid="email-outage-banner"]').exists()).toBe(false)
    expect((await mountApp('/signup', true)).find('[data-testid="email-outage-banner"]').exists()).toBe(false)
    expect((await mountApp('/leaflet', true)).find('[data-testid="email-outage-banner"]').exists()).toBe(false)
  })
})

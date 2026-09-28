import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia, type Pinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import LoginPanel from '@/components/app/LoginPanel.vue'
import { i18n } from '@/i18n'
import { useAuthStore } from '@/stores/auth'
import { useServiceStatusStore } from '@/stores/serviceStatus'
import { plugins, statusBody, UP } from './serviceFixtures'

let pinia: Pinia

function mountPanel() {
  return mount(LoginPanel, { attachTo: document.body, global: { plugins: [...plugins(pinia)] } })
}

describe('LoginPanel · eGov mobile', () => {
  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    i18n.global.locale.value = 'ru'
  })
  afterEach(() => {
    vi.restoreAllMocks()
    document.body.innerHTML = ''
  })

  it.each([
    ['status unknown (request failed)', null],
    ['endpoint not provided', statusBody()],
  ])('%s: the button stays, is captioned unavailable and explains the password login', async (_, status) => {
    useServiceStatusStore().status = status
    const login = vi.spyOn(useAuthStore(), 'login').mockResolvedValue()
    const wrapper = mountPanel()

    const egov = wrapper.get('[data-testid="login-egov"]')
    expect(egov.text()).toContain('Войти через eGov mobile')
    expect(egov.classes()).toContain('p-button-secondary')
    expect(wrapper.get('[data-testid="login-primary"]').classes()).not.toContain('p-button-secondary')
    expect(wrapper.get('[data-testid="egov-unavailable"]').text()).toBe('Недоступно: адрес сервиса eGov mobile не предоставлен')

    await egov.trigger('click')
    await flushPromises()
    expect(login).not.toHaveBeenCalled()
    const dialog = document.body.querySelector('[data-testid="egov-roadmap"]')
    expect(dialog?.textContent).toContain('Вход через eGov mobile недоступен')
    expect(dialog?.textContent).toContain('Адрес сервиса eGov mobile (Smart Bridge) не предоставлен, поэтому вход через eGov недоступен. Войдите по логину и паролю.')

    ;(document.body.querySelector('[data-testid="login-from-roadmap"]') as HTMLButtonElement).click()
    expect(login).toHaveBeenCalledWith()
    wrapper.unmount()
  })

  it('available: signs in through the realm broker with idpHint egov, no caption', async () => {
    useServiceStatusStore().status = statusBody({ egov: UP })
    const login = vi.spyOn(useAuthStore(), 'login').mockResolvedValue()
    const wrapper = mountPanel()

    expect(wrapper.find('[data-testid="egov-unavailable"]').exists()).toBe(false)
    expect(wrapper.get('[data-testid="login-egov"]').classes()).not.toContain('p-button-secondary')
    await wrapper.get('[data-testid="login-egov"]').trigger('click')
    expect(login).toHaveBeenCalledWith({ idpHint: 'egov' })
    expect(document.body.querySelector('[data-testid="egov-roadmap"]')).toBeNull()
    wrapper.unmount()
  })

  it('speaks Kazakh', () => {
    i18n.global.locale.value = 'kk'
    useServiceStatusStore().status = statusBody()
    const wrapper = mountPanel()
    expect(wrapper.get('[data-testid="egov-unavailable"]').text()).toBe('Қолжетімсіз: eGov mobile сервисінің мекенжайы берілмеген')
    wrapper.unmount()
    i18n.global.locale.value = 'ru'
  })
})

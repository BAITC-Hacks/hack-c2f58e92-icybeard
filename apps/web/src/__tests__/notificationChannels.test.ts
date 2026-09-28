import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia, type Pinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { account } from '@/api/endpoints'
import type { NotificationSettings } from '@/api/types'
import { i18n } from '@/i18n'
import { useServiceStatusStore } from '@/stores/serviceStatus'
import NotificationsView from '@/views/account/NotificationsView.vue'
import { plugins, statusBody, UP } from './serviceFixtures'

/** Сохранённые настройки пользователя: почта и push у рекомендаций включены — они не должны пропасть. */
const SAVED: NotificationSettings = {
  events: [
    { code: 'new_recommendation', titleRu: 'Новая рекомендация по пациенту', inApp: true, email: true, sms: false, push: true },
    { code: 'security', titleRu: 'Безопасность аккаунта', inApp: true, email: true, sms: true, push: true, locked: true },
  ],
  quietFrom: null, quietTo: null, quietExceptRegulator: true, digest: 'daily',
}
let pinia: Pinia

async function mountView() {
  const wrapper = mount(NotificationsView, { global: { plugins: [...plugins(pinia)], stubs: { AccountTabs: true, RouterLink: true } } })
  await flushPromises()
  return wrapper
}
const box = (wrapper: Awaited<ReturnType<typeof mountView>>, event: string, channel: string) =>
  wrapper.get(`[data-testid="notify-${event}-${channel}"] input`).element as HTMLInputElement

describe('notification settings · channel availability', () => {
  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    i18n.global.locale.value = 'ru'
    vi.spyOn(account, 'notifications').mockResolvedValue(structuredClone(SAVED))
    // Select из PrimeVue подписывается на ориентацию экрана, а в jsdom matchMedia нет
    vi.stubGlobal('matchMedia', (query: string) => ({ matches: false, media: query, addEventListener: () => {}, removeEventListener: () => {} }))
  })
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('disables email, SMS and push with reasons while only in-app notifications are delivered', async () => {
    useServiceStatusStore().status = statusBody()
    const wrapper = await mountView()

    expect(box(wrapper, 'new_recommendation', 'inApp').disabled).toBe(false)
    for (const channel of ['email', 'sms', 'push']) expect(box(wrapper, 'new_recommendation', channel).disabled).toBe(true)
    // отметки сохранены как были, просто недоступны
    expect(box(wrapper, 'new_recommendation', 'email').checked).toBe(true)
    expect(box(wrapper, 'new_recommendation', 'push').checked).toBe(true)

    expect(wrapper.get('[data-testid="channel-off-email"]').text()).toBe('почтовый сервер не настроен')
    expect(wrapper.get('[data-testid="channel-off-sms"]').text()).toBe('Сервис ещё не подключён')
    expect(wrapper.get('[data-testid="channel-off-push"]').text()).toBe('Сервис ещё не подключён')
    expect(wrapper.find('[data-testid="channel-off-inApp"]').exists()).toBe(false)
    expect(wrapper.get('[data-testid="notifications-delivery-note"]').text()).toContain('Сейчас уведомления доставляются только в системе')
    expect(wrapper.find('[data-testid="digest-email-off"]').exists()).toBe(true)
  })

  it('labels an unreachable mail server and keeps stored preferences on save', async () => {
    useServiceStatusStore().status = statusBody({ email: { available: false, reason: 'smtp_unreachable' } })
    const save = vi.spyOn(account, 'saveNotifications').mockImplementation(async (body) => body)
    const wrapper = await mountView()
    expect(wrapper.get('[data-testid="channel-off-email"]').text()).toBe('почтовый сервер не отвечает')

    await wrapper.get('[data-testid="notify-new_recommendation-inApp"] input').trigger('change')
    await wrapper.get('[data-testid="notifications-save"]').trigger('click')
    await flushPromises()
    const sent = save.mock.calls[0]![0].events.find((e) => e.code === 'new_recommendation')!
    expect(sent).toMatchObject({ inApp: false, email: true, sms: false, push: true })
  })

  it('enables channels the API reports as working; email stays enabled while its status is unknown', async () => {
    useServiceStatusStore().status = statusBody({ email: UP, sms: UP })
    let wrapper = await mountView()
    expect(box(wrapper, 'new_recommendation', 'email').disabled).toBe(false)
    expect(box(wrapper, 'new_recommendation', 'sms').disabled).toBe(false)
    expect(box(wrapper, 'new_recommendation', 'push').disabled).toBe(true)
    expect(wrapper.get('[data-testid="notifications-delivery-note"]').text()).toBe(
      'Сейчас не доставляются: Push. Отметки в этих колонках сохраняются и заработают, когда каналы снова будут доступны.',
    )
    wrapper.unmount()

    useServiceStatusStore().status = null
    wrapper = await mountView()
    expect(box(wrapper, 'new_recommendation', 'email').disabled).toBe(false)
    expect(box(wrapper, 'new_recommendation', 'sms').disabled).toBe(true)
    expect(box(wrapper, 'new_recommendation', 'push').disabled).toBe(true)
  })
})

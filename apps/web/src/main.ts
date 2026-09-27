import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import { createApp } from 'vue'
import '@fontsource-variable/manrope'
import 'primeicons/primeicons.css'
import 'maplibre-gl/dist/maplibre-gl.css'
import './styles/tokens.css'
import './styles/base.css'
import App from './App.vue'
import { i18n } from './i18n'
import { useAuthStore } from './stores/auth'
import { DarumenPreset } from './styles/preset'

const app = createApp(App)
app.use(createPinia())
// стили PrimeVue — в слое primevue, поэтому обычный CSS приложения перекрывает их без !important
app.use(PrimeVue, { theme: { preset: DarumenPreset, options: { darkModeSelector: '.darumen-dark', cssLayer: { name: 'primevue', order: 'primevue, app' } } } })
app.use(ToastService)
app.use(i18n)

// Маршрутизатор подключается только после проверки сессии: его первая навигация сразу запускает защиту
// маршрутов и переход по роли, и при переходе по прямой ссылке (например /gov/regions/19) роли уже должны быть известны.
// Сам модуль роутера импортируется тоже только теперь: createWebHistory() запоминает адрес в момент создания,
// а keycloak-js убирает #state/#code/#error после редиректа проверки сессии уже внутри init() — иначе первая
// навигация роутера возвращала бы в адрес устаревший фрагмент.
// Разрешения (GET /api/v1/me) тоже нужны до первой навигации: без них защита маршрутов и домашний экран считались бы
// по фолбэку из ролей токена. loadMe ждёт не дольше 5 с и при недоступном эндпоинте оставляет фолбэк (docs/rbac.md).
const auth = useAuthStore()
auth.init().then(() => auth.loadMe()).catch(() => false).finally(async () => {
  const { router } = await import('./router')
  app.use(router)
  app.mount('#app')
  // Заставка из index.html: после сборки знака (~4 с) фон и слово растворяются, а знак перелетает в знак шапки
  // (data-brand-mark) — плавный переход в интерфейс. Без якоря на странице знак просто растворяется.
  const boot = document.getElementById('boot')
  let skipBoot = false
  try {
    // возврат из Keycloak (вход, выход, проверка сессии) — вторая загрузка той же страницы: заставку не повторяем
    skipBoot = window.sessionStorage.getItem('darumen.boot.skip') === '1'
    window.sessionStorage.removeItem('darumen.boot.skip')
  } catch {
    skipBoot = false
  }
  if (boot && skipBoot) boot.remove()
  else if (boot) {
    const started = Number(boot.dataset.started ?? performance.timeOrigin)
    const wait = Math.max(0, 4000 - (Date.now() - started))
    window.setTimeout(() => {
      const mark = boot.querySelector('svg')
      const anchor = document.querySelector<HTMLElement>('[data-brand-mark]')
      const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (mark && anchor && !reduced) {
        const from = mark.getBoundingClientRect()
        const to = anchor.getBoundingClientRect()
        mark.style.transition = 'transform .7s cubic-bezier(.4,0,.2,1)'
        mark.style.transformOrigin = 'top left'
        mark.style.transform = `translate(${to.left - from.left}px, ${to.top - from.top}px) scale(${to.width / from.width})`
        boot.classList.add('fly')
      }
      boot.classList.add('out')
      window.setTimeout(() => boot.remove(), 750)
    }, wait)
  }
})

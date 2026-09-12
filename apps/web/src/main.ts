import Aura from '@primevue/themes/aura'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import { createApp } from 'vue'
import 'primeicons/primeicons.css'
import 'maplibre-gl/dist/maplibre-gl.css'
import './style.css'
import App from './App.vue'
import { i18n } from './i18n'
import { router } from './router'
import { useAuthStore } from './stores/auth'

const app = createApp(App)
app.use(createPinia())
app.use(PrimeVue, { theme: { preset: Aura, options: { darkModeSelector: '.darumen-dark' } } })
app.use(ToastService)
app.use(i18n)

// Маршрутизатор подключается только после проверки сессии: его первая навигация сразу запускает защиту
// маршрутов, и при переходе по прямой ссылке (например /gov/regions/19) роли уже должны быть известны.
const auth = useAuthStore()
auth
  .init()
  .finally(() => {
    app.use(router)
    app.mount('#app')
    // Переход по роли: вошедший пользователь с общей главной попадает на свой домашний экран.
    router.isReady().then(() => {
      const current = router.currentRoute.value
      if (auth.isAuthenticated && current.path === '/' && !current.query.denied) {
        router.replace(auth.roleHome())
      }
    })
  })

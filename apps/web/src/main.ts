import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import { createApp } from 'vue'
import '@fontsource-variable/onest'
import 'primeicons/primeicons.css'
import 'maplibre-gl/dist/maplibre-gl.css'
import './styles/tokens.css'
import './styles/base.css'
import App from './App.vue'
import { i18n } from './i18n'
import { router } from './router'
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
const auth = useAuthStore()
auth.init().finally(() => {
  app.use(router)
  app.mount('#app')
})

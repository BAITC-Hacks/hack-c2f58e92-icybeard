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
app.use(router)

useAuthStore()
  .init()
  .finally(() => app.mount('#app'))

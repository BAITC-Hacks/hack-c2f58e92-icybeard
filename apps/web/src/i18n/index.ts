import { createI18n } from 'vue-i18n'
import { kk } from './kk'
import { ru } from './ru'

const STORAGE_KEY = 'darumen.locale'

function savedLocale(): 'ru' | 'kk' {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'kk' ? 'kk' : 'ru'
  } catch {
    return 'ru'
  }
}

export const i18n = createI18n({
  legacy: false,
  locale: savedLocale(),
  fallbackLocale: 'ru',
  messages: { ru, kk },
})

export function setLocale(locale: 'ru' | 'kk') {
  i18n.global.locale.value = locale
  try {
    localStorage.setItem(STORAGE_KEY, locale)
  } catch {
    // приватный режим
  }
}

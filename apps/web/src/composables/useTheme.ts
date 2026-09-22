import { computed, ref, watch } from 'vue'

export type ThemeChoice = 'light' | 'dark' | 'system'

const STORAGE_KEY = 'darumen.theme'
const DARK_CLASS = 'darumen-dark'
const CHOICES: ThemeChoice[] = ['light', 'dark', 'system']

function readChoice(): ThemeChoice {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return (CHOICES as string[]).includes(saved ?? '') ? (saved as ThemeChoice) : 'system'
  } catch {
    return 'system'
  }
}

function prefersDark(): boolean {
  return typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(prefers-color-scheme: dark)').matches
}

// одно состояние на приложение: класс на <html> тот же, что ставит bootstrap-скрипт в index.html до загрузки стилей
const choice = ref<ThemeChoice>(readChoice())
const systemDark = ref(prefersDark())
const isDark = computed(() => (choice.value === 'system' ? systemDark.value : choice.value === 'dark'))

if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', (event) => {
    systemDark.value = event.matches
  })
}

watch(
  isDark,
  (dark) => {
    if (typeof document !== 'undefined') document.documentElement.classList.toggle(DARK_CLASS, dark)
  },
  { immediate: true },
)

/** Тема: light | dark | system. Выбор хранится в localStorage (ключ darumen.theme), класс darumen-dark — на <html>. */
export function useTheme() {
  function setTheme(next: ThemeChoice) {
    choice.value = next
    try {
      if (next === 'system') localStorage.removeItem(STORAGE_KEY)
      else localStorage.setItem(STORAGE_KEY, next)
    } catch {
      // приватный режим: выбор живёт до перезагрузки
    }
  }

  function cycle() {
    setTheme(CHOICES[(CHOICES.indexOf(choice.value) + 1) % CHOICES.length] ?? 'system')
  }

  return { theme: choice, isDark, setTheme, cycle }
}

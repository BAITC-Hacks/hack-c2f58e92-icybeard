import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

function memoryStorage(): Storage {
  const data = new Map<string, string>()
  return {
    get length() { return data.size },
    clear: () => data.clear(),
    getItem: (key: string) => data.get(key) ?? null,
    key: (index: number) => [...data.keys()][index] ?? null,
    removeItem: (key: string) => { data.delete(key) },
    setItem: (key: string, value: string) => { data.set(key, value) },
  }
}

function stubMatchMedia(dark: boolean) {
  vi.stubGlobal('matchMedia', (query: string) => ({ matches: dark && query.includes('dark'), media: query, addEventListener: () => {}, removeEventListener: () => {} }))
}

async function load() {
  vi.resetModules()
  return (await import('@/composables/useTheme')).useTheme()
}

describe('useTheme', () => {
  beforeEach(() => {
    vi.stubGlobal('localStorage', memoryStorage())
    document.documentElement.classList.remove('darumen-dark')
  })
  afterEach(() => vi.unstubAllGlobals())

  it('follows the system preference by default and toggles the html class', async () => {
    stubMatchMedia(true)
    const { theme, isDark } = await load()
    expect(theme.value).toBe('system')
    expect(isDark.value).toBe(true)
    expect(document.documentElement.classList.contains('darumen-dark')).toBe(true)
  })

  it('persists an explicit choice and cycles light → dark → system', async () => {
    stubMatchMedia(false)
    const { theme, isDark, setTheme, cycle } = await load()
    setTheme('dark')
    expect(isDark.value).toBe(true)
    expect(localStorage.getItem('darumen.theme')).toBe('dark')
    setTheme('light')
    cycle()
    expect(theme.value).toBe('dark')
    cycle()
    expect(theme.value).toBe('system')
    expect(localStorage.getItem('darumen.theme')).toBeNull()
    expect(isDark.value).toBe(false)
  })

  it('restores the saved choice on load', async () => {
    stubMatchMedia(false)
    localStorage.setItem('darumen.theme', 'dark')
    const { theme, isDark } = await load()
    expect(theme.value).toBe('dark')
    expect(isDark.value).toBe(true)
  })
})

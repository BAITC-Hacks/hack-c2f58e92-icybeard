/** Запомненный выбор пользователя в localStorage (приватный режим — выбор живёт до перезагрузки). */
export const WAIT_PREFS = { region: 'darumen.wait.region', profile: 'darumen.wait.profile' } as const

export function readPref(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

export function writePref(key: string, value: string | null): void {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    // приватный режим
  }
}

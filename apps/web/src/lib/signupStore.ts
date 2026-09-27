/** Заявка на регистрацию организации в этом браузере: statusToken — ключ к статусу без входа (docs/rbac.md),
 * хранится в localStorage по id заявки. Персональных данных сверх адреса почты для подписи экрана здесь нет. */
export interface SavedApplication { id: string; number: string; statusToken: string; email: string; orgName: string; savedAt: string; emailSent?: boolean; resendAfterSeconds?: number }

const PREFIX = 'darumen.signup.'

export function saveApplication(app: Omit<SavedApplication, 'savedAt'>): void {
  try {
    window.localStorage.setItem(PREFIX + app.id, JSON.stringify({ ...app, savedAt: new Date().toISOString() }))
  } catch {
    // без storage статус заявки откроется только по ссылке из письма
  }
}

export function readApplication(id: string): SavedApplication | null {
  try {
    const raw = window.localStorage.getItem(PREFIX + id)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Partial<SavedApplication>
    return parsed.id === id && typeof parsed.statusToken === 'string' ? (parsed as SavedApplication) : null
  } catch {
    return null
  }
}

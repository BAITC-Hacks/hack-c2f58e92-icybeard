/** Категориальные признаки запроса к модели ожидания — часть контракта API/модели (обучена на русских значениях
 * из ИС БГ, см. ml/src/darumen/services/state.py), поэтому значения не переводятся; переводятся только подписи в UI
 * (`doctor.referral.purpose.*`, `doctor.referral.territorial.*`). */
export const PURPOSE_VALUES = ['Оперативное лечение', 'Консервативное лечение', 'Диагностика', 'Реабилитация'] as const
export const TERRITORIAL_VALUES = ['Город', 'Село'] as const
export const FINANCE_DEFAULT = 'Активы Фонда на ОСМС'

export type ReferralPurpose = (typeof PURPOSE_VALUES)[number]
export type TerritorialType = (typeof TERRITORIAL_VALUES)[number]

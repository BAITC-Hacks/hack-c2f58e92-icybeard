import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { date as formatDate, dateTime as formatDateTime, dateTimeShort as formatDateTimeShort, num as formatNum } from '@/lib/format'

/** Форматирование чисел и дат, привязанное к языку интерфейса: шаблоны перерисовываются при смене RU/KK. */
export function useLocaleFormat() {
  const { locale } = useI18n()
  const tag = computed(() => (locale.value === 'kk' ? 'kk-KZ' : 'ru-RU'))
  return {
    tag,
    num: (value: number | null | undefined, digits = 0) => formatNum(value, digits, tag.value),
    date: (iso: string | null | undefined) => formatDate(iso, tag.value),
    dateTime: (iso: string | null | undefined) => formatDateTime(iso, tag.value),
    dateTimeShort: (iso: string | null | undefined) => formatDateTimeShort(iso),
  }
}

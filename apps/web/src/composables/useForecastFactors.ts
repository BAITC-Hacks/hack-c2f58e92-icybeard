import { computed, type Ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Factor } from '@/api/types'

export type ForecastFactor = { name: string; label: string; effect: string; dir: 'plus' | 'minus' | 'zero'; hint: string }

/** «Из чего сложился прогноз» простыми словами (маршрут пациента, ассистент направления): подпись по коду признака
 * (route.factor.<name>), значение из текста модели («очередь …: 133 (+9.0 дн.)» → 133), влияние «+N дн. к ожиданию» /
 * «−N дн. от ожидания» и пояснение, выбранное по знаку вклада (route.factorHint.<name>.plus|minus). */
export function useForecastFactors(source: Ref<Factor[] | null | undefined>, profileName: Ref<string | null | undefined>) {
  const { t, te } = useI18n()
  return computed<ForecastFactor[]>(() =>
    (source.value ?? []).map((f) => {
      const raw = f.text.replace(/\s*\([^)]*\)\s*$/, '')
      const value = raw.includes(': ') ? raw.slice(raw.indexOf(': ') + 2).trim() : ''
      const internal = value === 'True' || value === '1'
      const key = `route.factor.${f.name}`
      let label = te(key) ? t(key) : raw
      if (f.name === 'same_mo') label = t(internal ? 'route.factor.same_mo_yes' : 'route.factor.same_mo_no')
      else if (f.name === 'queue_len' && value) label = t('route.factor.queue_len_n', { n: value })
      else if (f.name === 'profile_code' && profileName.value) label = t('route.factor.profile_named', { name: profileName.value })
      const amount = Math.round(Math.abs(f.contribution))
      const dir: ForecastFactor['dir'] = amount === 0 ? 'zero' : f.contribution > 0 ? 'plus' : 'minus'
      const effect = dir === 'zero' ? t('route.factor.none') : dir === 'plus' ? t('route.factor.plus', { n: amount }) : t('route.factor.minus', { n: amount })
      const hintKey = `route.factorHint.${f.name === 'same_mo' ? (internal ? 'same_mo_yes' : 'same_mo_no') : f.name}.${dir === 'minus' ? 'minus' : 'plus'}`
      return { name: f.name, label, effect, dir, hint: dir !== 'zero' && te(hintKey) ? t(hintKey) : '' }
    }),
  )
}

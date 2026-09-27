<script setup lang="ts">
import Message from 'primevue/message'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { pub } from '@/api/endpoints'
import type { DailyResponse } from '@/api/types'
import LoginPanel from '@/components/app/LoginPanel.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Skeleton from '@/components/ui/Skeleton.vue'
import { num } from '@/lib/format'
import { dateShort } from '@/lib/route'
import { readPref, WAIT_PREFS } from '@/lib/prefs'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'

/** Страница входа — единственная страница без сессии (кроме памятки по QR). Рядом с входом — погода на сегодня и
 * завтра по столице региона с бытовыми советами и новости о здравоохранении; регион — последний выбранный на
 * /wait, иначе г. Алматы. Вошедший попадает сюда только с ?denied (страница не для его роли). */
const DEFAULT_REGION = '75'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
const router = useRouter()
const refdata = useRefdataStore()

const dailyRegion = readPref(WAIT_PREFS.region) ?? DEFAULT_REGION
const daily = ref<DailyResponse | null>(null)
const dailyBusy = ref(true)
const WEATHER_ICON: Record<string, string> = { clear: 'pi pi-sun', cloudy: 'pi pi-cloud', fog: 'pi pi-align-justify', rain: 'pi pi-cloud-download', snow: 'pi pi-asterisk', thunder: 'pi pi-bolt' }
const weatherIcon = (code: string) => WEATHER_ICON[code] ?? 'pi pi-cloud'
const dayLabel = (i: number) => (i === 0 ? t('home.today') : t('home.tomorrow'))

const denied = computed(() => (typeof route.query.denied === 'string' ? route.query.denied : ''))
/** Роли, которым открыта страница из ?denied — подсказка над кнопкой входа. */
const deniedRoles = computed(() => {
  if (!denied.value) return ''
  const roles = router.resolve(denied.value).meta.roles ?? []
  return roles.map((r) => t('decision.role.' + r)).join(' / ')
})
const loginHint = computed(() => {
  if (!denied.value || auth.isAuthenticated) return undefined
  return deniedRoles.value ? t('home.deniedGuestRole', { page: denied.value, roles: deniedRoles.value }) : t('home.deniedGuest', { page: denied.value })
})

onMounted(async () => {
  try {
    const [d] = await Promise.all([pub.daily(dailyRegion), refdata.load()])
    daily.value = d
  } catch {
    daily.value = null // погода, новости и факты — необязательная витрина: без API страница остаётся страницей входа
  } finally {
    dailyBusy.value = false
  }
})
</script>

<template>
  <PageShell :title="t('home.title')" :lead="t('home.lead')">
    <Message v-if="denied && auth.isAuthenticated" severity="warn" :closable="false" data-testid="denied">
      {{ deniedRoles ? t('home.deniedRoleNamed', { page: denied, roles: deniedRoles }) : t('home.deniedRole', { page: denied }) }}
      <RouterLink :to="roleHome(auth.role, auth.region)">{{ t('home.goHome') }}</RouterLink>
    </Message>
    <div class="home-grid">
      <LoginPanel :hint="loginHint" />
      <div class="daily-grid" data-testid="daily">
        <AppCard :title="daily ? t('home.weatherTitle', { city: daily.capital }) : t('home.weatherTitleShort')" data-testid="weather">
          <Skeleton v-if="dailyBusy && !daily" kind="kpi" />
          <template v-else-if="daily?.weather.available">
            <div class="weather-days">
              <div v-for="(d, i) in daily.weather.days.slice(0, 2)" :key="d.date" class="weather-day">
                <div class="muted small">{{ dayLabel(i) }} · {{ dateShort(d.date) }}</div>
                <div class="weather-main"><i :class="weatherIcon(d.code)" aria-hidden="true" /> <span class="tabular">{{ Math.round(d.tMax) }}°</span><span class="muted tabular"> / {{ Math.round(d.tMin) }}°</span></div>
                <div class="muted small">{{ t('home.weather.' + d.code) }} · {{ t('home.precip', { pct: d.precipitationProbability }) }}</div>
              </div>
            </div>
            <ul class="tips">
              <li v-for="tip in daily.tips" :key="tip.code + tip.day"><span class="tip-day">{{ dayLabel(tip.day) }}</span> {{ tip.text }}</li>
            </ul>
            <p class="muted small">{{ t('home.weatherNote', { source: daily.weather.source }) }}</p>
          </template>
          <p v-else class="muted">{{ t('home.weatherUnavailable') }}</p>
        </AppCard>
        <AppCard :title="t('home.newsTitle')" data-testid="news">
          <Skeleton v-if="dailyBusy && !daily" kind="lines" />
          <template v-else-if="daily?.news.available && daily.news.items.length">
            <ul class="news">
              <li v-for="n in daily.news.items" :key="n.url">
                <a :href="n.url" target="_blank" rel="noopener">{{ n.title }}</a>
                <div class="muted small">{{ n.source }}<template v-if="n.publishedAt"> · {{ dateShort(n.publishedAt) }}</template></div>
              </li>
            </ul>
          </template>
          <p v-else class="muted">{{ t('home.newsUnavailable') }}</p>
        </AppCard>
      </div>
    </div>

    <div class="facts-row" data-testid="data-facts">
      <div class="fact"><div class="fact-value tabular">{{ refdata.referralsTotal ? num(Math.round(refdata.referralsTotal / 1000)) : '—' }} {{ t('home.thousand') }}</div><div class="muted small">{{ t('home.factReferrals') }}</div></div>
      <div class="fact"><div class="fact-value tabular">{{ refdata.regionsCount || '—' }}</div><div class="muted small">{{ t('home.factRegions') }}</div></div>
      <div class="fact"><div class="fact-value">{{ t('home.factPeriodValue') }}</div><div class="muted small">{{ t('home.factPeriod') }}</div></div>
      <p class="muted small provenance">{{ t('home.factsNote') }}</p>
    </div>
  </PageShell>
</template>

<style scoped>
.home-grid { display: grid; grid-template-columns: minmax(280px, 380px) 1fr; gap: var(--dm-space-4); align-items: start; }
.daily-grid { display: grid; gap: var(--dm-space-4); }
.weather-days { display: grid; grid-template-columns: 1fr 1fr; gap: var(--dm-space-3); }
.weather-day { border: 1px solid var(--dm-hairline); border-radius: var(--dm-radius-md); padding: var(--dm-space-3); display: grid; gap: 4px; }
.weather-main { font-size: 1.6rem; font-weight: 600; display: flex; align-items: center; gap: 8px; }
.weather-main i { color: var(--dm-accent); font-size: 1.3rem; }
.tips { margin: var(--dm-space-3) 0 var(--dm-space-2); padding-left: 0; list-style: none; display: grid; gap: 6px; }
.tip-day { display: inline-block; font-size: 11.5px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--dm-muted); margin-right: 6px; }
.news { margin: 0; padding-left: 0; list-style: none; display: grid; gap: var(--dm-space-3); }
.news a { color: var(--dm-ink); text-decoration: none; }
.news a:hover { color: var(--dm-accent); }
.facts-row { display: flex; flex-wrap: wrap; gap: var(--dm-space-5); margin-top: var(--dm-space-5); padding-top: var(--dm-space-4); border-top: 1px solid var(--dm-hairline); align-items: flex-start; }
.fact-value { font-size: 1.4rem; font-weight: 600; }
.provenance { flex-basis: 100%; margin: 0; }
@media (max-width: 760px) { .home-grid { grid-template-columns: 1fr; } }
</style>

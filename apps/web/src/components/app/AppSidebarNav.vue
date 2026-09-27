<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import BrandMark from '@/components/app/BrandMark.vue'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'
import { NAV_GROUPS, type NavGroup } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'
import { shortOrgName } from '@/lib/format'
import { useRefdataStore } from '@/stores/refdata'

/** Содержимое боковой навигации персонала (W-Gov): знак + «Darumen Health», группы с label uppercase, пункты 40 px
 * radius 999 (активный — soft-фон и коралловая точка, остальные с отступом 28), внизу «пользователь · ведомство»,
 * пилюля RU/KK, тема и «Выйти». Пункты — из meta маршрутов (group / groupByRole / navRoles / nav / navTitle);
 * маршруты с параметрами добавляются здесь: «Регион» (свой или последний открытый) и кабинет организации главврача. */
const emit = defineEmits<{ navigate: [] }>()
const { t } = useI18n()
const auth = useAuthStore()
const refdata = useRefdataStore()
const router = useRouter()
const route = useRoute()

interface NavItem { to: string; label: string; icon: string; nav: number }
interface NavGroupItems { group: NavGroup; label: string; items: NavItem[] }

/** Последний открытый регион (страницы региона и организации) — цель пункта «Регион» у регулятора. */
const lastRegion = computed(() => {
  const fromRoute = route.name === 'region' ? String(route.params.kato ?? '') : route.name === 'organization' || route.name === 'organization-referrals' ? String(route.query.kato ?? '') : ''
  return fromRoute || auth.region || null
})

const groups = computed<NavGroupItems[]>(() => {
  const role = auth.role
  const routes = router
    .getRoutes()
    .filter((r) => r.meta.nav !== undefined && r.meta.title && r.meta.group && !r.path.includes(':'))
    .filter((r) => (!r.meta.roles || auth.hasRole(...r.meta.roles)) && (!r.meta.navRoles || (role !== null && (r.meta.navRoles.includes(role) || role === 'admin'))))
  const byGroup = new Map<NavGroup, NavItem[]>()
  const push = (group: NavGroup, item: NavItem) => byGroup.set(group, [...(byGroup.get(group) ?? []), item])
  for (const r of routes) {
    const group = (role && r.meta.groupByRole?.[role]) ?? r.meta.group!
    push(group, { to: r.path, label: t(r.meta.navTitle ?? r.meta.title ?? ''), icon: r.meta.icon ?? 'pi pi-circle', nav: r.meta.nav ?? 0 })
  }
  // главврач: кабинет своей организации («Больница»), без mo_code — свой регион
  if (role === 'chief') {
    if (auth.moCode) {
      push('hospital', { to: `/gov/organizations/${auth.moCode}`, label: t('nav.short.orgOverview'), icon: 'pi pi-building', nav: 10 })
      push('hospital', { to: `/gov/organizations/${auth.moCode}/referrals`, label: t('nav.short.orgReferrals'), icon: 'pi pi-inbox', nav: 20 })
    } else if (auth.region) {
      push('region', { to: `/gov/regions/${auth.region}`, label: t('nav.short.myRegion'), icon: 'pi pi-building', nav: 10 })
    }
  }
  // регулятор: «Регион» вторым пунктом министерства — последний открытый регион
  if ((role === 'regulator' || role === 'admin') && lastRegion.value) {
    push('ministry', { to: `/gov/regions/${lastRegion.value}`, label: t('nav.short.region'), icon: 'pi pi-building', nav: 20 })
  }
  return NAV_GROUPS.map((group) => ({ group, label: t(`nav.group.${group}`), items: (byGroup.get(group) ?? []).sort((a, b) => a.nav - b.nav) })).filter((g) => g.items.length > 0)
})

/** «пользователь · ведомство»: regulator1 · Минздрав РК, doctor1 · врач ПМСП, org028B · НИИ глазных болезней. */
const affiliation = computed(() => {
  if (auth.role === 'chief') return auth.moCode ? shortOrgName(refdata.organizationName(auth.moCode)) : refdata.regionName(auth.region)
  return auth.role ? t('nav.affiliation.' + auth.role) : ''
})

/** Активен пункт с точным путём; вложенный путь подсвечивает родителя, только если точного пункта нет
 * (кабинет организации против её «Направлений и отказов»). */
function isActive(to: string): boolean {
  if (route.path === to) return true
  const exact = groups.value.some((g) => g.items.some((i) => i.to === route.path))
  return !exact && to !== '/gov' && route.path.startsWith(to + '/')
}

async function resolveOrganization() {
  if (auth.role === 'chief' && auth.moCode) {
    try {
      await refdata.resolveOrganizations([auth.moCode])
    } catch {
      // без справочника в подписи остаётся код организации
    }
  }
}
onMounted(resolveOrganization)
watch(() => auth.moCode, resolveOrganization)
</script>

<template>
  <div class="sidenav">
    <RouterLink class="brand" to="/" title="Darumen Health" @click="emit('navigate')">
      <BrandMark :size="28" /><span class="label">Darumen Health</span>
    </RouterLink>
    <nav class="groups" :aria-label="t('shell.menu')">
      <div v-for="g in groups" :key="g.group" class="group">
        <div class="group-title eyebrow">{{ g.label }}</div>
        <RouterLink v-for="item in g.items" :key="item.to" :to="item.to" class="item" :class="{ active: isActive(item.to) }" :title="item.label" @click="emit('navigate')">
          <span class="dot" aria-hidden="true" /><i :class="item.icon" class="icon" aria-hidden="true" /><span class="label">{{ item.label }}</span>
        </RouterLink>
      </div>
    </nav>
    <div class="foot">
      <div class="user" :title="`${auth.actor} · ${affiliation}`" data-testid="user-chip">
        <i class="pi pi-user icon" aria-hidden="true" /><span class="label">{{ auth.actor }} · {{ affiliation }}</span>
      </div>
      <div class="controls">
        <span class="wide"><LocaleSwitch surface="soft" /></span>
        <span class="narrow"><LocaleSwitch mode="toggle" /></span>
        <ThemeToggle />
        <button type="button" class="logout" :title="t('auth.logout')" data-testid="logout" @click="auth.logout()">
          <i class="pi pi-sign-out icon" aria-hidden="true" /><span class="label">{{ t('auth.logout') }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.sidenav { display: flex; flex-direction: column; height: 100%; min-height: 0; padding: 24px 16px 20px; gap: 4px; box-sizing: border-box; }
.brand { display: flex; align-items: center; gap: 10px; padding: 0 8px 20px; text-decoration: none; color: var(--dm-ink); font-weight: 600; font-size: 16px; letter-spacing: -0.02em; }
.groups { flex: 1; overflow: auto; display: flex; flex-direction: column; gap: 4px; min-height: 0; }
.group { display: flex; flex-direction: column; gap: 4px; }
.group + .group { margin-top: 12px; }
.group-title { padding: 8px 12px 6px; }
.item { display: flex; align-items: center; gap: 10px; height: 40px; padding: 0 12px 0 28px; border-radius: var(--dm-radius-pill); text-decoration: none; color: var(--dm-muted); font-size: var(--dm-text-md); font-weight: 500; white-space: nowrap; overflow: hidden; box-sizing: border-box; }
.item .icon { display: none; }
.item .dot { display: none; width: 6px; height: 6px; border-radius: 50%; background: var(--dm-accent); flex: none; }
.item:hover { background: var(--dm-surface-2); color: var(--dm-ink); }
.item.active { background: var(--dm-surface-2); color: var(--dm-ink); padding-left: 12px; }
.item.active .dot { display: block; }
.foot { display: flex; flex-direction: column; gap: 10px; padding: 12px 12px 0; font-size: 13px; color: var(--dm-muted); }
.user { display: flex; align-items: center; gap: 8px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.user .icon { display: none; }
.controls { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.narrow { display: none; }
.logout { border: 0; background: none; padding: 0; font: inherit; font-size: 13px; color: var(--dm-muted); cursor: pointer; display: inline-flex; align-items: center; gap: 6px; }
.logout:hover { color: var(--dm-danger); }
.logout .icon { display: none; }

/* до 1100 px — только иконки: подписи скрыты, всё центрируется */
@media (max-width: 1100px) and (min-width: 641px) {
  .sidenav { padding-inline: 6px; }
  .label, .group-title { display: none; }
  .brand, .item, .user { justify-content: center; padding-inline: 0; }
  .item .icon, .user .icon, .logout .icon { display: inline-block; }
  .item.active { padding-left: 0; }
  .item.active .dot { display: none; }
  .item.active .icon { color: var(--dm-accent); }
  .controls { flex-direction: column; align-items: center; }
  .wide { display: none; }
  .narrow { display: inline-flex; }
  .foot { padding-inline: 0; align-items: center; }
}
</style>

<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import BrandMark from '@/components/app/BrandMark.vue'
import { shortOrgName } from '@/lib/format'
import { sidebarNav } from '@/lib/nav'
import { useAuthStore } from '@/stores/auth'
import { useRefdataStore } from '@/stores/refdata'
import LocaleSwitch from './LocaleSwitch.vue'
import NotificationBell from './NotificationBell.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Содержимое боковой навигации персонала: знак + «Darumen Health», группы с label uppercase, пункты 40 px radius 999
 * (активный — selected #E7ECFF, фиолетовая точка и ink-текст, остальные с отступом 28), внизу «пользователь ·
 * организация/роль» (ссылка на профиль), пилюля RU/KK, тема и «Выйти». Меню строится только из разрешений (lib/nav.ts):
 * пункты маршрутов с meta.nav плюс кабинет своей организации и «Регион». Группа «Аккаунт» — у всех вошедших. */
const emit = defineEmits<{ navigate: [] }>()
const { t } = useI18n()
const auth = useAuthStore()
const refdata = useRefdataStore()
const router = useRouter()
const route = useRoute()

/** Последний открытый регион (страницы региона и организации) — цель пункта «Регион»; иначе свой регион. */
const lastRegion = computed(() => {
  const fromRoute = route.name === 'region' ? String(route.params.kato ?? '') : route.name === 'organization' || route.name === 'organization-referrals' ? String(route.query.kato ?? '') : ''
  return fromRoute || auth.region || null
})

const groups = computed(() =>
  sidebarNav(router.getRoutes(), { can: auth.can, moCode: auth.moCode, region: lastRegion.value }).map((section) => ({
    ...section,
    label: t(`nav.group.${section.group}`),
    items: section.items.map((item) => ({ ...item, label: t(item.labelKey) })),
  })),
)

/** «пользователь · организация» у ролей с организацией, иначе «пользователь · роль». */
const affiliation = computed(() => {
  if (auth.moCode && (auth.role === 'org_admin' || auth.role === 'doctor')) return shortOrgName(refdata.organizationName(auth.moCode))
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
  if (!auth.moCode) return
  try {
    await refdata.resolveOrganizations([auth.moCode])
  } catch {
    // без справочника в подписи остаётся код организации
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
      <div v-for="g in groups" :key="g.group" class="group" :data-testid="`nav-group-${g.group}`">
        <div class="group-title eyebrow">{{ g.label }}</div>
        <RouterLink v-for="item in g.items" :key="item.to" :to="item.to" class="item" :class="{ active: isActive(item.to) }" :title="item.label" @click="emit('navigate')">
          <span class="dot" aria-hidden="true" /><i :class="item.icon" class="icon" aria-hidden="true" /><span class="label">{{ item.label }}</span>
        </RouterLink>
      </div>
    </nav>
    <div class="foot">
      <RouterLink class="user" to="/account/profile" :title="`${auth.actor} · ${affiliation}`" data-testid="user-chip" @click="emit('navigate')">
        <i class="pi pi-user icon" aria-hidden="true" /><span class="label">{{ auth.actor }} · {{ affiliation }}</span>
      </RouterLink>
      <div class="controls">
        <NotificationBell />
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
.item { display: flex; align-items: center; gap: 10px; height: 40px; padding: 0 12px 0 28px; border-radius: var(--dm-radius-pill); text-decoration: none; color: var(--dm-muted); font-size: var(--dm-text-md); font-weight: 500; white-space: nowrap; overflow: hidden; box-sizing: border-box; flex: none; }
.item .icon { display: none; }
.item .dot { display: none; width: 6px; height: 6px; border-radius: 50%; background: var(--dm-accent); flex: none; }
.item:hover { background: var(--dm-bg); color: var(--dm-ink); }
.item.active { background: var(--dm-accent-soft); color: var(--dm-ink); padding-left: 12px; }
.item.active .dot { display: block; }
.foot { display: flex; flex-direction: column; gap: 10px; padding: 12px 12px 0; font-size: 13px; color: var(--dm-muted); }
.user { display: flex; align-items: center; gap: 8px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; color: var(--dm-muted); text-decoration: none; }
.user:hover { color: var(--dm-accent-hover); }
.user .label { overflow: hidden; text-overflow: ellipsis; }
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

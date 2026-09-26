<script setup lang="ts">
import BrandMark from '@/components/app/BrandMark.vue'
import Button from 'primevue/button'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'
import { NAV_GROUPS, type NavGroup } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'

/** Содержимое боковой навигации персонала: группы пунктов из meta маршрутов (group/nav/navTitle/icon) по ролям,
 * внизу — пользователь · роль, язык, тема, «Выйти». Одно и то же наполнение живёт в aside и в drawer телефона. */
const emit = defineEmits<{ navigate: [] }>()
const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()

interface NavItem { to: string; label: string; icon: string }
interface NavGroupItems { group: NavGroup; label: string; items: NavItem[] }

const groups = computed<NavGroupItems[]>(() => {
  const routes = router
    .getRoutes()
    .filter((r) => r.meta.nav !== undefined && r.meta.title && r.meta.group && NAV_GROUPS.includes(r.meta.group) && (!r.meta.roles || auth.hasRole(...r.meta.roles)))
  return NAV_GROUPS.map((group) => {
    const items: NavItem[] = routes
      .filter((r) => r.meta.group === group)
      .sort((a, b) => (a.meta.nav ?? 0) - (b.meta.nav ?? 0))
      .map((r) => ({ to: r.path, label: t(r.meta.navTitle ?? r.meta.title ?? ''), icon: r.meta.icon ?? 'pi pi-circle' }))
    // главврачу — свой регион первым пунктом группы «Регион» (домашний экран роли)
    if (group === 'region' && auth.role === 'chief' && auth.region) {
      items.unshift({ to: `/gov/regions/${auth.region}`, label: t('nav.short.myRegion'), icon: 'pi pi-building' })
    }
    return { group, label: t(`nav.group.${group}`), items }
  }).filter((g) => g.items.length > 0)
})

const roleLabel = computed(() => (auth.role ? t('decision.role.' + auth.role) : ''))
</script>

<template>
  <div class="sidenav">
    <RouterLink class="brand" to="/" title="Darumen Health" @click="emit('navigate')">
      <BrandMark :size="28" /><span class="label">Darumen Health</span>
    </RouterLink>
    <nav class="groups" :aria-label="t('shell.menu')">
      <div v-for="g in groups" :key="g.group" class="group">
        <div class="group-title label">{{ g.label }}</div>
        <RouterLink v-for="item in g.items" :key="item.to" :to="item.to" class="item" :title="item.label" active-class="active" @click="emit('navigate')">
          <i :class="item.icon" aria-hidden="true" /><span class="label">{{ item.label }}</span>
        </RouterLink>
      </div>
    </nav>
    <div class="foot">
      <div class="user" :title="`${auth.actor} · ${roleLabel}`" data-testid="user-chip">
        <i class="pi pi-user" aria-hidden="true" /><span class="label">{{ auth.actor }} <span class="muted">· {{ roleLabel }}</span></span>
      </div>
      <div class="controls">
        <span class="wide"><LocaleSwitch /></span>
        <span class="narrow"><LocaleSwitch mode="toggle" /></span>
        <ThemeToggle />
      </div>
      <Button :label="t('auth.logout')" :title="t('auth.logout')" icon="pi pi-sign-out" size="small" severity="secondary" text class="logout" data-testid="logout" @click="auth.logout()" />
    </div>
  </div>
</template>

<style scoped>
.sidenav { display: flex; flex-direction: column; height: 100%; min-height: 0; padding: var(--dm-space-3) var(--dm-space-2); gap: var(--dm-space-3); }
.brand { display: flex; align-items: center; gap: 10px; padding: 6px 8px; text-decoration: none; color: var(--dm-ink); font-weight: 700; font-size: 1.05rem; }
.brand-mark { width: 28px; height: 28px; flex: none; border-radius: 8px; background: var(--dm-accent); color: #fff; display: grid; place-items: center; font-size: 15px; }
.groups { flex: 1; overflow: auto; display: flex; flex-direction: column; gap: var(--dm-space-3); min-height: 0; }
.group-title { font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--dm-muted); padding: 4px 8px 2px; }
.item { display: flex; align-items: center; gap: 10px; padding: 8px; border-radius: var(--dm-radius-sm); text-decoration: none; color: var(--dm-ink); font-size: 0.95rem; white-space: nowrap; overflow: hidden; }
.item i { width: 18px; text-align: center; color: var(--dm-muted); flex: none; }
.item:hover { background: var(--dm-surface-2); }
.item.active { background: var(--dm-accent-soft); color: var(--dm-accent); }
.item.active i { color: var(--dm-accent); }
.foot { border-top: 1px solid var(--dm-hairline); padding-top: var(--dm-space-3); display: flex; flex-direction: column; gap: 8px; }
.user { display: flex; align-items: center; gap: 10px; padding: 0 8px; font-size: 0.9rem; overflow: hidden; white-space: nowrap; }
.user i { color: var(--dm-muted); flex: none; }
.controls { display: flex; align-items: center; gap: 6px; padding: 0 4px; }
.narrow { display: none; }
.logout { justify-content: flex-start; }

/* до 1100 px — только иконки: подписи скрыты, всё центрируется */
@media (max-width: 1100px) and (min-width: 641px) {
  .sidenav { padding-inline: 6px; }
  .label { display: none; }
  .brand, .item, .user { justify-content: center; padding-inline: 0; }
  .controls { flex-direction: column; align-items: center; }
  .wide { display: none; }
  .narrow { display: inline-flex; }
  .logout :deep(.p-button-label) { display: none; }
  .logout { justify-content: center; }
}
</style>

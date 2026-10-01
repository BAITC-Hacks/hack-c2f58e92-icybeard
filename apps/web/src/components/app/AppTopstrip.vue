<script setup lang="ts">
import Menu from 'primevue/menu'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { accountNav } from '@/lib/nav'
import { useAuthStore } from '@/stores/auth'
import LocaleSwitch from './LocaleSwitch.vue'
import NotificationBell from './NotificationBell.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Верхняя полоса кабинета (components.md): высота 60, белая, разделитель снизу; справа — колокольчик,
 * локаль, кнопка темы и меню пользователя — то же, что у гражданина в шапке: «Первый вход», профиль,
 * безопасность, уведомления, данные и согласия, «Выйти». Отдельной группы «Аккаунт» в сайдбаре и отдельной
 * кнопки выхода на десктопе нет. На телефоне полосу заменяет mobilebar с drawer-версией сайдбара. */
const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const menu = ref<InstanceType<typeof Menu> | null>(null)
const accountItems = computed(() => [
  ...accountNav(router.getRoutes()).map((item) => ({ label: t(item.labelKey), icon: item.icon, command: () => router.push(item.to) })),
  { separator: true },
  { label: t('auth.logout'), icon: 'pi pi-sign-out', command: () => auth.logout() },
])
</script>

<template>
  <header class="topstrip">
    <span class="spacer" />
    <NotificationBell />
    <LocaleSwitch surface="soft" />
    <ThemeToggle />
    <button type="button" class="user-chip" aria-haspopup="true" :aria-label="t('account.menu')" data-testid="user-chip" @click="menu?.toggle($event)">
      <i class="pi pi-user" aria-hidden="true" /><span class="user-name">{{ auth.actor }}</span><i class="pi pi-angle-down" aria-hidden="true" />
    </button>
    <Menu ref="menu" :model="accountItems" popup data-testid="user-menu" />
  </header>
</template>

<style scoped>
.topstrip { height: var(--topstrip-h); flex: none; display: flex; align-items: center; gap: 10px; padding: 0 28px; background: var(--surface); border-bottom: 1px solid var(--border); box-sizing: border-box; }
.spacer { flex: 1; }
.user-chip { display: inline-flex; align-items: center; gap: 8px; height: 36px; padding: 0 14px; border: 0; border-radius: var(--radius-pill); background: var(--surface-muted); color: var(--text); font: inherit; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); cursor: pointer; max-width: 260px; }
.user-chip:hover { background: var(--accent-soft); }
.user-chip .pi { font-size: 14px; color: var(--text-secondary); }
.user-name { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
@media (max-width: 640px) { .topstrip { display: none; } }
</style>

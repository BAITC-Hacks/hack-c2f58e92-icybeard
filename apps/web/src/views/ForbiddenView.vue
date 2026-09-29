<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import StateNoAccess from '@/components/states/StateNoAccess.vue'
import { useAuthStore } from '@/stores/auth'

/** «Нет доступа к разделу» (W-Auth-Blocked): сюда ведёт защита маршрутов, когда у вошедшего нет разрешения раздела;
 * в адресе — исходный раздел (?from) и код разрешения (?permission) для запроса доступа. */
const { t } = useI18n()
const route = useRoute()
const auth = useAuthStore()
const from = computed(() => (typeof route.query.from === 'string' && route.query.from.startsWith('/') ? route.query.from : '/'))
const permission = computed(() => (typeof route.query.permission === 'string' ? route.query.permission : null))
</script>

<template>
  <main class="page forbidden">
    <section class="card forbidden-card">
      <StateNoAccess :permission="permission" :path="from" tone="danger" />
      <RouterLink class="home-link" :to="auth.roleHome()">{{ t('access.goHome') }}</RouterLink>
    </section>
  </main>
</template>

<style scoped>
/* public-forbidden-new: серый фон, белая карточка 440–460 radius 20, замок в danger-круге, «← На главную» 12.5/700 */
.forbidden { align-items: center; justify-content: center; }
.forbidden-card { width: min(460px, 100%); border-radius: var(--radius-card-lg); display: flex; flex-direction: column; align-items: center; padding: 28px 28px 32px; }
.home-link { margin-top: -4px; display: inline-flex; align-items: center; gap: 6px; font-size: var(--fs-base-sm); font-weight: var(--fw-bold); color: var(--accent-strong); text-decoration: none; }
.home-link::before { content: '←'; }
.home-link:hover { color: var(--accent); }
</style>

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
      <StateNoAccess :permission="permission" :path="from" />
      <RouterLink class="link-arrow small home-link" :to="auth.roleHome()">{{ t('access.goHome') }}</RouterLink>
    </section>
  </main>
</template>

<style scoped>
.forbidden { align-items: center; justify-content: center; }
.forbidden-card { width: min(560px, 100%); display: flex; flex-direction: column; align-items: center; padding-bottom: 32px; }
.home-link { margin-top: -8px; }
</style>

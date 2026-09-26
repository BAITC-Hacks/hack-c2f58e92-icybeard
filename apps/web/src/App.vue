<script setup lang="ts">
import Toast from 'primevue/toast'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import AppSidebar from '@/components/app/AppSidebar.vue'
import AppTopbar from '@/components/app/AppTopbar.vue'
import { usesSidebar } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'

/** Каркас: персоналу (doctor, chief, regulator, steward, admin) — боковая навигация; гражданину и гостю — верхняя
 * полоса и макет 960 px; страницы с meta.bare (памятка) — без навигации. */
const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
const bare = computed(() => route.meta.bare === true)
const sidebar = computed(() => !bare.value && usesSidebar(auth.role))
</script>

<template>
  <div class="shell" :class="{ 'shell--side': sidebar, 'shell--bare': bare }">
    <AppSidebar v-if="sidebar" />
    <AppTopbar v-else-if="!bare" />
    <div class="shell-main">
      <Toast />
      <RouterView />
      <footer v-if="!bare" class="footer">{{ t('app.footer') }}</footer>
    </div>
  </div>
</template>

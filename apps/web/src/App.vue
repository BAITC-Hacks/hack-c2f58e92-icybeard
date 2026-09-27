<script setup lang="ts">
import Toast from 'primevue/toast'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import AppSidebar from '@/components/app/AppSidebar.vue'
import AppTopbar from '@/components/app/AppTopbar.vue'
import PublicBar from '@/components/app/PublicBar.vue'
import { useAuthStore } from '@/stores/auth'

/** Каркас: у кого есть разрешения персонала — боковая навигация; гражданину и странице входа — верхняя полоса;
 * публичные страницы (регистрация организации, приглашение) — знак и RU/KK; памятка (meta.bare) — без навигации. */
const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
const bare = computed(() => route.meta.bare === true)
const isPublic = computed(() => route.meta.public === true)
const sidebar = computed(() => !bare.value && !isPublic.value && auth.sidebar)
</script>

<template>
  <div class="shell" :class="{ 'shell--side': sidebar, 'shell--bare': bare, 'shell--public': isPublic }">
    <AppSidebar v-if="sidebar" />
    <PublicBar v-else-if="isPublic" />
    <AppTopbar v-else-if="!bare" />
    <div class="shell-main">
      <Toast />
      <RouterView />
      <footer v-if="isPublic" class="footer">{{ t('auth.syntheticNote') }}</footer>
      <footer v-else-if="!bare" class="footer">{{ t('app.footer') }}</footer>
    </div>
  </div>
</template>

<script setup lang="ts">
import Toast from 'primevue/toast'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import AppSidebar from '@/components/app/AppSidebar.vue'
import AppTopbar from '@/components/app/AppTopbar.vue'
import AppTopstrip from '@/components/app/AppTopstrip.vue'
import EmailOutageBanner from '@/components/app/EmailOutageBanner.vue'
import PublicBar from '@/components/app/PublicBar.vue'
import { useAuthStore } from '@/stores/auth'

/** Каркас: у кого есть разрешения персонала — боковая навигация; гражданину и странице входа — верхняя полоса;
 * публичные страницы (регистрация организации, приглашение) — знак и RU/KK; памятка (meta.bare) — без навигации.
 * Вошедшему пользователю над страницей — баннер «Почтовый сервер недоступен», пока почта не работает. */
const { t, locale } = useI18n()
const auth = useAuthStore()
const route = useRoute()
const bare = computed(() => route.meta.bare === true)
const isPublic = computed(() => route.meta.public === true)
const sidebar = computed(() => !bare.value && !isPublic.value && auth.sidebar)
const signedInShell = computed(() => !bare.value && !isPublic.value && auth.isAuthenticated)
/** Голубой градиент --bg-hero-gradient — только главная без входа (home-prop-5); вошедших защита маршрутов сюда не пускает. */
const hero = computed(() => route.name === 'home' && !auth.isAuthenticated)
</script>

<template>
  <div class="shell" :class="{ 'shell--side': sidebar, 'shell--bare': bare, 'shell--public': isPublic, 'shell--hero': hero }">
    <AppSidebar v-if="sidebar" />
    <PublicBar v-else-if="isPublic" />
    <AppTopbar v-else-if="!bare" />
    <div class="shell-main">
      <AppTopstrip v-if="sidebar" />
      <Toast />
      <EmailOutageBanner v-if="signedInShell" />
      <!-- тексты с сервера (этапы маршрута, нормативы, объяснения) приходят на языке запроса: при смене RU/KK страница
           пересоздаётся и заново загружает данные на новом языке -->
      <RouterView v-slot="{ Component }"><component :is="Component" :key="locale" /></RouterView>
      <footer v-if="isPublic" class="footer">{{ t('auth.syntheticNote') }}</footer>
      <footer v-else-if="!bare" class="footer">{{ t('app.footer') }}</footer>
    </div>
  </div>
</template>

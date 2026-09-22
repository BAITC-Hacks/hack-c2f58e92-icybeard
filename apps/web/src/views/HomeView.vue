<script setup lang="ts">
import Message from 'primevue/message'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import LoginPanel from '@/components/app/LoginPanel.vue'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
</script>

<template>
  <main class="page">
    <h1>{{ t('home.title') }}</h1>
    <p class="lead">{{ t('home.lead') }}</p>
    <Message v-if="route.query.denied" severity="warn" :closable="false" data-testid="denied">
      <template v-if="auth.isAuthenticated">
        {{ t('home.deniedRole', { page: route.query.denied }) }}
        <RouterLink :to="roleHome(auth.role, auth.region)">{{ t('home.goHome') }}</RouterLink>
      </template>
      <template v-else>{{ t('home.deniedGuest', { page: route.query.denied }) }}</template>
    </Message>
    <div class="grid cols-2" style="margin-top: 16px">
      <LoginPanel v-if="!auth.isAuthenticated" />
      <RouterLink v-else class="card" :to="roleHome(auth.role, auth.region)" data-testid="continue">
        <h2>{{ t('home.continueTitle') }}</h2>
        <p class="muted">{{ auth.actor }}<template v-if="auth.role"> · {{ t('decision.role.' + auth.role) }}</template></p>
      </RouterLink>
      <section class="card">
        <h2>{{ t('home.publicTitle') }}</h2>
        <p><RouterLink to="/wait">{{ t('nav.wait') }}</RouterLink> — {{ t('home.citizen') }}</p>
        <p><RouterLink to="/medicines">{{ t('nav.medicines') }}</RouterLink> — {{ t('home.medicines') }}</p>
      </section>
    </div>
  </main>
</template>

<style scoped>
a.card { text-decoration: none; color: inherit; }
a.card:hover { border-color: var(--darumen-accent); }
</style>

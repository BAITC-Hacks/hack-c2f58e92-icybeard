<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import Message from 'primevue/message'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
</script>

<template>
  <main class="page">
    <h1>{{ t('home.title') }}</h1>
    <p class="lead">{{ t('home.lead') }}</p>
    <Message v-if="route.query.denied" severity="warn" :closable="false">
      {{ t(auth.mode === 'keycloak' ? 'home.deniedKeycloak' : 'home.denied', { page: route.query.denied }) }}
    </Message>
    <Message v-if="auth.mode === 'keycloak' && !auth.isAuthenticated" severity="info" :closable="false">
      {{ t('home.keycloakIntro') }} <code>darumen</code>: regulator1 ({{ t('home.roleRegulator') }}), chief1 ({{ t('home.roleChief') }}), doctor1 ({{ t('home.roleDoctor') }}),
      steward1 ({{ t('home.roleSteward') }}), citizen1 ({{ t('home.roleCitizen') }}), admin1 ({{ t('home.roleAll') }}).
      {{ t('home.publicPages') }}
    </Message>
    <Message v-else-if="auth.mode === 'headers' && !auth.isAuthenticated" severity="info" :closable="false">
      {{ t('home.demoModeHint') }}
    </Message>
    <div class="grid cols-2" style="margin-top: 16px">
      <RouterLink class="card" to="/gov"><h2>Darumen Gov</h2><p>{{ t('home.gov') }}</p></RouterLink>
      <RouterLink class="card" to="/doctor/referral"><h2>Darumen Care · {{ t('home.roleDoctor') }}</h2><p>{{ t('home.doctor') }}</p></RouterLink>
      <RouterLink class="card" to="/wait"><h2>Darumen Care · {{ t('home.roleCitizen') }}</h2><p>{{ t('home.citizen') }}</p></RouterLink>
      <RouterLink class="card" to="/steward"><h2>Data Intake Fabric</h2><p>{{ t('home.steward') }}</p></RouterLink>
    </div>
  </main>
</template>

<style scoped>
a.card { text-decoration: none; color: inherit; }
a.card:hover { border-color: var(--darumen-accent); }
</style>

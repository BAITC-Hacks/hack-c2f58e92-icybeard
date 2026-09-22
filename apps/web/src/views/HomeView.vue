<script setup lang="ts">
import Message from 'primevue/message'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import LoginPanel from '@/components/app/LoginPanel.vue'
import AppCard from '@/components/ui/AppCard.vue'
import PageShell from '@/components/ui/PageShell.vue'
import Section from '@/components/ui/Section.vue'
import { roleHome } from '@/router/roles'
import { useAuthStore } from '@/stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const route = useRoute()
</script>

<template>
  <PageShell :title="t('home.title')" :lead="t('home.lead')">
    <Message v-if="route.query.denied" severity="warn" :closable="false" data-testid="denied">
      <template v-if="auth.isAuthenticated">
        {{ t('home.deniedRole', { page: route.query.denied }) }}
        <RouterLink :to="roleHome(auth.role, auth.region)">{{ t('home.goHome') }}</RouterLink>
      </template>
      <template v-else>{{ t('home.deniedGuest', { page: route.query.denied }) }}</template>
    </Message>
    <Section :cols="2">
      <LoginPanel v-if="!auth.isAuthenticated" />
      <AppCard v-else :title="t('home.continueTitle')" :to="roleHome(auth.role, auth.region)" data-testid="continue">
        <p class="muted">{{ auth.actor }}<template v-if="auth.role"> · {{ t('decision.role.' + auth.role) }}</template></p>
      </AppCard>
      <AppCard :title="t('home.publicTitle')">
        <p><RouterLink to="/wait">{{ t('nav.wait') }}</RouterLink> — {{ t('home.citizen') }}</p>
        <p><RouterLink to="/medicines">{{ t('nav.medicines') }}</RouterLink> — {{ t('home.medicines') }}</p>
      </AppCard>
    </Section>
  </PageShell>
</template>

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
      Для страницы {{ route.query.denied }} нужна другая роль. Выберите роль в шапке{{ auth.mode === 'keycloak' ? ' или войдите' : '' }}.
    </Message>
    <Message v-if="auth.mode === 'keycloak' && !auth.isAuthenticated" severity="info" :closable="false">
      Вход через Keycloak (кнопка «Войти» в шапке). Демо-пользователи с паролем <code>darumen</code>: regulator1 (регулятор), chief1 (главврач), doctor1 (врач), steward1 (стюард), citizen1 (гражданин), admin1 (всё).
      Публичные страницы «Ожидание для граждан» и «Проверка рецепта» открываются без входа.
    </Message>
    <Message v-else-if="auth.mode === 'headers' && !auth.isAuthenticated" severity="info" :closable="false">
      Демо-режим: выберите роль в шапке справа, вход не нужен.
    </Message>
    <div class="grid cols-2" style="margin-top: 16px">
      <RouterLink class="card" to="/gov"><h2>Darumen Gov</h2><p>{{ t('home.gov') }}</p></RouterLink>
      <RouterLink class="card" to="/doctor/referral"><h2>Darumen Care · врач</h2><p>{{ t('home.doctor') }}</p></RouterLink>
      <RouterLink class="card" to="/wait"><h2>Darumen Care · гражданин</h2><p>{{ t('home.citizen') }}</p></RouterLink>
      <RouterLink class="card" to="/steward"><h2>Data Intake Fabric</h2><p>{{ t('home.steward') }}</p></RouterLink>
    </div>
  </main>
</template>

<style scoped>
a.card { text-decoration: none; color: inherit; }
a.card:hover { border-color: var(--darumen-accent); }
</style>

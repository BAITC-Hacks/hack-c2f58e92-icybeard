<script setup lang="ts">
import Toast from 'primevue/toast'
import { useI18n } from 'vue-i18n'
import AppTopbar from '@/components/app/AppTopbar.vue'

const { t } = useI18n()
</script>

<template>
  <div class="shell">
    <AppTopbar />
    <Toast />
    <RouterView />
    <footer class="footer">{{ t('app.footer') }}</footer>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { scribe } from '@/api/endpoints'
import ErrorBox from '@/components/ErrorBox.vue'

const { t, locale } = useI18n()
const route = useRoute()
const text = ref('')
const approvedAt = ref('')
const error = ref<unknown>(null)

onMounted(async () => {
  try {
    const leaflet = await scribe.leaflet(String(route.params.token))
    text.value = leaflet.text
    approvedAt.value = leaflet.approvedAt
  } catch (e) {
    error.value = e
  }
})
</script>

<template>
  <main class="page" style="max-width: 720px">
    <h1>{{ t('leaflet.title') }}</h1>
    <ErrorBox :error="error" />
    <div v-if="text" class="card">
      <p style="white-space: pre-wrap">{{ text }}</p>
      <p class="muted">{{ t('leaflet.approvedBy') }} {{ new Date(approvedAt).toLocaleString(locale === 'kk' ? 'kk-KZ' : 'ru-RU') }}. Darumen Care.</p>
    </div>
  </main>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { Explanation, ModelInfo } from '@/api/types'
import OriginTag from '@/components/OriginTag.vue'
import { signed } from '@/lib/format'

defineProps<{ explanation: Explanation; model?: ModelInfo; unit?: string }>()
const { t } = useI18n()
</script>

<template>
  <div class="card">
    <h2>{{ t('explanationCard.title') }} <OriginTag kind="ml" /></h2>
    <p>{{ explanation.summary }}</p>
    <div v-for="factor in explanation.factors" :key="factor.name" class="factor">
      <span>{{ factor.text }}</span>
      <span class="contribution" :class="factor.contribution >= 0 ? 'plus' : 'minus'">{{ signed(factor.contribution) }} {{ unit ?? '' }}</span>
    </div>
    <p v-if="model" class="muted" style="margin-top: 8px">{{ t('explanationCard.model', { name: model.name, version: model.version, through: model.trainedThrough }) }}</p>
  </div>
</template>

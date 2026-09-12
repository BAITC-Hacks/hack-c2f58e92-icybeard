<script setup lang="ts">
import type { Explanation, ModelInfo } from '@/api/types'
import OriginTag from '@/components/OriginTag.vue'
import { signed } from '@/lib/format'

defineProps<{ explanation: Explanation; model?: ModelInfo; unit?: string }>()
</script>

<template>
  <div class="card">
    <h2>Почему так <OriginTag kind="ml" /></h2>
    <p>{{ explanation.summary }}</p>
    <div v-for="factor in explanation.factors" :key="factor.name" class="factor">
      <span>{{ factor.text }}</span>
      <span class="contribution" :class="factor.contribution >= 0 ? 'plus' : 'minus'">{{ signed(factor.contribution) }} {{ unit ?? '' }}</span>
    </div>
    <p v-if="model" class="muted" style="margin-top: 8px">Модель {{ model.name }} {{ model.version }}, обучена по {{ model.trainedThrough }}</p>
  </div>
</template>

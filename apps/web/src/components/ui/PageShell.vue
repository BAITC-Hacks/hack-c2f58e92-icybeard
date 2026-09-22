<script setup lang="ts">
import OriginTag from '@/components/OriginTag.vue'

/** Каркас страницы: заголовок с меткой происхождения, подводка, при необходимости — пометка «синтетические данные»
 * и действия справа. Заменяет `<main class="page"><h1>…` в каждом экране. */
defineProps<{ title: string; lead?: string; origin?: 'ml' | 'formula' | 'ai'; originNote?: string; synthetic?: string }>()
</script>

<template>
  <main class="page">
    <header class="page-head">
      <div>
        <h1>{{ title }} <OriginTag v-if="origin" :kind="origin" :note="originNote" /><slot name="title-extra" /></h1>
        <p v-if="lead" class="lead">{{ lead }}</p>
        <p v-if="synthetic" class="lead synthetic">{{ synthetic }}</p>
      </div>
      <div v-if="$slots.actions" class="page-actions"><slot name="actions" /></div>
    </header>
    <slot />
  </main>
</template>

<style scoped>
.page-head { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--dm-space-4); flex-wrap: wrap; margin-bottom: var(--dm-space-4); }
.page-head h1 { margin-bottom: 4px; }
.page-head .lead { margin-bottom: 0; }
.page-actions { display: flex; gap: var(--dm-space-2); flex-wrap: wrap; align-items: center; }
</style>

<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import OriginTag from '@/components/OriginTag.vue'

/** Карточка с hairline-границей; с `to` — целиком ссылка. Метка происхождения — в заголовке, у всех чисел модели. */
defineProps<{ title?: string; origin?: 'ml' | 'formula' | 'ai'; originNote?: string; to?: RouteLocationRaw; dense?: boolean }>()
</script>

<template>
  <component :is="to ? 'RouterLink' : 'section'" class="card" :class="{ dense, link: !!to }" :to="to">
    <header v-if="title || $slots.header" class="card-head">
      <h2 v-if="title">{{ title }} <OriginTag v-if="origin" :kind="origin" :note="originNote" /></h2>
      <div v-if="$slots.header" class="card-head-extra"><slot name="header" /></div>
    </header>
    <slot />
  </component>
</template>

<style scoped>
.card.dense { padding: var(--dm-space-3); }
.card.link { display: block; text-decoration: none; color: inherit; }
.card.link:hover { border-color: var(--dm-accent); }
.card-head { display: flex; justify-content: space-between; align-items: baseline; gap: var(--dm-space-2); }
.card-head h2 { margin-bottom: var(--dm-space-3); }
</style>

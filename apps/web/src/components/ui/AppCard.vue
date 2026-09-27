<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import OriginTag from '@/components/OriginTag.vue'

/** Карточка-секция: белая, radius 16, padding 24, без рамки; заголовок 20 / 500 с меткой происхождения, справа —
 * слот header (чип, подпись, ссылка). С `to` — целиком ссылка; `label` — заголовок как label uppercase (hero-карточки). */
defineProps<{ title?: string; origin?: 'ml' | 'formula' | 'ai'; originNote?: string; to?: RouteLocationRaw; dense?: boolean; label?: boolean }>()
</script>

<template>
  <component :is="to ? 'RouterLink' : 'section'" class="card" :class="{ dense, link: !!to }" :to="to">
    <header v-if="title || $slots.header" class="card-head">
      <h2 v-if="title && !label">{{ title }}<OriginTag v-if="origin" :kind="origin" :note="originNote" class="head-origin" /></h2>
      <span v-else-if="title" class="eyebrow">{{ title }}<OriginTag v-if="origin" :kind="origin" :note="originNote" class="head-origin" /></span>
      <div v-if="$slots.header" class="card-head-extra"><slot name="header" /></div>
    </header>
    <slot />
  </component>
</template>

<style scoped>
.card.dense { padding: var(--dm-space-4); }
.card.link { display: block; text-decoration: none; color: inherit; }
.card.link:hover { box-shadow: inset 0 0 0 2px var(--dm-accent); }
.card-head { display: flex; justify-content: space-between; align-items: center; gap: var(--dm-space-3); margin-bottom: var(--dm-space-3); flex-wrap: wrap; }
.card-head h2 { margin: 0; display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.card-head .eyebrow { display: inline-flex; align-items: center; gap: 10px; }
.card-head-extra { display: flex; align-items: center; gap: 8px; margin-left: auto; }
</style>

<script setup lang="ts">
/** Сетка карточек: 1, 2 или 3 колонки с автопереносом на узких экранах. */
withDefaults(defineProps<{ cols?: 1 | 2 | 3; title?: string }>(), { cols: 1 })
</script>

<template>
  <section class="section">
    <h2 v-if="title" class="section-title">{{ title }}</h2>
    <div class="grid" :class="`cols-${cols}`"><slot /></div>
  </section>
</template>

<style scoped>
.section { margin-top: var(--dm-space-4); }
.section-title { font-size: 1.05rem; margin: 0 0 var(--dm-space-3); }
.grid.cols-1 { grid-template-columns: 1fr; }
</style>

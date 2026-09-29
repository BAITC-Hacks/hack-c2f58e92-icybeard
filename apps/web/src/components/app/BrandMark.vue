<script setup lang="ts">
/** Знак Darumen (геометрия svg/mark.svg из darumen-assets): в шапке и сайдбаре; сюда прилетает знак заставки из
 * index.html (по атрибуту data-brand-mark). Цвета «синей гаммы»: блок — чернила --text (в тёмной теме светлые),
 * дуга и сектор — синий --accent. */
withDefaults(defineProps<{ size?: number }>(), { size: 28 })
</script>

<template>
  <svg class="brand-mark" viewBox="20 20 63 60" :width="size" :height="Math.round((size * 60) / 63)" aria-hidden="true" data-brand-mark>
    <path class="block" d="M30 22h19v56H30a8 8 0 0 1-8-8V30a8 8 0 0 1 8-8z" />
    <path class="arc" d="M53 25a25 25 0 0 1 25 25" fill="none" stroke-width="6" stroke-linecap="round" />
    <path class="sector" d="M53 50h28a28 28 0 0 1-28 28z" />
  </svg>
</template>

<style scoped>
.brand-mark { display: block; flex: none; }
.block { fill: var(--text, #1B2440); }
.arc { stroke: var(--accent, #2F6FE4); }
.sector { fill: var(--accent, #2F6FE4); }
</style>

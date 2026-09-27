<script setup lang="ts">
/** Знак Darumen (геометрия svg/mark.svg из darumen-assets): в шапке и сайдбаре; сюда прилетает знак заставки из
 * index.html (по атрибуту data-brand-mark). Цвета Палитры C: блок #333333 (в тёмной теме — светлые чернила),
 * дуга и сектор — фиолетовый accent #5B5BD6 (в тёмной теме — #8B8BF0). */
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
.block { fill: var(--dm-ink, #333333); }
.arc { stroke: var(--dm-accent, #5B5BD6); }
.sector { fill: var(--dm-accent, #5B5BD6); }
</style>

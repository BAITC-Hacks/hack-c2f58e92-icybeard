<script setup lang="ts">
/** Знак Darumen (геометрия svg/mark.svg из darumen-assets): в шапке и сайдбаре; сюда прилетает знак лоадера из index.html
 * (по атрибуту data-brand-mark). Цвета бренда фиксированные: блок Navy на светлом и Mist на тёмном, дуга и сектор Sky. */
withDefaults(defineProps<{ size?: number }>(), { size: 26 })
</script>

<template>
  <svg class="brand-mark" viewBox="20 20 63 60" :width="size" :height="Math.round((size * 60) / 63)" aria-hidden="true" data-brand-mark>
    <path class="block" d="M30 22h19v56H30a8 8 0 0 1-8-8V30a8 8 0 0 1 8-8z" />
    <path d="M53 25a25 25 0 0 1 25 25" fill="none" stroke="#29B6D8" stroke-width="6" stroke-linecap="round" />
    <path d="M53 50h28a28 28 0 0 1-28 28z" fill="#29B6D8" />
  </svg>
</template>

<style scoped>
.brand-mark { display: block; flex: none; }
.block { fill: #0b2a4a; }
:global(.darumen-dark) .block { fill: #f1f8fb; }
</style>

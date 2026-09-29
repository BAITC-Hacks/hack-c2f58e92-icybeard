<script setup lang="ts">
import BrandMark from '@/components/app/BrandMark.vue'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Шапка публичных страниц («синяя гамма»): белая 64 px с разделителем, знак + «darumen» слева, RU/KK и тема справа. */
</script>

<template>
  <header class="public-bar">
    <RouterLink class="brand" to="/"><BrandMark :size="28" /><span>darumen</span></RouterLink>
    <span class="spacer" />
    <LocaleSwitch />
    <ThemeToggle />
  </header>
</template>

<style scoped>
.public-bar { display: flex; align-items: center; gap: 12px; min-height: 64px; padding: 0 28px; background: var(--surface); border-bottom: 1px solid var(--border); box-sizing: border-box; }
.brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--text); font-size: var(--fs-lg); font-weight: var(--fw-extrabold); letter-spacing: -0.01em; }
.spacer { flex: 1; }
@media (max-width: 640px) { .public-bar { padding: 0 16px; min-height: 56px; } }
</style>

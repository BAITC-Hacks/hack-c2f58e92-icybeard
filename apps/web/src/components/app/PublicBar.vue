<script setup lang="ts">
import BrandMark from '@/components/app/BrandMark.vue'
import LocaleSwitch from './LocaleSwitch.vue'
import ThemeToggle from './ThemeToggle.vue'

/** Полоса публичных страниц (W-Auth-Signup, Pending, Verify, Invite): знак + «darumen» слева, RU/KK и тема справа. */
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
.public-bar { display: flex; align-items: center; gap: 12px; padding: 24px 40px 0; }
.brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--dm-ink); font-size: var(--dm-text-lg); font-weight: 600; letter-spacing: -0.02em; }
.spacer { flex: 1; }
@media (max-width: 640px) { .public-bar { padding: 16px 16px 0; } }
</style>

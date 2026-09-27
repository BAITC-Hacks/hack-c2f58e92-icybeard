<script setup lang="ts">
import BrandMark from '@/components/app/BrandMark.vue'
import Button from 'primevue/button'
import Drawer from 'primevue/drawer'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AppSidebarNav from './AppSidebarNav.vue'

/** Боковой каркас персонала: белый aside 240 px без рамки (до 1100 px — 64 px, только иконки), на телефоне — верхняя
 * полоска с кнопкой меню и drawer с тем же наполнением. */
const { t } = useI18n()
const open = ref(false)
</script>

<template>
  <aside class="sidebar"><AppSidebarNav /></aside>
  <header class="mobilebar">
    <Button icon="pi pi-bars" text rounded :aria-label="t('shell.menu')" data-testid="menu-open" @click="open = true" />
    <RouterLink class="brand" to="/"><BrandMark :size="24" /><span>Darumen Health</span></RouterLink>
  </header>
  <Drawer v-model:visible="open" :header="t('shell.menu')" class="sidebar-drawer" :style="{ width: '280px' }">
    <AppSidebarNav @navigate="open = false" />
  </Drawer>
</template>

<style scoped>
.sidebar { width: 240px; flex: none; position: sticky; top: 0; height: 100vh; background: var(--dm-surface); overflow: hidden; }
.mobilebar { display: none; align-items: center; gap: 6px; padding: 6px 10px; background: var(--dm-surface); }
.mobilebar .brand { display: flex; align-items: center; gap: 8px; font-weight: 600; letter-spacing: -0.02em; color: var(--dm-ink); text-decoration: none; }
@media (max-width: 1100px) { .sidebar { width: 64px; } }
@media (max-width: 640px) { .sidebar { display: none; } .mobilebar { display: flex; } }
</style>

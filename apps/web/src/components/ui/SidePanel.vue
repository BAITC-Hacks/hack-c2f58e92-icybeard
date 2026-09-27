<script setup lang="ts">
import Drawer from 'primevue/drawer'

/** Панель деталей справа: открывается по клику в таблице, закрывается крестиком или Esc. Заголовок 20 / 500. */
defineProps<{ title: string; subtitle?: string; width?: string }>()
const visible = defineModel<boolean>('visible', { default: false })
</script>

<template>
  <Drawer v-model:visible="visible" position="right" class="side-panel" :style="{ width: width ?? 'min(460px, 100vw)' }">
    <template #header>
      <div class="side-head">
        <div class="side-title">{{ title }}</div>
        <div v-if="subtitle" class="muted small">{{ subtitle }}</div>
      </div>
    </template>
    <slot />
    <template v-if="$slots.footer" #footer><div class="side-foot"><slot name="footer" /></div></template>
  </Drawer>
</template>

<style scoped>
.side-head { min-width: 0; }
.side-title { font-weight: 500; font-size: var(--dm-text-lg); letter-spacing: -0.01em; }
.side-foot { display: flex; gap: 8px; flex-wrap: wrap; }
</style>

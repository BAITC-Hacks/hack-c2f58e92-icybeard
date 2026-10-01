<script setup lang="ts">
import Drawer from 'primevue/drawer'

/** Панель деталей справа (одна ширина у всех экранов — 560 px, на телефоне во всю ширину): открывается по клику в таблице, закрывается крестиком или Esc. Заголовок 22 / 800, отступы 28 px. */
defineProps<{ title: string; subtitle?: string }>()
const visible = defineModel<boolean>('visible', { default: false })
</script>

<template>
  <Drawer v-model:visible="visible" position="right" class="side-panel" :style="{ width: 'min(560px, 100vw)' }">
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
.side-head { display: flex; flex-direction: column; gap: 4px; }
.side-title { font-weight: var(--fw-extrabold); font-size: var(--fs-xl); letter-spacing: -0.01em; }
.side-head .small { font-size: var(--fs-base-sm); }
:global(.side-panel .p-drawer-header) { padding: 24px 28px 16px; }
:global(.side-panel .p-drawer-content) { padding: 8px 28px 24px; }
:global(.side-panel .p-drawer-footer) { padding: 16px 28px 24px; border-top: 1px solid var(--border); }
.side-foot { display: flex; gap: 8px; flex-wrap: wrap; }
</style>

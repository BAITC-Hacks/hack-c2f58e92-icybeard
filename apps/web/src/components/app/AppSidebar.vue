<script setup lang="ts">
import BrandMark from '@/components/app/BrandMark.vue'
import Button from 'primevue/button'
import Drawer from 'primevue/drawer'
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AppSidebarNav from './AppSidebarNav.vue'

/** Боковой каркас персонала: белый aside 264 px с разделителем справа. Кнопка внизу сворачивает его до полосы
 * иконок (72 px) — выбор запоминается в браузере; на экранах до 1100 px он всегда свёрнут. На телефоне —
 * верхняя полоска с кнопкой меню и drawer с тем же наполнением (в drawer есть и подвал с локалью/темой,
 * на десктопе эти элементы живут в верхней полосе AppTopstrip). */
const { t } = useI18n()
const open = ref(false)

const COLLAPSED_KEY = 'darumen.sidebar.collapsed'
function readCollapsed(): boolean {
  try {
    return window.localStorage.getItem(COLLAPSED_KEY) === '1'
  } catch {
    return false
  }
}
const collapsed = ref(readCollapsed())
function toggleCollapsed() {
  collapsed.value = !collapsed.value
  try {
    window.localStorage.setItem(COLLAPSED_KEY, collapsed.value ? '1' : '0')
  } catch {
    // без storage выбор живёт до перезагрузки
  }
}

const narrowQuery = typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(max-width: 1100px)') : null
const narrow = ref(narrowQuery?.matches ?? false)
const onNarrow = (e: MediaQueryListEvent) => (narrow.value = e.matches)
onMounted(() => narrowQuery?.addEventListener('change', onNarrow))
onBeforeUnmount(() => narrowQuery?.removeEventListener('change', onNarrow))
const compact = computed(() => collapsed.value || narrow.value)
</script>

<template>
  <aside class="sidebar" :class="{ compact }">
    <div class="sidebar-nav"><AppSidebarNav :foot="false" :compact="compact" /></div>
    <button v-if="!narrow" type="button" class="collapse" :title="collapsed ? t('shell.expandMenu') : t('shell.collapseMenu')" :aria-label="collapsed ? t('shell.expandMenu') : t('shell.collapseMenu')"
      :aria-expanded="!collapsed" data-testid="sidebar-collapse" @click="toggleCollapsed">
      <i class="pi" :class="collapsed ? 'pi-angle-double-right' : 'pi-angle-double-left'" aria-hidden="true" /><span v-if="!collapsed">{{ t('shell.collapseMenu') }}</span>
    </button>
  </aside>
  <header class="mobilebar">
    <Button icon="pi pi-bars" text rounded :aria-label="t('shell.menu')" data-testid="menu-open" @click="open = true" />
    <RouterLink class="brand" to="/"><BrandMark :size="24" /><span>Darumen Health</span></RouterLink>
  </header>
  <Drawer v-model:visible="open" :header="t('shell.menu')" class="sidebar-drawer" :style="{ width: '280px' }">
    <AppSidebarNav @navigate="open = false" />
  </Drawer>
</template>

<style scoped>
.sidebar { width: var(--sidebar-w); flex: none; position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column; background: var(--surface); border-right: 1px solid var(--border); box-sizing: border-box; overflow: hidden; transition: width 0.18s ease; }
.sidebar.compact { width: 72px; }
.sidebar-nav { flex: 1; min-height: 0; }
.collapse { display: flex; align-items: center; gap: 10px; height: 42px; margin: 8px 12px 14px; padding: 0 12px; border: 0; border-radius: var(--radius-md); background: none; color: var(--text-faint); font: inherit; font-size: 14px; font-weight: var(--fw-semibold); cursor: pointer; white-space: nowrap; }
.collapse:hover { background: var(--surface-hover); color: var(--text); }
.collapse .pi { font-size: 15px; }
.sidebar.compact .collapse { justify-content: center; padding: 0; margin-inline: 10px; }
.mobilebar { display: none; align-items: center; gap: 6px; padding: 6px 10px; background: var(--surface); border-bottom: 1px solid var(--border); }
.mobilebar .brand { display: flex; align-items: center; gap: 8px; font-weight: var(--fw-extrabold); letter-spacing: -0.02em; color: var(--text); text-decoration: none; }
@media (max-width: 640px) { .sidebar { display: none; } .mobilebar { display: flex; } }
@media (prefers-reduced-motion: reduce) { .sidebar { transition: none; } }
</style>

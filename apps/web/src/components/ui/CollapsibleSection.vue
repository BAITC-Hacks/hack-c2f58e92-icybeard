<script setup lang="ts">
import { ref, useId } from 'vue'
import OriginTag from '@/components/OriginTag.vue'

/** Свёртываемая секция-карточка: заголовок обычным жирным текстом, итог справа («7 истекли, 3 действуют»), шеврон; свёрнута по
 * умолчанию. Метка происхождения — на заголовке, одна на секцию. */
const props = defineProps<{ title: string; summary?: string; open?: boolean; origin?: 'ml' | 'formula' | 'ai'; originNote?: string; tone?: 'warn' | 'danger' | 'ok'; lead?: string }>()
const emit = defineEmits<{ toggle: [open: boolean] }>()
const expanded = ref(props.open ?? false)
const id = useId()

function toggle() {
  expanded.value = !expanded.value
  emit('toggle', expanded.value)
}
</script>

<template>
  <section class="collapsible card" :class="{ expanded }">
    <button type="button" class="head" :aria-expanded="expanded" :aria-controls="id" @click="toggle">
      <span class="head-text">
        <span class="head-title">{{ title }} <OriginTag v-if="origin" :kind="origin" :note="originNote" /></span>
        <span v-if="lead" class="head-lead">{{ lead }}</span>
      </span>
      <span v-if="summary" class="summary tabular" :class="tone">{{ summary }}</span>
      <i class="pi chevron" :class="expanded ? 'pi-chevron-up' : 'pi-chevron-down'" aria-hidden="true" />
    </button>
    <div v-show="expanded" :id="id" class="body"><slot /></div>
  </section>
</template>

<style scoped>
.collapsible { padding: 0; }
.head { display: flex; align-items: center; gap: var(--dm-space-3); width: 100%; padding: 14px 20px; min-height: 52px; box-sizing: border-box; background: none; border: 0; color: inherit; font: inherit; text-align: left; cursor: pointer; border-radius: var(--dm-radius-lg); }
.expanded .head { border-radius: var(--dm-radius-lg) var(--dm-radius-lg) 0 0; }
.head-text { flex: 1; display: flex; flex-direction: column; gap: 4px; min-width: 0; }
.head-lead { font-size: var(--dm-text-sm); color: var(--text-secondary); font-weight: 400; line-height: 1.45; }
.head-title { display: flex; align-items: center; gap: 10px; font-size: var(--fs-base); font-weight: var(--fw-bold); color: var(--text); }
.summary { color: var(--dm-muted); font-size: var(--dm-text-sm); text-align: right; }
.summary.warn, .summary.danger { color: var(--dm-danger); }
.summary.ok { color: var(--dm-ok); }
.chevron { color: var(--dm-muted); font-size: 0.8rem; }
.body { padding: 16px 20px 20px; border-top: 1px solid var(--dm-hairline); }
</style>

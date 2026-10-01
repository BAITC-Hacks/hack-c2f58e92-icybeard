<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

/** Приоритет в строке рабочего списка: цветной кружок с числом. Цвет — относительно максимума в списке:
 * верхняя треть — высокий (danger), середина — средний (warning), нижняя — низкий (success). Только представление. */
const props = withDefaults(defineProps<{ value: number; max?: number }>(), { max: 100 })
const { t } = useI18n()
const level = computed(() => {
  const ratio = props.value / (props.max || 1)
  return ratio >= 2 / 3 ? 'high' : ratio < 1 / 3 ? 'low' : 'mid'
})
</script>

<template>
  <span class="priority tabular" :class="level" :title="t(`doctor.worklist.priorityLevel.${level}`)" :aria-label="`${t(`doctor.worklist.priorityLevel.${level}`)}: ${Math.round(value)}`">{{ Math.round(value) }}</span>
</template>

<style scoped>
.priority { display: inline-grid; place-items: center; min-width: 32px; height: 32px; padding: 0 6px; border-radius: 999px; box-sizing: border-box; font-weight: var(--fw-bold); font-size: var(--fs-md); }
.high { background: var(--danger-bg); color: var(--danger-text); }
.mid { background: var(--warning-bg); color: var(--warning-text); }
.low { background: var(--success-bg); color: var(--success-text); }
</style>

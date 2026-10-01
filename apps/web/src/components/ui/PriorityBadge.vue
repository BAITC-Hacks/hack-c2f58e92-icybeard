<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

/** Приоритет в строке рабочего списка: цветной кружок с числом по фиксированной шкале API 0…10 (Worklist.cs):
 * 7–10 — высокий (danger), 4–6 — средний (warning), 0–3 — низкий (success). Пороги постоянные, а не от максимума
 * списка, чтобы «8» значила одно и то же в любом регионе и профиле. Только представление. */
const PRIORITY_MAX = 10
const props = defineProps<{ value: number }>()
const { t } = useI18n()
const rounded = computed(() => Math.max(0, Math.min(PRIORITY_MAX, Math.round(props.value))))
const level = computed(() => (rounded.value >= 7 ? 'high' : rounded.value >= 4 ? 'mid' : 'low'))
const hint = computed(() => `${t(`doctor.worklist.priorityLevel.${level.value}`)} · ${t('doctor.worklist.priorityOf', { n: rounded.value, max: PRIORITY_MAX })}`)
</script>

<template>
  <span class="priority tabular" :class="level" :title="hint" :aria-label="hint">{{ rounded }}</span>
</template>

<style scoped>
.priority { display: inline-grid; place-items: center; min-width: 32px; height: 32px; padding: 0 6px; border-radius: 999px; box-sizing: border-box; font-weight: var(--fw-bold); font-size: var(--fs-md); }
.high { background: var(--danger-bg); color: var(--danger-text); }
.mid { background: var(--warning-bg); color: var(--warning-text); }
.low { background: var(--success-bg); color: var(--success-text); }
</style>

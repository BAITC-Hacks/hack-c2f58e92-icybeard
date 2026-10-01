<script setup lang="ts">
import { computed } from 'vue'
import type { RouteStage } from '@/api/types'
import { dateShort } from '@/lib/route'

/** Горизонтальный степпер этапов маршрута («синяя гамма», route-new / doctor-route-patient-new).
 * Гражданин: узлы 40 — пройден --accent с белой галочкой, текущий --accent-soft с рамкой 2.5 --accent и точкой 9,
 * будущий белый с рамкой 2 --toggle-off; линия 2px --border-soft, пройденная часть --accent.
 * Врач (`variant="doctor"`): узлы 48 — пройден --success-bg с галочкой, активный --accent с белой цифрой и кольцом
 * 6px --accent-soft, будущий --surface-muted с цифрой; линия 4px --border, пройденная --success-line.
 * Под узлом — название этапа, ниже мелко дата или норматив (`norms`). Только представление, данные — из кода. */
const props = defineProps<{ stages: RouteStage[]; variant?: 'citizen' | 'doctor'; norms?: boolean }>()

const n = computed(() => props.stages.length)
/** Доля линии до центра текущего узла (все пройдены — 1, ничего не начато — 0). */
const progress = computed(() => {
  if (n.value < 2) return 0
  const current = props.stages.findIndex((s) => s.status === 'current')
  if (current >= 0) return current / (n.value - 1)
  return props.stages.every((s) => s.status === 'done') ? 1 : 0
})
/** Линия идёт от центра первой колонки до центра последней: отступы по 50%/n с краёв. */
const lineStyle = computed(() => ({ left: `calc(50% / ${n.value})`, right: `calc(50% / ${n.value})` }))
const doneStyle = computed(() => ({ left: `calc(50% / ${n.value})`, width: `calc((100% - 100% / ${n.value}) * ${progress.value})` }))
const sub = (stage: RouteStage) => (stage.date ? dateShort(stage.date) : props.norms && stage.norm ? stage.norm : '')
</script>

<template>
  <ol class="steps" :class="variant === 'doctor' ? 'doctor' : 'citizen'" :aria-label="stages.find((s) => s.status === 'current')?.title">
    <span class="line" :style="lineStyle" aria-hidden="true" />
    <span class="line done" :style="doneStyle" aria-hidden="true" />
    <li v-for="(stage, i) in stages" :key="stage.code" class="step" :class="stage.status">
      <span class="node" aria-hidden="true">
        <svg v-if="stage.status === 'done'" class="check" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M5 12l5 5L19 7" /></svg>
        <span v-else-if="stage.status === 'current' && variant !== 'doctor'" class="dot" />
        <template v-else-if="variant === 'doctor'">{{ i + 1 }}</template>
      </span>
      <span class="label">{{ stage.title }}</span>
      <span v-if="sub(stage)" class="sub tabular">{{ sub(stage) }}</span>
    </li>
  </ol>
</template>

<style scoped>
.steps { list-style: none; margin: 0; padding: 0; display: flex; align-items: flex-start; position: relative; }
.step { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 9px; position: relative; text-align: center; }
.node { border-radius: 50%; display: flex; align-items: center; justify-content: center; box-sizing: border-box; z-index: 1; flex: none; }
.label { font-size: 13px; font-weight: var(--fw-bold); color: var(--text-secondary); padding: 0 6px; }
.sub { font-size: var(--fs-xs); color: var(--text-faint); margin-top: -5px; }
.line { position: absolute; background: var(--border-soft); }
.line.done { background: var(--accent); }

/* гражданин: узлы 40, линия 2px */
.citizen .line { top: 19px; height: 2px; }
.citizen .node { width: 40px; height: 40px; }
.citizen .step.done .node { background: var(--accent); }
.citizen .step.done .check { width: 16px; height: 16px; stroke-width: 2.6; color: var(--text-on-accent); }
.citizen .step.current .node { background: var(--accent-soft); border: 2.5px solid var(--accent); }
.citizen .step.current .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--accent); }
.citizen .step.current .label { font-weight: var(--fw-extrabold); color: var(--accent-strong); }
.citizen .step.upcoming .node { background: var(--surface); border: 2px solid var(--toggle-off); }
.citizen .step.upcoming .label { font-weight: var(--fw-semibold); color: var(--text-faint); }

/* врач: узлы 48, линия 4px, пройденная — success-line */
.doctor .line { top: 22px; height: 4px; background: var(--border); }
.doctor .line.done { background: var(--success-line); }
.doctor .node { width: 48px; height: 48px; font-size: var(--fs-lg); font-weight: var(--fw-extrabold); background: var(--surface-muted); color: var(--text-muted); }
.doctor .step.done .node { background: var(--success-bg); color: var(--success-text); }
.doctor .step.done .check { width: 18px; height: 18px; stroke-width: 3; }
.doctor .step.current .node { background: var(--accent); color: var(--text-on-accent); box-shadow: 0 0 0 6px var(--accent-soft); }
.doctor .step.current .label { font-size: var(--fs-md); font-weight: var(--fw-extrabold); color: var(--accent-strong); }
.doctor .label { font-size: 14px; font-weight: var(--fw-regular); color: var(--text-muted); }
.doctor .step.done .label { color: var(--text-secondary); font-weight: var(--fw-semibold); }

@media (max-width: 720px) {
  .label { font-size: var(--fs-xs); }
  .citizen .node { width: 32px; height: 32px; }
  .citizen .line { top: 15px; }
  .doctor .node { width: 40px; height: 40px; }
  .doctor .line { top: 18px; }
}
</style>

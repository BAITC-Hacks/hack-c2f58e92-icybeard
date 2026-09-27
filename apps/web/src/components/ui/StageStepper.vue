<script setup lang="ts">
import type { RouteStage } from '@/api/types'
import { dateShort } from '@/lib/route'

/** Этапы маршрута. Горизонтальный прогресс (W-Patient): полосы 3 px (пройдено ink, впереди hairline) с точкой 14 px
 * coral и обводкой ink на текущем, под ними подписи 12 ink-2. Вертикальная лента (W-Route, `vertical`): точки 10 px
 * ink / coral / hairline и линия между ними, справа название 15 / 500 и дата 13 ink-3. `chevrons` оставлен как псевдоним
 * горизонтального варианта для прежних вызовов. */
defineProps<{ stages: RouteStage[]; chevrons?: boolean; norms?: boolean; vertical?: boolean }>()
</script>

<template>
  <ol v-if="vertical" class="timeline">
    <li v-for="(stage, i) in stages" :key="stage.code" :class="stage.status">
      <span class="rail" aria-hidden="true"><span class="dot" /><span v-if="i < stages.length - 1" class="line" /></span>
      <span class="text">
        <span class="title">{{ stage.title }}</span>
        <span class="date tabular">{{ stage.date ? dateShort(stage.date) : norms && stage.norm ? stage.norm : '' }}</span>
      </span>
    </li>
  </ol>
  <div v-else class="progress" :title="stages.find((s) => s.status === 'current')?.title">
    <div class="bars">
      <span v-for="stage in stages" :key="stage.code" class="bar" :class="stage.status" aria-hidden="true"><span v-if="stage.status === 'current'" class="marker" /><span class="track" /></span>
    </div>
    <div class="labels">
      <span v-for="stage in stages" :key="stage.code" class="stage-label" :class="stage.status" :title="stage.norm ?? undefined">
        {{ stage.title }}<template v-if="stage.date"> · {{ dateShort(stage.date) }}</template><template v-else-if="norms && stage.norm"> · {{ stage.norm }}</template>
      </span>
    </div>
  </div>
</template>

<style scoped>
/* горизонтальный прогресс */
.progress { display: flex; flex-direction: column; gap: 8px; }
.bars, .labels { display: grid; grid-auto-flow: column; grid-auto-columns: minmax(0, 1fr); gap: 4px; }
.bar { display: flex; align-items: center; gap: 4px; height: 14px; }
.bar .track { flex: 1; height: 3px; border-radius: 2px; background: var(--dm-hairline); }
.bar.done .track { background: var(--dm-primary); }
.bar .marker { width: 14px; height: 14px; border-radius: 50%; background: var(--dm-accent); border: 2px solid var(--dm-ink); box-sizing: border-box; flex: none; }
.labels { font-size: var(--dm-text-xs); color: var(--dm-muted); letter-spacing: 0.02em; }
.stage-label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.stage-label.current { color: var(--dm-ink); font-weight: 500; }
/* вертикальная лента */
.timeline { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; }
.timeline li { display: flex; gap: 16px; min-height: 64px; }
.timeline li:last-child { min-height: 0; }
.rail { display: flex; flex-direction: column; align-items: center; width: 14px; flex: none; }
.rail .dot { width: 10px; height: 10px; border-radius: 50%; background: var(--dm-hairline); flex: none; margin-top: 6px; box-sizing: border-box; }
.rail .line { flex: 1; width: 3px; border-radius: 2px; background: var(--dm-hairline); margin-top: 4px; }
li.done .rail .dot, li.done .rail .line { background: var(--dm-primary); }
li.current .rail .dot { width: 14px; height: 14px; background: var(--dm-accent); border: 2px solid var(--dm-ink); margin-top: 4px; }
.text { display: flex; flex-direction: column; gap: 2px; padding-bottom: 16px; min-width: 0; }
li:last-child .text { padding-bottom: 0; }
.title { font-size: var(--dm-text-md); font-weight: 500; }
li.upcoming .title { color: var(--dm-muted); }
.date { font-size: 13px; color: var(--dm-muted); }
</style>

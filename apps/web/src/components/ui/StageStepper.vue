<script setup lang="ts">
import type { RouteStage } from '@/api/types'
import { dateShort } from '@/lib/route'

/** Этапы маршрута: горизонтальный степпер с датами под пройденными (гражданин) или стадии-шевроны (врач). */
defineProps<{ stages: RouteStage[]; chevrons?: boolean; norms?: boolean }>()
</script>

<template>
  <ol class="stepper" :class="{ chevrons }">
    <li v-for="stage in stages" :key="stage.code" :class="stage.status" :title="stage.norm ?? undefined">
      <span class="dot" aria-hidden="true"><i v-if="stage.status === 'done'" class="pi pi-check" /></span>
      <span class="text">
        <span class="title">{{ stage.title }}</span>
        <span class="date muted">{{ stage.date ? dateShort(stage.date) : norms && stage.norm ? stage.norm : '' }}</span>
      </span>
    </li>
  </ol>
</template>

<style scoped>
.stepper { list-style: none; display: flex; gap: 0; margin: 0; padding: 0; overflow-x: auto; }
.stepper li { flex: 1 1 0; min-width: 96px; display: flex; flex-direction: column; align-items: flex-start; gap: 6px; position: relative; padding-right: 12px; }
.stepper li::before { content: ''; position: absolute; top: 9px; left: 20px; right: 0; height: 2px; background: var(--dm-hairline); }
.stepper li:last-child::before { display: none; }
.stepper li.done::before { background: var(--dm-accent); }
.dot { width: 20px; height: 20px; border-radius: 50%; border: 2px solid var(--dm-hairline); background: var(--dm-surface); display: grid; place-items: center; font-size: 9px; color: #fff; position: relative; z-index: 1; box-sizing: border-box; }
li.done .dot { background: var(--dm-accent); border-color: var(--dm-accent); }
li.current .dot { border-color: var(--dm-accent); box-shadow: 0 0 0 3px var(--dm-accent-soft); }
.text { display: flex; flex-direction: column; font-size: 0.85rem; line-height: 1.25; }
li.current .title { font-weight: 600; }
li.upcoming .title { color: var(--dm-muted); }
.date { font-size: 0.78rem; font-variant-numeric: tabular-nums; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
/* шевроны: сплошная лента стадий */
.chevrons { gap: 4px; }
.chevrons li { padding: 6px 10px 6px 18px; min-width: 0; background: var(--dm-neutral-soft); clip-path: polygon(0 0, calc(100% - 12px) 0, 100% 50%, calc(100% - 12px) 100%, 0 100%, 12px 50%); flex-direction: row; align-items: center; }
.chevrons li::before { display: none; }
.chevrons li:first-child { clip-path: polygon(0 0, calc(100% - 12px) 0, 100% 50%, calc(100% - 12px) 100%, 0 100%); padding-left: 10px; }
.chevrons .dot { display: none; }
.chevrons .text { font-size: 0.8rem; }
.chevrons li.done { background: var(--dm-accent-soft); color: var(--dm-accent); }
.chevrons li.current { background: var(--dm-accent); color: #fff; }
.chevrons li.current .title { color: #fff; }
.chevrons li.current .date { color: rgba(255, 255, 255, 0.85); }
.chevrons li.done .date { color: var(--dm-accent); }
.chevrons .date { white-space: nowrap; }
</style>

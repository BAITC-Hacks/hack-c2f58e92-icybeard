<script setup lang="ts">
import { computed } from 'vue'

/** Две мини-полосы «модель / baseline» в плитке качества; `lowerIsBetter` красит модель, когда она хуже. */
const props = withDefaults(defineProps<{ model: number; baseline: number; lowerIsBetter?: boolean }>(), { lowerIsBetter: true })
const max = computed(() => Math.max(props.model, props.baseline, 1e-9))
const worse = computed(() => (props.lowerIsBetter ? props.model > props.baseline : props.model < props.baseline))
</script>

<template>
  <span class="pair" aria-hidden="true">
    <span class="bar model" :class="{ worse }" :style="{ width: `${(props.model / max) * 100}%` }" />
    <span class="bar baseline" :style="{ width: `${(props.baseline / max) * 100}%` }" />
  </span>
</template>

<style scoped>
.pair { display: flex; flex-direction: column; gap: 3px; width: 100%; max-width: 160px; }
.bar { display: block; height: 6px; border-radius: 3px; min-width: 2px; }
.model { background: var(--dm-accent); }
.model.worse { background: var(--dm-danger); }
.baseline { background: var(--dm-faint); }
</style>

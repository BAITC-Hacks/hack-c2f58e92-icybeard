<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'

/**
 * Метка происхождения числа или текста (доска C-Tokens): «ML-модель» (info-soft/ink), «расчёт по формуле» (inset/ink-2),
 * «AI-черновик» (lavender/accent-hover). С разрешением gov.map или referral.assist метка — ссылка на страницу качества моделей.
 */
const props = defineProps<{ kind: 'ml' | 'formula' | 'ai'; note?: string }>()
const auth = useAuthStore()
const { t } = useI18n()

const label = computed(() => t(`originTag.label.${props.kind}`))
const title = computed(() => props.note ?? t(`originTag.title.${props.kind}`))
const linkable = computed(() => auth.canAny(['gov.map', 'referral.assist']))
</script>

<template>
  <RouterLink v-if="linkable" class="origin" :class="kind" :title="title" to="/quality">{{ label }}</RouterLink>
  <span v-else class="origin" :class="kind" :title="title">{{ label }}</span>
</template>

<style scoped>
.origin {
  display: inline-block;
  font-size: var(--dm-text-xs);
  font-weight: 500;
  line-height: 1.2;
  letter-spacing: 0.02em;
  padding: 4px 10px;
  border-radius: var(--dm-radius-sm);
  text-decoration: none;
  vertical-align: middle;
  cursor: help;
  white-space: nowrap;
}
a.origin { cursor: pointer; }
.origin.ml { background: var(--dm-info-soft); color: var(--dm-ink); }
.origin.formula { background: var(--dm-neutral-soft); color: var(--dm-muted); }
.origin.ai { background: var(--dm-ai-soft); color: var(--dm-ai); }
</style>

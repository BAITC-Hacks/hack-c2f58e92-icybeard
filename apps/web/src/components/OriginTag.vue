<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'

/**
 * Метка происхождения числа или текста: «ML-модель», «расчёт по формуле», «AI-черновик».
 * Для ролей chief/regulator/admin метка — ссылка на страницу качества моделей.
 */
const props = defineProps<{ kind: 'ml' | 'formula' | 'ai'; note?: string }>()
const auth = useAuthStore()
const { t } = useI18n()

const label = computed(() => t(`originTag.label.${props.kind}`))
const title = computed(() => props.note ?? t(`originTag.title.${props.kind}`))
const linkable = computed(() => auth.hasRole('chief', 'regulator'))
</script>

<template>
  <RouterLink v-if="linkable" class="origin" :class="kind" :title="title" to="/quality">{{ label }}</RouterLink>
  <span v-else class="origin" :class="kind" :title="title">{{ label }}</span>
</template>

<style scoped>
.origin {
  display: inline-block;
  font-size: 11px;
  line-height: 1;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  padding: 4px 8px;
  border-radius: 999px;
  text-decoration: none;
  vertical-align: middle;
  cursor: help;
}
a.origin { cursor: pointer; }
.origin.ml { background: var(--dm-accent-soft); color: var(--dm-accent); }
.origin.formula { background: var(--dm-neutral-soft); color: var(--dm-muted); }
.origin.ai { background: var(--dm-ai-soft); color: var(--dm-ai); }
</style>

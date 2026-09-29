<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'

/**
 * Метка происхождения числа или текста (components.md «Происхождение числа»): бирюзовый «ML» и лавандовый «AI»
 * упразднены — все виды выглядят одинаково: нейтральная пилюля --surface-muted/--text-secondary с title-подсказкой.
 * С разрешением gov.map или referral.assist метка — ссылка на страницу качества моделей.
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
  font-size: var(--fs-xs);
  font-weight: var(--fw-bold);
  line-height: 1.2;
  letter-spacing: 0.01em;
  padding: 4px 10px;
  border-radius: var(--radius-pill);
  background: var(--surface-muted);
  color: var(--text-secondary);
  text-decoration: none;
  vertical-align: middle;
  cursor: help;
  white-space: nowrap;
}
a.origin { cursor: pointer; }
a.origin:hover { color: var(--accent-strong); }
</style>

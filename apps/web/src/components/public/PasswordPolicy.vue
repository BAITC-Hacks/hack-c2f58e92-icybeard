<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { passwordChecks, passwordStrength, PASSWORD_MIN_LENGTH, PASSWORD_RULES } from '@/lib/validation'

/** Шкала надёжности и чек-лист политики паролей realm (те же правила, что в Keycloak: длина 12, заглавная и строчная
 * буквы, цифра, не совпадает с логином). */
const props = defineProps<{ password: string; username?: string }>()
const { t } = useI18n()
const checks = computed(() => passwordChecks(props.password, props.username ?? ''))
const strength = computed(() => passwordStrength(props.password, props.username ?? ''))
const STRENGTH_KEYS = ['none', 'weak', 'medium', 'strong', 'excellent'] as const
</script>

<template>
  <div class="policy" data-testid="password-policy">
    <div class="meter" aria-hidden="true">
      <span v-for="i in 4" :key="i" class="seg" :class="{ on: i <= strength, [`s${strength}`]: i <= strength }" />
      <span class="meter-label" :class="`s${strength}`">{{ password ? t(`password.strength.${STRENGTH_KEYS[strength]}`) : '' }}</span>
    </div>
    <ul class="rules">
      <li v-for="rule in PASSWORD_RULES" :key="rule" :class="{ ok: checks[rule] }" :data-testid="`rule-${rule}`">
        <i :class="checks[rule] ? 'pi pi-check' : 'pi pi-circle'" aria-hidden="true" />{{ t(`password.rule.${rule}`, { n: PASSWORD_MIN_LENGTH }) }}
      </li>
    </ul>
  </div>
</template>

<style scoped>
.policy { display: flex; flex-direction: column; gap: 8px; }
.meter { display: grid; grid-template-columns: repeat(4, 1fr) auto; gap: 6px; align-items: center; }
.seg { height: 4px; border-radius: 2px; background: var(--dm-dot-idle); }
.seg.on.s1 { background: var(--dm-danger); }
.seg.on.s2 { background: var(--dm-warn-strong); }
.seg.on.s3, .seg.on.s4 { background: var(--dm-ok); }
.meter-label { font-size: var(--dm-text-sm); min-width: 88px; text-align: right; }
.meter-label.s1 { color: var(--dm-danger); }
.meter-label.s2 { color: var(--dm-warn); }
.meter-label.s3, .meter-label.s4 { color: var(--dm-ok); }
.rules { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 4px 12px; font-size: var(--dm-text-sm); color: var(--dm-muted); }
.rules li { display: flex; align-items: center; gap: 8px; }
.rules i { font-size: 11px; }
.rules li.ok { color: var(--dm-ok); }
</style>

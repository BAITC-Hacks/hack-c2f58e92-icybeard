<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { CODE_LENGTH } from '@/lib/validation'

/** Ввод 6-значного кода из письма (W-Auth-Verify): шесть ячеек 52 px на inset, фокус — фиолетовая рамка; цифра
 * переводит фокус дальше, Backspace на пустой — назад, вставка всего кода раскладывается по ячейкам. По шестой цифре —
 * событие complete. */
defineProps<{ disabled?: boolean; invalid?: boolean }>()
const model = defineModel<string>({ default: '' })
const emit = defineEmits<{ complete: [string] }>()
const { t } = useI18n()
const cells = ref<HTMLInputElement[]>([])
const digits = ref<string[]>(Array.from({ length: CODE_LENGTH }, (_, i) => model.value[i] ?? ''))

watch(model, (value) => {
  if (value !== digits.value.join('')) digits.value = Array.from({ length: CODE_LENGTH }, (_, i) => value[i] ?? '')
})

function commit() {
  const code = digits.value.join('')
  model.value = code
  if (code.length === CODE_LENGTH && /^\d+$/.test(code)) emit('complete', code)
}

function focus(index: number) {
  void nextTick(() => cells.value[Math.max(0, Math.min(CODE_LENGTH - 1, index))]?.focus())
}

function onInput(index: number, event: Event) {
  const input = event.target as HTMLInputElement
  const value = input.value.replace(/\D/g, '')
  if (value.length > 1) {
    fill(index, value)
    return
  }
  digits.value[index] = value
  input.value = value
  commit()
  if (value) focus(index + 1)
}

function fill(start: number, value: string) {
  for (let i = 0; i < value.length && start + i < CODE_LENGTH; i += 1) digits.value[start + i] = value[i]!
  commit()
  focus(Math.min(CODE_LENGTH - 1, start + value.length))
}

function onPaste(index: number, event: ClipboardEvent) {
  const text = (event.clipboardData?.getData('text') ?? '').replace(/\D/g, '')
  if (!text) return
  event.preventDefault()
  fill(text.length >= CODE_LENGTH ? 0 : index, text.slice(0, CODE_LENGTH))
}

function onKeydown(index: number, event: KeyboardEvent) {
  if (event.key === 'Backspace' && !digits.value[index] && index > 0) {
    digits.value[index - 1] = ''
    commit()
    focus(index - 1)
    event.preventDefault()
  } else if (event.key === 'ArrowLeft') focus(index - 1)
  else if (event.key === 'ArrowRight') focus(index + 1)
}

defineExpose({ focus: () => focus(digits.value.findIndex((d) => !d) === -1 ? CODE_LENGTH - 1 : digits.value.findIndex((d) => !d)) })
</script>

<template>
  <div class="code" role="group" :aria-label="t('signup.codeLabel')" data-testid="code-input">
    <input
      v-for="(digit, i) in digits"
      :key="i"
      :ref="(el) => { if (el) cells[i] = el as HTMLInputElement }"
      class="cell"
      :class="{ invalid }"
      :value="digit"
      inputmode="numeric"
      autocomplete="one-time-code"
      maxlength="6"
      :disabled="disabled"
      :aria-label="t('signup.codeDigit', { n: i + 1 })"
      @input="onInput(i, $event)"
      @paste="onPaste(i, $event)"
      @keydown="onKeydown(i, $event)"
      @focus="($event.target as HTMLInputElement).select()"
    />
  </div>
</template>

<style scoped>
.code { display: flex; gap: 10px; justify-content: space-between; }
.cell { width: 52px; height: 60px; border: 2px solid transparent; border-radius: var(--dm-radius-md); background: var(--dm-surface-2); color: var(--dm-ink); text-align: center; font: inherit; font-size: 26px; font-weight: 500; font-variant-numeric: tabular-nums; outline: none; box-sizing: border-box; }
.cell:focus { border-color: var(--dm-primary); background: var(--dm-surface); }
.cell.invalid { border-color: var(--dm-danger); }
@media (max-width: 420px) { .cell { width: 44px; height: 52px; font-size: 22px; } }
</style>

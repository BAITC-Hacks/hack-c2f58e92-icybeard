<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ApiError } from '@/api/client'
import { admin } from '@/api/endpoints'
import type { RoleInfo } from '@/api/types'
import ErrorBox from '@/components/ErrorBox.vue'
import { roleTitle, type Titled } from '@/lib/labels'

/** «Создать роль» / «Дублировать роль»: ключ (латиница, как realm role в Keycloak), названия RU/KK, описание и роль-образец
 * (copyFrom — её разрешения копируются). POST /admin/roles. */
const props = defineProps<{ roles: RoleInfo[]; copyFrom?: string | null; roleCatalog: Record<string, Titled> }>()
const visible = defineModel<boolean>('visible', { default: false })
const emit = defineEmits<{ created: [string] }>()
const { t } = useI18n()

const key = ref('')
const titleRu = ref('')
const titleKk = ref('')
const descriptionRu = ref('')
const source = ref<string | null>(null)
const touched = ref(false)
const saving = ref(false)
const error = ref<unknown>(null)

watch(visible, (open) => {
  if (!open) return
  key.value = props.copyFrom ? `${props.copyFrom}_copy` : ''
  titleRu.value = props.copyFrom ? `${roleTitle(props.copyFrom, props.roleCatalog)} (${t('admin.roles.copySuffix')})` : ''
  titleKk.value = ''
  descriptionRu.value = ''
  source.value = props.copyFrom ?? null
  touched.value = false
  error.value = null
})

const sourceOptions = computed(() => props.roles.filter((r) => r.key !== 'admin').map((r) => ({ value: r.key, label: roleTitle(r.key, props.roleCatalog) })))
const fieldError = (name: string) => (error.value instanceof ApiError ? error.value.field(name) : undefined)
const errors = computed(() => ({
  key: !/^[a-z][a-z0-9_]{2,31}$/.test(key.value) ? t('admin.roles.keyRule') : props.roles.some((r) => r.key === key.value) ? t('admin.roles.keyTaken') : fieldError('key'),
  titleRu: !titleRu.value.trim() ? t('validation.required') : fieldError('titleRu'),
  titleKk: !titleKk.value.trim() ? t('validation.required') : fieldError('titleKk'),
}))

async function create() {
  touched.value = true
  if (Object.values(errors.value).some(Boolean)) return
  saving.value = true
  error.value = null
  try {
    await admin.createRole({ key: key.value, titleRu: titleRu.value.trim(), titleKk: titleKk.value.trim(), descriptionRu: descriptionRu.value.trim() || undefined, copyFrom: source.value ?? undefined })
    emit('created', key.value)
    visible.value = false
  } catch (e) {
    error.value = e
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog v-model:visible="visible" modal :header="copyFrom ? t('admin.roles.duplicateTitle') : t('admin.roles.createTitle')" :style="{ width: 'min(520px, 94vw)' }" data-testid="role-dialog">
    <form class="form-col" novalidate @submit.prevent="create">
      <div class="field"><label for="r-key">{{ t('admin.roles.key') }}</label><InputText id="r-key" v-model="key" class="mono" placeholder="bed_manager" :invalid="touched && !!errors.key" /><span v-if="touched && errors.key" class="error">{{ errors.key }}</span><span v-else class="caption">{{ t('admin.roles.keyHint') }}</span></div>
      <div class="field"><label for="r-ru">{{ t('admin.roles.titleRu') }}</label><InputText id="r-ru" v-model="titleRu" :invalid="touched && !!errors.titleRu" /><span v-if="touched && errors.titleRu" class="error">{{ errors.titleRu }}</span></div>
      <div class="field"><label for="r-kk">{{ t('admin.roles.titleKk') }}</label><InputText id="r-kk" v-model="titleKk" :invalid="touched && !!errors.titleKk" /><span v-if="touched && errors.titleKk" class="error">{{ errors.titleKk }}</span></div>
      <div class="field"><label for="r-desc">{{ t('admin.roles.description') }}</label><Textarea id="r-desc" v-model="descriptionRu" rows="3" auto-resize /><span class="caption">{{ t('admin.roles.descriptionHint') }}</span></div>
      <div class="field"><label for="r-from">{{ t('admin.roles.copyFrom') }}</label><Select id="r-from" v-model="source" :options="sourceOptions" option-label="label" option-value="value" show-clear :placeholder="t('admin.roles.emptyRole')" /><span class="caption">{{ t('admin.roles.copyFromHint') }}</span></div>
      <ErrorBox v-if="!(error instanceof ApiError && error.status === 422)" :error="error" />
      <button type="submit" hidden />
    </form>
    <template #footer>
      <Button :label="t('common.cancel')" severity="secondary" @click="visible = false" />
      <Button :label="copyFrom ? t('admin.roles.duplicate') : t('admin.roles.create')" :loading="saving" data-testid="role-create-submit" @click="create" />
    </template>
  </Dialog>
</template>

import { ref, type Ref } from 'vue'

/** Загрузка данных страницы: значение, признак загрузки и ошибка (для AsyncState / StateError), повтор — run().
 * Ответ устаревшего запроса (фильтр или выбор строки уже сменились) отбрасывается: побеждает последний run(). */
export function useAsync<T>(loader: () => Promise<T>, initial: T | null = null) {
  const data = ref(initial) as Ref<T | null>
  const loading = ref(false)
  const error = ref<unknown>(null)
  let latest = 0
  async function run(): Promise<T | null> {
    const request = ++latest
    loading.value = true
    error.value = null
    try {
      const result = await loader()
      if (request === latest) data.value = result
      return result
    } catch (e) {
      if (request === latest) error.value = e
      return null
    } finally {
      if (request === latest) loading.value = false
    }
  }
  return { data, loading, error, run }
}

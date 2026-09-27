import { describe, expect, it } from 'vitest'
import { useAsync } from '@/composables/useAsync'

describe('useAsync', () => {
  it('keeps the result of the latest run when an older request resolves later', async () => {
    const resolvers: ((value: string) => void)[] = []
    const state = useAsync<string>(() => new Promise((resolve) => resolvers.push(resolve)))
    const first = state.run()
    const second = state.run()
    resolvers[1]!('new')
    await second
    resolvers[0]!('old')
    await first
    expect(state.data.value).toBe('new')
    expect(state.loading.value).toBe(false)
  })

  it('exposes the error of the latest run', async () => {
    const state = useAsync<string>(() => Promise.reject(new Error('404')))
    await state.run()
    expect(state.error.value).toBeInstanceOf(Error)
    expect(state.data.value).toBeNull()
  })
})

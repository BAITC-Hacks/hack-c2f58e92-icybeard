import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { journal } from '@/api/endpoints'
import { useIncomingReferrals } from '@/composables/useIncomingReferrals'
import { useAuthStore } from '@/stores/auth'

describe('useIncomingReferrals', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.restoreAllMocks()
  })

  it('asks for the incoming referrals of the user\'s own organisation', async () => {
    // на базах, где у врача охват worklist.view ещё «all», сервер без moCode отвечает 422 «Нужна организация»
    const list = vi.spyOn(journal, 'referralsIncoming').mockResolvedValue([])
    useAuthStore().moCode = '028B'

    await useIncomingReferrals().load()

    expect(list).toHaveBeenCalledWith(expect.objectContaining({ moCode: '028B' }))
  })

  it('a picked organisation wins over the own one; without either no organisation is sent', async () => {
    const list = vi.spyOn(journal, 'referralsIncoming').mockResolvedValue([])
    const incoming = useIncomingReferrals()

    await incoming.load()
    expect(list).toHaveBeenLastCalledWith(expect.objectContaining({ moCode: undefined }))

    useAuthStore().moCode = '028B'
    incoming.moCode.value = '22GN'
    await incoming.load()
    expect(list).toHaveBeenLastCalledWith(expect.objectContaining({ moCode: '22GN' }))
  })
})

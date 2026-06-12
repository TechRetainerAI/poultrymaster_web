'use client'

import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ReactNode, useEffect, useState } from 'react'
import { useAuthStore } from '@/lib/store/auth-store'
import { useFarmSettingsStore } from '@/lib/currency'

interface QueryProviderProps {
  children: ReactNode
}

export function QueryProvider({ children }: QueryProviderProps) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // With SSR, we usually want to set some default staleTime
            // above 0 to avoid refetching immediately on the client
            staleTime: 60 * 1000, // 1 minute
            refetchOnWindowFocus: false,
            retry: 1,
          },
        },
      })
  )

  // Currency settings live on the Farms row. Load them once per active farm
  // so every page that calls fmtMoney() sees the right symbol/code without
  // needing its own fetch. The load is a no-op when no farm is active or the
  // settings for the current farm are already in the persisted store.
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const loadSettings = useFarmSettingsStore((s) => s.load)
  useEffect(() => {
    if (activeFarmId) void loadSettings(false)
  }, [activeFarmId, loadSettings])

  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
}

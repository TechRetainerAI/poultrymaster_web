'use client'

import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ReactNode, useEffect, useState } from 'react'
import { useAuthStore } from '@/lib/store/auth-store'
import { useFarmSettingsStore } from '@/lib/currency'
import { getCompanyTimeContext } from '@/lib/api/company-time'
import { cacheCompanyTimeZone } from '@/lib/utils/company-datetime'

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

  // The company's timezone, cached for the same reason and in the same shape as
  // the currency above: every table calls fmtDateTime() to render a date and
  // time, and that is a plain function -- it also runs inside CSV and PDF export
  // helpers, where a React hook cannot be used. Warming the cache here once per
  // active farm means no page needs its own fetch.
  //
  // Until this lands the formatters fall back to UTC, which is what the values
  // are stored in and is also the correct zone for 83 of the 84 companies on
  // this database -- so a slow or failed load degrades quietly rather than
  // showing the wrong time.
  useEffect(() => {
    if (!activeFarmId) return
    let cancelled = false
    getCompanyTimeContext()
      .then((c) => {
        if (!cancelled) cacheCompanyTimeZone(activeFarmId, c.timeZoneId)
      })
      .catch(() => {
        /* keep the UTC fallback */
      })
    return () => {
      cancelled = true
    }
  }, [activeFarmId])

  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
}

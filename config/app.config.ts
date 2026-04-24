import { DEFAULT_FARM_API_ORIGIN } from '@/lib/api/default-api-hosts'

export const appConfig = {
  api: {
    baseURL: process.env.NEXT_PUBLIC_API_BASE_URL && (process.env.NEXT_PUBLIC_API_BASE_URL.startsWith('http://') || process.env.NEXT_PUBLIC_API_BASE_URL.startsWith('https://'))
      ? process.env.NEXT_PUBLIC_API_BASE_URL
      : (process.env.NEXT_PUBLIC_API_BASE_URL ? `https://${process.env.NEXT_PUBLIC_API_BASE_URL}` : DEFAULT_FARM_API_ORIGIN),
    timeout: 30000,
  },
  app: {
    name: 'Poultry Master',
    version: '1.0.0',
    description: 'Farm Management System',
  },
  /** Product team contact (Talk to Poultry Master). Override with NEXT_PUBLIC_SUPPORT_EMAIL. */
  support: {
    email:
      (typeof process !== 'undefined' && process.env.NEXT_PUBLIC_SUPPORT_EMAIL?.trim()) ||
      'techretainer@gmail.com',
  },
  features: {
    enableAnalytics: process.env.NEXT_PUBLIC_ENABLE_ANALYTICS === 'true',
    enablePWA: process.env.NEXT_PUBLIC_ENABLE_PWA === 'true',
  },
  pagination: {
    defaultPageSize: 10,
    maxPageSize: 100,
  },
  cache: {
    defaultTTL: 5 * 60 * 1000, // 5 minutes
  },
} as const

export type AppConfig = typeof appConfig

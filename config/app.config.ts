export const appConfig = {
  api: {
    baseURL: process.env.NEXT_PUBLIC_API_BASE_URL && (process.env.NEXT_PUBLIC_API_BASE_URL.startsWith('http://') || process.env.NEXT_PUBLIC_API_BASE_URL.startsWith('https://'))
      ? process.env.NEXT_PUBLIC_API_BASE_URL
      : (process.env.NEXT_PUBLIC_API_BASE_URL ? `https://${process.env.NEXT_PUBLIC_API_BASE_URL}` : 'https://farmapi.techretainer.com'),
    timeout: 30000,
  },
  app: {
    name: 'Poultry Master',
    version: '1.0.0',
    description: 'Farm Management System',
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

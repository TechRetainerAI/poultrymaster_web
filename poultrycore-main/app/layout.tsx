import type { Metadata } from 'next'
import { GeistSans } from 'geist/font/sans'
import { GeistMono } from 'geist/font/mono'
import { Analytics } from '@vercel/analytics/next'
import { QueryProvider } from '@/components/providers/query-provider'
import { StoreHydration } from '@/components/providers/store-hydration'
import { FloatingChatWidget } from '@/components/chat/floating-chat-widget'
import { SubscriptionGuard } from '@/components/auth/subscription-guard'
import { WaterAccessGuard } from '@/components/auth/water-access-guard'
import { HotelAccessGuard } from '@/components/auth/hotel-access-guard'
import { Toaster } from '@/components/ui/toaster'
import './globals.css'

export const metadata: Metadata = {
  title: 'VisibilityCore',
  description: 'Farm Management System',
  generator: 'VisibilityCore',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  const enableVercelAnalytics = process.env.NEXT_PUBLIC_ENABLE_ANALYTICS === 'true'

  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`font-sans ${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
        <QueryProvider>
          <StoreHydration />
          <SubscriptionGuard />
          <WaterAccessGuard />
          <HotelAccessGuard />
          {children}
          <FloatingChatWidget />
          <Toaster />
        </QueryProvider>
        {enableVercelAnalytics ? <Analytics /> : null}
      </body>
    </html>
  )
}

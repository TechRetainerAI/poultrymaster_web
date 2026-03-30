import type { Metadata } from 'next'
import { GeistSans } from 'geist/font/sans'
import { GeistMono } from 'geist/font/mono'
import { Analytics } from '@vercel/analytics/next'
import { QueryProvider } from '@/components/providers/query-provider'
import { FloatingChatWidget } from '@/components/chat/floating-chat-widget'
import { Toaster } from '@/components/ui/toaster'
import './globals.css'

export const metadata: Metadata = {
  title: 'Poultry Master',
  description: 'Farm Management System',
  generator: 'Poultry Master',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en">
      <body className={`font-sans ${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
        <QueryProvider>
          {children}
          <FloatingChatWidget />
          <Toaster />
        </QueryProvider>
        <Analytics />
      </body>
    </html>
  )
}

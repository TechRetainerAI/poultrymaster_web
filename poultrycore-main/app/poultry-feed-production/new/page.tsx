"use client"

import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { FeedProductionBatchForm } from "@/components/feed-production/batch-form"

export default function NewFeedProductionBatchPage() {
  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6">
          <FeedProductionBatchForm />
        </main>
      </div>
    </div>
  )
}

import { Skeleton } from "@/components/ui/skeleton"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"

export function StatCardSkeleton() {
  return (
    <div className="border rounded-lg border-l-4 border-l-gray-200 p-4 flex items-center gap-3">
      <Skeleton className="h-9 w-9 rounded-lg" />
      <div className="space-y-1.5">
        <Skeleton className="h-6 w-16" />
        <Skeleton className="h-3 w-24" />
      </div>
    </div>
  )
}

export function ListSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="border rounded-lg p-4 flex items-center gap-4">
          <Skeleton className="h-10 w-10 rounded-full" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-4 w-1/3" />
            <Skeleton className="h-3 w-1/2" />
          </div>
          <Skeleton className="h-6 w-16 rounded-full" />
        </div>
      ))}
    </div>
  )
}

export function PageSkeleton({ statCards = 4, listRows = 5 }: { statCards?: number; listRows?: number }) {
  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            {/* Header skeleton */}
            <div className="flex items-center gap-3">
              <Skeleton className="h-10 w-10 rounded-lg" />
              <div className="space-y-1.5">
                <Skeleton className="h-7 w-48" />
                <Skeleton className="h-4 w-64" />
              </div>
            </div>
            {/* Stat cards skeleton */}
            <div className={`grid grid-cols-2 md:grid-cols-${statCards} gap-4`}>
              {Array.from({ length: statCards }).map((_, i) => (
                <StatCardSkeleton key={i} />
              ))}
            </div>
            {/* List skeleton */}
            <div className="border rounded-lg p-4">
              <ListSkeleton rows={listRows} />
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}

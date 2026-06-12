"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { DollarSign, Boxes, Feather, ListChecks, Egg, HeartPulse, ShoppingCart, Loader2 } from "lucide-react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useAlertsStore } from "@/lib/store/alerts-store"
import { getProductionRecords } from "@/lib/api/production-record"
import { getSales } from "@/lib/api/sale"
import { getExpenses } from "@/lib/api/expense"
import { getHealthRecords } from "@/lib/api/health"
import { getUserContext } from "@/lib/utils/user-context"

interface ActivityItem {
  id: string
  type: "production" | "sale" | "expense" | "health"
  description: string
  date: Date
  detail?: string
}

export function DashboardCharts() {
  const router = useRouter()
  const alertsOpen = useAlertsStore(s => s.isOpen)
  const openAlerts = useAlertsStore(s => s.open)
  const closeAlerts = useAlertsStore(s => s.close)
  const alerts = useAlertsStore(s => s.alerts)

  const [activities, setActivities] = useState<ActivityItem[]>([])
  const [loadingActivities, setLoadingActivities] = useState(true)

  useEffect(() => {
    loadRecentActivity()
  }, [])

  const loadRecentActivity = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setLoadingActivities(false)
      return
    }

    try {
      const [prodRes, salesRes, expRes, healthRes] = await Promise.all([
        getProductionRecords(userId, farmId).catch(() => ({ success: false, data: [] })),
        getSales(userId, farmId).catch(() => ({ success: false, data: [] })),
        getExpenses(userId, farmId).catch(() => ({ success: false, data: [] })),
        getHealthRecords(userId, farmId).catch(() => ({ success: false, data: [] })),
      ])

      const items: ActivityItem[] = []

      // Production records
      if (prodRes.success && prodRes.data) {
        for (const r of (prodRes.data as any[]).slice(0, 20)) {
          const eggs = r.totalProduction || 0
          items.push({
            id: `prod-${r.id}`,
            type: "production",
            description: `Logged ${eggs.toLocaleString()} eggs${r.flockName ? ` (${r.flockName})` : ""}`,
            date: new Date(r.createdAt || r.date),
            detail: r.mortality ? `${r.mortality} mortality` : undefined,
          })
        }
      }

      // Sales
      if (salesRes.success && salesRes.data) {
        for (const s of (salesRes.data as any[]).slice(0, 20)) {
          items.push({
            id: `sale-${s.saleId}`,
            type: "sale",
            description: `Sold ${s.quantity} ${s.product || "items"} to ${s.customerName || "customer"}`,
            date: new Date(s.createdDate || s.saleDate),
            detail: s.totalAmount ? `GHS ${Number(s.totalAmount).toLocaleString(undefined, { minimumFractionDigits: 2 })}` : undefined,
          })
        }
      }

      // Expenses
      if (expRes.success && expRes.data) {
        for (const e of (expRes.data as any[]).slice(0, 20)) {
          items.push({
            id: `exp-${e.expenseId}`,
            type: "expense",
            description: `${e.category || "Expense"}: ${e.description || ""}`.trim(),
            date: new Date(e.createdDate || e.expenseDate),
            detail: e.amount ? `GHS ${Number(e.amount).toLocaleString(undefined, { minimumFractionDigits: 2 })}` : undefined,
          })
        }
      }

      // Health records
      if (healthRes.success && healthRes.data) {
        for (const h of (healthRes.data as any[]).slice(0, 20)) {
          const action = h.vaccination ? `Vaccination: ${h.vaccination}` : h.medication ? `Medication: ${h.medication}` : "Health check"
          items.push({
            id: `health-${h.id}`,
            type: "health",
            description: action,
            date: new Date(h.recordDate),
            detail: h.notes || undefined,
          })
        }
      }

      // Sort by date descending and take the most recent 10
      items.sort((a, b) => b.date.getTime() - a.date.getTime())
      setActivities(items.slice(0, 10))
    } catch (err) {
      console.error("[Dashboard] Error loading recent activity:", err)
    }
    setLoadingActivities(false)
  }

  const getActivityIcon = (type: ActivityItem["type"]) => {
    switch (type) {
      case "production": return <Egg className="w-4 h-4 text-amber-600" />
      case "sale": return <ShoppingCart className="w-4 h-4 text-green-600" />
      case "expense": return <DollarSign className="w-4 h-4 text-red-500" />
      case "health": return <HeartPulse className="w-4 h-4 text-blue-600" />
    }
  }

  const getActivityColor = (type: ActivityItem["type"]) => {
    switch (type) {
      case "production": return "bg-amber-50 border-amber-200"
      case "sale": return "bg-green-50 border-green-200"
      case "expense": return "bg-red-50 border-red-200"
      case "health": return "bg-blue-50 border-blue-200"
    }
  }

  const formatTimeAgo = (date: Date) => {
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMs / 3600000)
    const diffDays = Math.floor(diffMs / 86400000)

    if (diffMins < 1) return "Just now"
    if (diffMins < 60) return `${diffMins}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    if (diffDays < 7) return `${diffDays}d ago`
    return date.toLocaleDateString()
  }

  return (
    <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
      {/* Recent Activity */}
      <Card className="bg-white">
        <CardHeader>
          <CardTitle className="text-lg font-semibold">Recent Activity</CardTitle>
        </CardHeader>
        <CardContent>
          {loadingActivities ? (
            <div className="h-48 flex items-center justify-center text-slate-400">
              <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading activity...
            </div>
          ) : activities.length === 0 ? (
            <div className="h-48 flex items-center justify-center text-slate-500">
              No recent activity to display
            </div>
          ) : (
            <div className="space-y-2 max-h-[320px] overflow-y-auto pr-1">
              {activities.map((a) => (
                <div
                  key={a.id}
                  className={`flex items-start gap-3 rounded-lg border p-2.5 ${getActivityColor(a.type)}`}
                >
                  <div className="mt-0.5">{getActivityIcon(a.type)}</div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-slate-800 leading-snug truncate">{a.description}</p>
                    {a.detail && (
                      <p className="text-xs text-slate-500 mt-0.5 truncate">{a.detail}</p>
                    )}
                  </div>
                  <span className="text-xs text-slate-400 whitespace-nowrap">{formatTimeAgo(a.date)}</span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Quick Actions */}
      <Card className="bg-white">
        <CardHeader>
          <CardTitle className="text-lg font-semibold">Quick Actions</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Log Production */}
            <Button
              className="h-16 justify-between bg-green-800 hover:bg-green-900 text-white"
              onClick={() => router.push("/production-records/new")}
            >
              <span className="text-xl font-semibold">0</span>
              <span className="mx-auto">Log Production</span>
              <ListChecks className="h-5 w-5 opacity-70" />
            </Button>

            {/* Record Sale */}
            <Button
              className="h-16 justify-between bg-orange-500 hover:bg-orange-600 text-white"
              onClick={() => router.push("/sales")}
            >
              <DollarSign className="h-5 w-5 opacity-90" />
              <span className="mx-auto">Record Sale</span>
              <span className="w-5" />
            </Button>

            {/* Update Inventory */}
            <Button
              className="h-16 justify-between bg-sky-500 hover:bg-sky-600 text-white"
              onClick={() => router.push("/expenses")}
            >
              <Boxes className="h-5 w-5 opacity-90" />
              <span className="mx-auto">Update Expenses</span>
              <span className="w-5" />
            </Button>

            {/* Add Flock */}
            <Button
              className="h-16 justify-between bg-slate-100 hover:bg-slate-200 text-slate-800"
              onClick={() => router.push("/flocks/new")}
              variant="outline"
            >
              <Feather className="h-5 w-5 opacity-90" />
              <span className="mx-auto">Add Flock</span>
              <span className="w-5" />
            </Button>
          </div>
          {/* Alerts / Notifications */}
          <div className="mt-4">
            <Button
              variant="outline"
              className="w-full h-12 justify-center"
              onClick={openAlerts}
            >
              View system alerts and notifications
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Alerts Dialog */}
      <Dialog open={alertsOpen} onOpenChange={(v) => v ? openAlerts() : closeAlerts()}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>System Alerts and Notifications</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            {alerts.length === 0 ? (
              <div className="text-slate-600">No alerts</div>
            ) : (
              alerts.map(a => (
                <div key={a.id} className="rounded border p-3">
                  <div className="font-medium text-slate-900">{a.title}</div>
                  {a.description && <div className="text-sm text-slate-600">{a.description}</div>}
                  {a.time && <div className="text-xs text-slate-500 mt-1">{a.time}</div>}
                </div>
              ))
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
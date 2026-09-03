"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Bell, CheckCircle2, AlertTriangle, Info, XCircle, Settings, Filter } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { PageHeader } from "@/components/restaurant/page-header"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listNotifications,
  markNotificationRead,
  markAllNotificationsRead,
  getNotificationSettings,
  upsertNotificationSettings,
  type RestaurantNotification,
  type NotificationSettings,
} from "@/lib/api/restaurant"

function severityIcon(severity: string) {
  switch (severity?.toLowerCase()) {
    case "warning":
      return <AlertTriangle className="h-5 w-5 text-amber-500 shrink-0" />
    case "error":
      return <XCircle className="h-5 w-5 text-red-500 shrink-0" />
    case "success":
      return <CheckCircle2 className="h-5 w-5 text-green-500 shrink-0" />
    default:
      return <Info className="h-5 w-5 text-blue-500 shrink-0" />
  }
}

function timeAgo(dateStr: string): string {
  const now = Date.now()
  const then = new Date(dateStr).getTime()
  const diff = Math.max(0, now - then)
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return "Just now"
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d ago`
  return new Date(dateStr).toLocaleDateString()
}

export default function RestaurantNotificationsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [notifications, setNotifications] = useState<RestaurantNotification[]>([])
  const [unreadOnly, setUnreadOnly] = useState(false)
  const [savingSettings, setSavingSettings] = useState(false)
  const [settings, setSettings] = useState<Partial<NotificationSettings>>({
    newOrderAlerts: true,
    lowStockAlerts: true,
    reservationAlerts: true,
    kpiAlerts: true,
    shiftReminders: false,
    emailEnabled: true,
    smsEnabled: false,
    pushEnabled: false,
  })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") {
      router.replace("/dashboard")
      return
    }
  }, [activeFarmType, router])

  useEffect(() => {
    loadNotifications()
  }, [])

  async function loadNotifications() {
    try {
      setLoading(true)
      const data = await listNotifications()
      setNotifications(data)
    } catch {
      toast({ title: "Error", description: "Failed to load notifications", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  async function loadSettings() {
    try {
      const s = await getNotificationSettings()
      setSettings(s)
    } catch {
      // Settings may not exist yet; keep defaults
    }
  }

  async function handleMarkAllRead() {
    try {
      await markAllNotificationsRead()
      setNotifications((prev) => prev.map((n) => ({ ...n, isRead: true })))
      toast({ title: "Done", description: "All notifications marked as read" })
    } catch {
      toast({ title: "Error", description: "Failed to mark all as read", variant: "destructive" })
    }
  }

  async function handleMarkRead(id: number) {
    try {
      await markNotificationRead(id)
      setNotifications((prev) =>
        prev.map((n) => (n.notificationId === id ? { ...n, isRead: true } : n))
      )
    } catch {
      // silent
    }
  }

  async function handleSaveSettings() {
    try {
      setSavingSettings(true)
      await upsertNotificationSettings(settings)
      toast({ title: "Saved", description: "Notification preferences updated" })
    } catch {
      toast({ title: "Error", description: "Failed to save settings", variant: "destructive" })
    } finally {
      setSavingSettings(false)
    }
  }

  const unreadCount = notifications.filter((n) => !n.isRead).length
  const displayedNotifications = unreadOnly
    ? notifications.filter((n) => !n.isRead)
    : notifications

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-5xl mx-auto space-y-6">
            <PageHeader
              icon={Bell}
              title="Notifications & Alerts"
              subtitle="Stay on top of orders, stock, and operations"
            >
              <Button
                variant="outline"
                onClick={handleMarkAllRead}
                disabled={unreadCount === 0}
              >
                Mark All Read
              </Button>
            </PageHeader>

            <Tabs
              defaultValue="all"
              className="space-y-4"
              onValueChange={(v) => {
                if (v === "settings") loadSettings()
              }}
            >
              <TabsList className="bg-white border shadow-sm">
                <TabsTrigger
                  value="all"
                  className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"
                >
                  <Bell className="h-4 w-4 mr-2" />
                  All
                  {unreadCount > 0 && (
                    <Badge className="ml-2 bg-rose-600 text-white text-xs px-1.5 py-0">
                      {unreadCount}
                    </Badge>
                  )}
                </TabsTrigger>
                <TabsTrigger
                  value="settings"
                  className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"
                >
                  <Settings className="h-4 w-4 mr-2" />
                  Settings
                </TabsTrigger>
              </TabsList>

              {/* ─── ALL TAB ─── */}
              <TabsContent value="all">
                <Card>
                  <CardContent className="pt-6 space-y-3">
                    {/* Unread filter toggle */}
                    <div className="flex items-center justify-end mb-2">
                      <Button
                        size="sm"
                        variant={unreadOnly ? "default" : "outline"}
                        className={unreadOnly ? "bg-rose-600 hover:bg-rose-700" : ""}
                        onClick={() => setUnreadOnly(!unreadOnly)}
                      >
                        <Filter className="h-4 w-4 mr-1" />
                        {unreadOnly ? "Showing Unread" : "Show Unread Only"}
                      </Button>
                    </div>

                    {displayedNotifications.length === 0 ? (
                      <EmptyState
                        icon={Bell}
                        title="No notifications"
                        description={
                          unreadOnly
                            ? "You're all caught up! No unread notifications."
                            : "You're all caught up! Alerts will appear here for orders, low stock, and more."
                        }
                      />
                    ) : (
                      <div className="space-y-2">
                        {displayedNotifications.map((n) => (
                          <div
                            key={n.notificationId}
                            onClick={() => !n.isRead && handleMarkRead(n.notificationId)}
                            className={`relative flex items-start gap-3 p-4 rounded-lg border cursor-pointer transition-colors hover:bg-gray-50 ${
                              !n.isRead ? "bg-blue-50/60 border-blue-100" : "bg-white"
                            }`}
                          >
                            {/* Unread dot */}
                            {!n.isRead && (
                              <span className="absolute left-1.5 top-1/2 -translate-y-1/2 h-2 w-2 rounded-full bg-blue-500" />
                            )}

                            <div className="mt-0.5">{severityIcon(n.severity)}</div>

                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2 flex-wrap">
                                <h4
                                  className={`text-sm ${
                                    !n.isRead ? "font-bold text-gray-900" : "font-medium text-gray-700"
                                  }`}
                                >
                                  {n.title}
                                </h4>
                                <Badge variant="outline" className="text-xs">
                                  {n.type}
                                </Badge>
                              </div>
                              <p className="text-sm text-muted-foreground mt-0.5">{n.message}</p>
                            </div>

                            <span className="text-xs text-muted-foreground whitespace-nowrap shrink-0">
                              {timeAgo(n.createdAt)}
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* ─── SETTINGS TAB ─── */}
              <TabsContent value="settings">
                <Card>
                  <CardHeader>
                    <CardTitle className="text-lg">Notification Preferences</CardTitle>
                    <CardDescription>Choose which alerts you receive and how</CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-5">
                    {/* Alert toggles */}
                    <div className="space-y-3">
                      {[
                        {
                          key: "newOrderAlerts" as const,
                          label: "New Order Alerts",
                          desc: "Get notified when a new order is placed",
                        },
                        {
                          key: "lowStockAlerts" as const,
                          label: "Low Stock Alerts",
                          desc: "Alert when ingredients fall below reorder point",
                        },
                        {
                          key: "reservationAlerts" as const,
                          label: "Reservation Reminders",
                          desc: "Upcoming reservation notifications",
                        },
                        {
                          key: "kpiAlerts" as const,
                          label: "KPI Threshold Alerts",
                          desc: "Alert when food cost or other KPIs exceed thresholds",
                        },
                        {
                          key: "shiftReminders" as const,
                          label: "Shift Reminders",
                          desc: "Notify staff before their shift starts",
                        },
                      ].map((item) => (
                        <div
                          key={item.key}
                          className="flex items-center justify-between p-3 border rounded-lg"
                        >
                          <div>
                            <h4 className="font-medium text-sm">{item.label}</h4>
                            <p className="text-xs text-muted-foreground">{item.desc}</p>
                          </div>
                          <Switch
                            checked={!!settings[item.key]}
                            onCheckedChange={(checked) =>
                              setSettings((prev) => ({ ...prev, [item.key]: checked }))
                            }
                          />
                        </div>
                      ))}
                    </div>

                    {/* Delivery channels */}
                    <div className="border-t pt-4">
                      <h4 className="font-medium text-sm mb-3">Delivery Channels</h4>
                      <div className="space-y-3">
                        {[
                          {
                            key: "emailEnabled" as const,
                            label: "Email",
                            desc: "Receive notifications via email",
                          },
                          {
                            key: "smsEnabled" as const,
                            label: "SMS",
                            desc: "Receive notifications via text message",
                          },
                          {
                            key: "pushEnabled" as const,
                            label: "Push",
                            desc: "Receive browser push notifications",
                          },
                        ].map((ch) => (
                          <div
                            key={ch.key}
                            className="flex items-center justify-between p-3 border rounded-lg"
                          >
                            <div>
                              <h4 className="font-medium text-sm">{ch.label}</h4>
                              <p className="text-xs text-muted-foreground">{ch.desc}</p>
                            </div>
                            <Switch
                              checked={!!settings[ch.key]}
                              onCheckedChange={(checked) =>
                                setSettings((prev) => ({ ...prev, [ch.key]: checked }))
                              }
                            />
                          </div>
                        ))}
                      </div>
                    </div>

                    <Button
                      className="bg-rose-600 hover:bg-rose-700"
                      onClick={handleSaveSettings}
                      disabled={savingSettings}
                    >
                      {savingSettings ? "Saving..." : "Save Preferences"}
                    </Button>
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>
    </div>
  )
}

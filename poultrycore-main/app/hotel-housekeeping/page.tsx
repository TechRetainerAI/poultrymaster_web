"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Sparkles } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHousekeepingTasks, updateHousekeepingStatus, type HotelHousekeepingTask, type HotelHousekeepingStatus } from "@/lib/api/hotel"

const PRIORITY_COLOR: Record<string, string> = { Low: "bg-slate-100 text-slate-700", Normal: "bg-blue-100 text-blue-700", High: "bg-amber-100 text-amber-700", Urgent: "bg-red-100 text-red-700" }
const STATUS_COLOR: Record<string, string> = { Pending: "bg-slate-100 text-slate-700", InProgress: "bg-blue-100 text-blue-700", Completed: "bg-emerald-100 text-emerald-700", Inspected: "bg-violet-100 text-violet-700", Failed: "bg-red-100 text-red-700" }
const STATUSES: HotelHousekeepingStatus[] = ["Pending", "InProgress", "Completed", "Inspected"]

export default function HotelHousekeepingPage() {
  const router = useRouter(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType); const logout = useLogout()
  const [tasks, setTasks] = useState<HotelHousekeepingTask[]>([]); const [loading, setLoading] = useState(true)
  const [filterStatus, setFilterStatus] = useState("all")

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setTasks(await listHousekeepingTasks()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function changeStatus(task: HotelHousekeepingTask, status: HotelHousekeepingStatus) {
    try { await updateHousekeepingStatus(task.hotelHousekeepingTaskId, status); toast({ title: `Task updated to ${status}` }); await load() }
    catch (e: any) { toast({ title: "Update failed", description: e?.message, variant: "destructive" }) }
  }

  const filtered = tasks.filter((t) => filterStatus === "all" || t.status === filterStatus)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3"><Sparkles className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Housekeeping</h1></div>
            <Select value={filterStatus} onValueChange={setFilterStatus}><SelectTrigger className="w-[160px]"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all">All</SelectItem>{STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent></Select>
          </div>
          {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {STATUSES.map((status) => {
                const col = filtered.filter((t) => filterStatus === "all" ? t.status === status : true)
                if (filterStatus !== "all" && filterStatus !== status) return null
                return (
                  <div key={status}>
                    <h3 className="font-semibold text-sm text-slate-500 mb-3 uppercase">{status} ({col.length})</h3>
                    <div className="space-y-3">
                      {col.map((t) => (
                        <Card key={t.hotelHousekeepingTaskId}>
                          <CardContent className="p-4 space-y-2">
                            <div className="flex items-center justify-between"><span className="font-bold">Room {t.roomNumber}</span><Badge variant="outline" className={PRIORITY_COLOR[t.priority]}>{t.priority}</Badge></div>
                            <div className="text-sm text-slate-500">{t.taskType}</div>
                            {t.assignedTo && <div className="text-xs text-slate-400">Assigned: {t.assignedTo}</div>}
                            <div className="flex gap-1 flex-wrap">
                              {STATUSES.filter((s) => s !== t.status).map((s) => (
                                <Button key={s} variant="outline" size="sm" className="text-xs" onClick={() => changeStatus(t, s)}>{s}</Button>
                              ))}
                            </div>
                          </CardContent>
                        </Card>
                      ))}
                    </div>
                  </div>
                )
              })}
              {filtered.length === 0 && <div className="col-span-full text-center py-12 text-slate-400">No housekeeping tasks.</div>}
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

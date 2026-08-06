"use client"

import React, { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { CalendarDays, Plus, Loader2, Eye, Pencil, Trash2, Undo2, CheckCircle2, Layers } from "lucide-react"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { usePermissions } from "@/hooks/use-permissions"
import {
  listWaterDailyProductions, deleteWaterDailyProduction, postWaterDailyProduction,
  reverseWaterDailyProduction, setWaterDailyProductionStatus, deleteWaterDailyProductionAllocation,
  WATER_DAILY_PRODUCTION_STATUS_LABELS, waterMachineScopeLabel,
  type WaterDailyProduction,
} from "@/lib/api/water"

const STATUS_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  PendingAllocation: "bg-amber-100 text-amber-800",
  Allocated: "bg-blue-100 text-blue-700",
  Posted: "bg-emerald-100 text-emerald-700",
  Reversed: "bg-purple-100 text-purple-700",
  Cancelled: "bg-red-100 text-red-700",
}

type ConfirmState = {
  type: "delete" | "post" | "reverse" | "repost" | "cancel" | "deleteAllocation"
  id: number
  title: string
  description: string
  actionLabel: string
  destructive?: boolean
}

export default function WaterDailyProductionPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const permissions = usePermissions()

  const [rows, setRows] = useState<WaterDailyProduction[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)

  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [status, setStatus] = useState<string>("all")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      setRows(await listWaterDailyProductions())
    } catch (e: any) {
      toast({ title: "Failed to load batch production", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  const filtered = useMemo(() => {
    const byDate = filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      dateKey: "productionDate",
      searchKeys: ["productionNumber", "productName", "notes"],
    } as any)
    return status === "all" ? byDate : byDate.filter((r: WaterDailyProduction) => r.status === status)
  }, [rows, search, dateFrom, dateTo, status])

  const totals = useMemo(() => ({
    days: filtered.length,
    bags: filtered.reduce((s, r) => s + (r.bagsProduced || 0), 0),
    good: filtered.reduce((s, r) => s + (r.goodBags || 0), 0),
    pending: filtered.filter((r) => r.status === "PendingAllocation").length,
    posted: filtered.filter((r) => r.status === "Posted").length,
  }), [filtered])

  function ask(next: ConfirmState) { setConfirm(next) }

  async function runConfirm() {
    if (!confirm) return
    setBusy(true)
    try {
      switch (confirm.type) {
        case "delete": await deleteWaterDailyProduction(confirm.id); break
        case "post":
        case "repost": await postWaterDailyProduction(confirm.id); break
        case "reverse": await reverseWaterDailyProduction(confirm.id); break
        case "cancel": await setWaterDailyProductionStatus(confirm.id, "Cancelled"); break
        case "deleteAllocation": await deleteWaterDailyProductionAllocation(confirm.id); break
      }
      toast({ title: `${confirm.actionLabel} done` })
      setConfirm(null)
      await load()
    } catch (e: any) {
      toast({ title: `${confirm.actionLabel} failed`, description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  function renderActions(r: WaterDailyProduction) {
    const id = r.waterDailyProductionId
    const view = (
      <Button key="v" variant="ghost" size="sm" asChild>
        <Link href={`/water-daily-production/${id}`}><Eye className="w-4 h-4" /></Link>
      </Button>
    )
    const edit = (
      <Button key="e" variant="ghost" size="sm" asChild>
        <Link href={`/water-daily-production/${id}/edit`}><Pencil className="w-4 h-4" /></Link>
      </Button>
    )
    const allocate = (
      <Button key="a" variant="ghost" size="sm" asChild title="Allocate across machines">
        <Link href={`/water-daily-production/${id}/allocate`}><Layers className="w-4 h-4 text-blue-600" /></Link>
      </Button>
    )
    const del = permissions.canDelete ? (
      <Button key="d" variant="ghost" size="sm" title="Delete"
        onClick={() => ask({
          type: "delete", id, title: "Delete this batch production record?",
          description: "The day's totals, machine list and allocation will be removed. This cannot be undone.",
          actionLabel: "Delete", destructive: true,
        })}>
        <Trash2 className="w-4 h-4 text-red-600" />
      </Button>
    ) : null
    const post = (
      <Button key="p" variant="ghost" size="sm" title="Post"
        onClick={() => ask({
          type: "post", id, title: "Post this day's production?",
          description: "One production record is created and approved per machine. Finished goods, raw material lots, expenses and losses are all updated.",
          actionLabel: "Post",
        })}>
        <CheckCircle2 className="w-4 h-4 text-emerald-600" />
      </Button>
    )
    const repost = (
      <Button key="rp" variant="ghost" size="sm" title="Repost"
        onClick={() => ask({
          type: "repost", id, title: "Repost this day's production?",
          description: "Fresh production records are created and approved for each machine, at a new posting version.",
          actionLabel: "Repost",
        })}>
        <CheckCircle2 className="w-4 h-4 text-emerald-600" />
      </Button>
    )
    const reverse = (
      <Button key="rv" variant="ghost" size="sm" title="Reverse"
        onClick={() => ask({
          type: "reverse", id, title: "Reverse this day's production?",
          description: "Each machine's production record is reopened and cancelled: finished goods come back out of stock, raw material lots are restored, linked expenses are cancelled. The day stays available to re-allocate and repost.",
          actionLabel: "Reverse", destructive: true,
        })}>
        <Undo2 className="w-4 h-4 text-purple-600" />
      </Button>
    )

    switch (r.status) {
      case "Draft": return [edit, del]
      case "PendingAllocation": return [edit, allocate, del]
      case "Allocated": return [allocate, post, del]
      case "Posted": return [view, reverse]
      case "Reversed": return [view, allocate, repost, del]
      default: return [view]
    }
  }

  if (loading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="p-6 flex items-center gap-2 text-slate-500">
            <Loader2 className="w-4 h-4 animate-spin" /> Loading batch production…
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                <CalendarDays className="h-5 w-5 text-sky-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-semibold text-slate-900 truncate">Batch production</h1>
                <p className="text-xs sm:text-sm text-slate-500">
                  Record the day&apos;s totals, then split them across the machines that produced them.
                </p>
              </div>
            </div>
            <Button onClick={() => router.push("/water-daily-production/new")}>
              <Plus className="w-4 h-4 mr-1" /> Log batch production
            </Button>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
            {[
              { label: "Days", value: totals.days.toLocaleString() },
              { label: "Bags produced", value: totals.bags.toLocaleString() },
              { label: "Good bags", value: totals.good.toLocaleString() },
              { label: "Pending allocation", value: totals.pending.toLocaleString() },
              { label: "Posted", value: totals.posted.toLocaleString() },
            ].map((t) => (
              <Card key={t.label}>
                <CardContent className="p-3">
                  <div className="text-xs text-slate-500">{t.label}</div>
                  <div className="text-lg font-semibold tabular-nums text-slate-900">{t.value}</div>
                </CardContent>
              </Card>
            ))}
          </div>

          <Card className="mb-4">
            <CardContent className="p-3">
              <ListFilters
                search={search} setSearch={setSearch}
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
                searchPlaceholder="Search by document number, product or notes"
                extras={
                  <select
                    value={status} onChange={(e) => setStatus(e.target.value)}
                    className="h-9 rounded-md border border-slate-200 bg-white px-2 text-sm"
                  >
                    <option value="all">All statuses</option>
                    {Object.entries(WATER_DAILY_PRODUCTION_STATUS_LABELS).map(([k, v]) => (
                      <option key={k} value={k}>{v}</option>
                    ))}
                  </select>
                }
              />
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-0 overflow-x-auto">
              {filtered.length === 0 ? (
                <div className="p-8 text-center text-sm text-slate-500">
                  No batch production records yet. Log the day&apos;s totals to get started.
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Document</TableHead>
                      <TableHead>Product</TableHead>
                      <TableHead>Machines</TableHead>
                      <TableHead className="text-right">Bags</TableHead>
                      <TableHead className="text-right">Good</TableHead>
                      <TableHead className="text-right">Rejected</TableHead>
                      <TableHead className="text-right">All-in cost</TableHead>
                      <TableHead className="text-right">Cost/bag</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((r) => (
                      <TableRow key={r.waterDailyProductionId}>
                        <TableCell className="whitespace-nowrap">{(r.productionDate || "").slice(0, 10)}</TableCell>
                        <TableCell className="font-medium">{r.productionNumber || `#${r.waterDailyProductionId}`}</TableCell>
                        <TableCell>{r.productName ?? "—"}</TableCell>
                        <TableCell className="text-xs text-slate-600">{waterMachineScopeLabel(r)}</TableCell>
                        <TableCell className="text-right tabular-nums">{(r.bagsProduced || 0).toLocaleString()}</TableCell>
                        <TableCell className="text-right tabular-nums">{(r.goodBags || 0).toLocaleString()}</TableCell>
                        <TableCell className="text-right tabular-nums">{(r.rejectedSachets || 0).toLocaleString()}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(r.allInCost || 0)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(r.costPerBag || 0)}</TableCell>
                        <TableCell>
                          <Badge variant="outline" className={cn("border-0", STATUS_BADGE[r.status])}>
                            {WATER_DAILY_PRODUCTION_STATUS_LABELS[r.status] ?? r.status}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right whitespace-nowrap">{renderActions(r)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <AlertDialog open={!!confirm} onOpenChange={(open) => { if (!open && !busy) setConfirm(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{confirm?.title}</AlertDialogTitle>
            <AlertDialogDescription>{confirm?.description}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => { e.preventDefault(); void runConfirm() }}
              disabled={busy}
              className={cn(confirm?.destructive && "bg-red-600 hover:bg-red-700 focus:ring-red-600")}
            >
              {busy ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Working…</> : confirm?.actionLabel}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

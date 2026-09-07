"use client"

/**
 * Production Losses (migration 067 / prompt #5).
 *
 * Loss records are auto-created when a Production record is approved with
 * DamagedBags > 0 or RejectedSachets > 0. The same records get a cancellation
 * when the production record is reopened. This page is read-only — record
 * management happens via the production record.
 */

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, TrendingDown, Eye } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { listWaterProductionLosses, type WaterProductionLoss } from "@/lib/api/water"

const STATUS_COLORS: Record<string, string> = {
  Approved: "bg-rose-100 text-rose-800",
  Cancelled: "bg-slate-100 text-slate-700",
  Draft: "bg-slate-100 text-slate-700",
}

export default function WaterProductionLossesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  const [losses, setLosses] = useState<WaterProductionLoss[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [busy, setBusy] = useState(true)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setBusy(true)
    try { setLosses(await listWaterProductionLosses()) }
    catch (e: any) { toast({ title: "Could not load losses", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setBusy(false) }
  }

  const visible = useMemo(() =>
    filterByDateAndSearch(losses, {
      search, dateFrom, dateTo,
      searchKeys: ["batchNumber", "productName", "lossType", "reason"],
      dateKey: "lossDate",
    }), [losses, search, dateFrom, dateTo])

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visible)

  // Roll-up of "Approved" losses for the cards (Cancelled rows are reopened
  // and shouldn't count towards money lost).
  const totals = useMemo(() => {
    const approved = losses.filter(l => l.status === "Approved")
    const totalValue = approved.reduce((s, l) => s + (l.totalValue ?? 0), 0)
    const totalBags = approved.reduce((s, l) => s + l.bagsLost, 0)
    const totalSachets = approved.reduce((s, l) => s + l.sachetsLost, 0)
    return { totalValue, totalBags, totalSachets, count: approved.length }
  }, [losses])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-rose-100 rounded-lg flex items-center justify-center">
                <TrendingDown className="h-5 w-5 text-rose-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-semibold text-slate-900 truncate">Production losses</h1>
                <p className="text-xs sm:text-sm text-slate-500">
                  Damaged bags / rejected sachets auto-recorded on production approval.
                </p>
              </div>
            </div>
          </div>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Records</div><div className="text-xl font-semibold tabular-nums">{totals.count}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Bags lost</div><div className="text-xl font-semibold tabular-nums">{totals.totalBags.toLocaleString()}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Sachets lost</div><div className="text-xl font-semibold tabular-nums">{totals.totalSachets.toLocaleString()}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total value</div><div className="text-xl font-semibold tabular-nums text-rose-700">{gh(totals.totalValue)}</div></CardContent></Card>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search batch number, product, type or reason"
          />

          <Card>
            <CardContent className="p-0">
              {busy ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : losses.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No production losses recorded yet.</div>
              ) : (
                <MobileCardList
                  striped
                  defaultOpen
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(l) => l.waterProductionLossId}
                  primary={(l) => `${l.batchNumber ?? `#${l.sourceId}`} · ${l.productName ?? "—"}`}
                  secondary={(l) => (
                    <>
                      <span>{l.lossDate?.split("T")[0]}</span>
                      <Badge className={STATUS_COLORS[l.status] ?? ""}>{l.status}</Badge>
                    </>
                  )}
                  highlights={(l) => [
                    { label: "Bags lost", value: l.bagsLost.toLocaleString(), accent: "rose" },
                    { label: "Sachets lost", value: l.sachetsLost.toLocaleString(), accent: "rose" },
                    { label: "Total value", value: gh(l.totalValue), accent: "violet", wide: true },
                  ]}
                  details={(l) => [
                    { label: "Type", value: l.lossType },
                    { label: "Bags value", value: gh(l.bagsLossValue) },
                    { label: "Sachets value", value: gh(l.sachetsLossValue) },
                  ]}
                  actions={(l) => (
                    <>
                      {l.sourceType === "ProductionBatch" && l.sourceId ? (
                        <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                          <Link href={`/water-production-batches/${l.sourceId}`}>
                            <Eye className="h-4 w-4 mr-1" /> View batch
                          </Link>
                        </Button>
                      ) : null}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Batch</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead>Type</TableHead>
                            <TableHead className="text-right">Bags</TableHead>
                            <TableHead className="text-right">Sachets</TableHead>
                            <TableHead className="text-right">Total value</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((l) => (
                            <TableRow key={l.waterProductionLossId}>
                              <TableCell className="whitespace-nowrap">{l.lossDate?.split("T")[0]}</TableCell>
                              <TableCell>{l.batchNumber ?? `#${l.sourceId}`}</TableCell>
                              <TableCell className="max-w-[180px] truncate">{l.productName ?? "—"}</TableCell>
                              <TableCell>{l.lossType}</TableCell>
                              <TableCell className="text-right tabular-nums">{l.bagsLost.toLocaleString()}</TableCell>
                              <TableCell className="text-right tabular-nums">{l.sachetsLost.toLocaleString()}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold whitespace-nowrap">{gh(l.totalValue)}</TableCell>
                              <TableCell><Badge className={STATUS_COLORS[l.status] ?? ""}>{l.status}</Badge></TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                {l.sourceType === "ProductionBatch" && l.sourceId ? (
                                  <Button asChild size="sm" variant="ghost" title="View batch">
                                    <Link href={`/water-production-batches/${l.sourceId}`}><Eye className="h-4 w-4" /></Link>
                                  </Button>
                                ) : null}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}

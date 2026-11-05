"use client"

// Generic Stock Movements — shows all inventory movements (purchases, sales,
// adjustments, internal use, losses) for all products across a date range.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, sortData, type SortDirection } from "@/components/ui/sortable-header"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Boxes, TrendingUp, TrendingDown, ArrowUpDown, Download } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { getStockMovements, type GenericStockMovement } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { exportTableToPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

const DEFAULT = defaultReportRange()

const MOVE_COLORS: Record<string, string> = {
  Purchase: "bg-blue-100 text-blue-700",
  Sale: "bg-emerald-100 text-emerald-700",
  Adjustment: "bg-slate-100 text-slate-700",
  AdjustmentUp: "bg-green-100 text-green-700",
  AdjustmentDown: "bg-amber-100 text-amber-700",
  InternalUse: "bg-amber-100 text-amber-700",
  "Internal Use": "bg-amber-100 text-amber-700",
  Loss: "bg-red-100 text-red-700",
  Damage: "bg-red-100 text-red-700",
  "Damage/Loss": "bg-red-100 text-red-700",
  OpeningStock: "bg-slate-200 text-slate-800",
  "Opening Stock": "bg-slate-200 text-slate-800",
  Return: "bg-violet-100 text-violet-700",
  Transfer: "bg-indigo-100 text-indigo-700",
  Reversal: "bg-slate-200 text-slate-800",
}
const MOVE_COLOR_FALLBACK = "bg-slate-200 text-slate-800"

export default function GenericStockMovementsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [rows, setRows] = useState<GenericStockMovement[]>([])
  const [loading, setLoading] = useState(true)
  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [search, setSearch] = useState("")
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [sortKey, setSortKey] = useState<string>("date")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const data = await getStockMovements(dateFrom, dateTo)
      setRows(data)
    } catch (e: any) {
      toast({ title: "Could not load stock movements", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const typeOptions = useMemo(() => {
    const seen = new Set<string>()
    for (const r of rows) seen.add(r.movementType)
    return [...seen].sort()
  }, [rows])

  const totals = useMemo(() => {
    let inQty = 0, outQty = 0, inVal = 0, outVal = 0
    for (const r of rows) {
      if (r.quantity > 0) { inQty += r.quantity; inVal += (r.totalCostValue ?? 0) }
      else { outQty += Math.abs(r.quantity); outVal += Math.abs(r.totalCostValue ?? 0) }
    }
    return { inQty, outQty, inVal, outVal, netQty: inQty - outQty }
  }, [rows])

  const filtered = useMemo(() => {
    let data = rows
    if (typeFilter !== "ALL") data = data.filter((r) => r.movementType === typeFilter)
    return filterByDateAndSearch(data, {
      search,
      searchKeys: ["productName", "movementType", "reason", "notes"],
      dateKey: "movementDate",
    })
  }, [rows, typeFilter, search])

  const sorted = useMemo(
    () => sortData(filtered, sortKey, sortDir, (item: any, key: string) => {
      switch (key) {
        case "date": return new Date(item.movementDate).getTime()
        case "product": return item.productName ?? ""
        case "type": return item.movementType
        case "qty": return item.quantity
        case "cost": return item.totalCostValue ?? 0
        default: return item[key]
      }
    }),
    [filtered, sortKey, sortDir],
  )

  const pg = usePagination(sorted)

  function doExport() {
    const opts: PdfExportOptions = {
      title: "Stock Movements",
      subtitle: `${dateFrom} to ${dateTo}`,
      columns: [
        { header: "Date", key: "movementDate", width: 70 },
        { header: "Product", key: "productName", width: 120 },
        { header: "Type", key: "movementType", width: 70 },
        { header: "Qty", key: "quantity", width: 50, align: "right" },
        { header: "Unit Cost", key: "unitCost", width: 60, align: "right", format: "currency" },
        { header: "Total", key: "totalCostValue", width: 70, align: "right", format: "currency" },
        { header: "Reason", key: "reason", width: 100 },
      ],
      rows: sorted.map((r) => ({
        ...r,
        movementDate: fmtDateTime(r.movementDate, r),
      })),
    }
    exportTableToPdf(opts)
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">

          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <ArrowUpDown className="h-5 w-5 text-emerald-600" /> Stock Movements
              </h1>
              <p className="text-xs text-slate-500">
                Every inventory change — purchases, sales, adjustments, internal use, and losses.
              </p>
            </div>
            <Button size="sm" variant="outline" onClick={doExport} disabled={loading || sorted.length === 0}>
              <Download className="h-4 w-4 mr-1" /> Export PDF
            </Button>
          </div>

          {/* KPI tiles */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
                <TrendingUp className="h-3.5 w-3.5" /> Stock In
              </div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{totals.inQty.toLocaleString()} units</div>
              <div className="text-xs text-slate-500">{gh(totals.inVal)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
                <TrendingDown className="h-3.5 w-3.5" /> Stock Out
              </div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-red-700">{totals.outQty.toLocaleString()} units</div>
              <div className="text-xs text-slate-500">{gh(totals.outVal)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
                <Boxes className="h-3.5 w-3.5" /> Net Change
              </div>
              <div className={cn("mt-1 text-lg font-semibold tabular-nums", totals.netQty >= 0 ? "text-emerald-700" : "text-red-700")}>
                {totals.netQty >= 0 ? "+" : ""}{totals.netQty.toLocaleString()} units
              </div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
                <ArrowUpDown className="h-3.5 w-3.5" /> Movements
              </div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-slate-900">{rows.length}</div>
              <div className="text-xs text-slate-500">in period</div>
            </CardContent></Card>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchPlaceholder="Search product, type, reason…"
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
          />

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading stock movements…</CardContent></Card>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">No stock movements in this period.</CardContent></Card>
          ) : (
            <Card>
              <CardHeader className="pb-2">
                <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
                  <div>
                    <CardTitle className="text-base">Movement History</CardTitle>
                    <CardDescription className="text-xs">{sorted.length} movement(s)</CardDescription>
                  </div>
                  <Select value={typeFilter} onValueChange={setTypeFilter}>
                    <SelectTrigger className="h-8 w-full sm:w-[12rem]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All types</SelectItem>
                      {typeOptions.map((t) => (
                        <SelectItem key={t} value={t}>{t}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </CardHeader>
              <CardContent className="p-0 md:p-2">
                <MobileCardList
                  defaultOpen
                  striped
                  stripeAccent="blue"
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r: any) => r.genericStockMovementId}
                  primary={(r: any) => r.productName ?? `Product #${r.genericProductId}`}
                  secondary={(r: any) => fmtDateTime(r.movementDate, r)}
                  trailing={(r: any) => (
                    <Badge className={MOVE_COLORS[r.movementType] ?? MOVE_COLOR_FALLBACK}>
                      {r.movementType}
                    </Badge>
                  )}
                  highlights={(r: any) => [
                    {
                      label: r.quantity >= 0 ? "In" : "Out",
                      value: `${r.quantity >= 0 ? "+" : ""}${r.quantity}`,
                      accent: r.quantity >= 0 ? "emerald" : "rose",
                    },
                    ...(r.totalCostValue != null ? [{ label: "Value", value: gh(Math.abs(r.totalCostValue)), accent: "blue" as const }] : []),
                  ]}
                  details={(r: any) => [
                    { label: "Type", value: r.movementType },
                    { label: "Unit cost", value: r.unitCost != null ? gh(r.unitCost) : "—" },
                    { label: "Reason", value: r.reason ?? "—" },
                    { label: "Notes", value: r.notes ?? "—" },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            {([
                              ["date", "Date", ""],
                              ["product", "Product", ""],
                              ["type", "Type", ""],
                              ["qty", "Qty", "text-right [&>div]:justify-end"],
                              ["cost", "Value", "text-right [&>div]:justify-end"],
                            ] as const).map(([key, label, cls]) => (
                              <SortableHeader
                                key={key}
                                label={label}
                                sortKey={key}
                                currentSort={sortKey}
                                currentDirection={sortDir}
                                onSort={(k) => {
                                  if (k === sortKey) setSortDir(sortDir === "asc" ? "desc" : "asc")
                                  else { setSortKey(k); setSortDir("asc") }
                                }}
                                className={cls}
                              />
                            ))}
                            <TableHead>Reason / Notes</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r: any) => (
                            <TableRow key={r.genericStockMovementId}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(r.movementDate, r)}</TableCell>
                              <TableCell className="font-medium">{r.productName ?? `#${r.genericProductId}`}</TableCell>
                              <TableCell>
                                <Badge className={MOVE_COLORS[r.movementType] ?? MOVE_COLOR_FALLBACK}>
                                  {r.movementType}
                                </Badge>
                              </TableCell>
                              <TableCell className={cn("text-right tabular-nums font-medium", r.quantity >= 0 ? "text-emerald-700" : "text-red-600")}>
                                {r.quantity >= 0 ? "+" : ""}{r.quantity}
                              </TableCell>
                              <TableCell className="text-right tabular-nums">
                                {r.totalCostValue != null ? gh(Math.abs(r.totalCostValue)) : "—"}
                              </TableCell>
                              <TableCell className="max-w-xs whitespace-normal break-words text-sm text-slate-600">
                                {r.reason ?? r.notes ?? "—"}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

"use client"

// Product Tracker — shows the complete stock history for a single product,
// including every movement (purchases, sales, adjustments, internal use, losses)
// with a running balance, so you can see how stock went up and down over time.

import { useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Suspense } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  ArrowLeft, Boxes, TrendingUp, TrendingDown, ArrowUpDown, Download, Package, History,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getStockMovements, getProducts,
  type GenericStockMovement, type GenericProduct,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { exportTableToPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

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
  ManualMovement: "bg-purple-100 text-purple-700",
}
const MOVE_COLOR_FALLBACK = "bg-slate-200 text-slate-800"

function ProductTrackerInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [allMovements, setAllMovements] = useState<GenericStockMovement[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  // Selected product — from URL or first product
  const urlProductId = searchParams.get("productId")
  const [selectedProductId, setSelectedProductId] = useState<string>(urlProductId ?? "")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [movements, prods] = await Promise.all([
        getStockMovements(),  // All movements, no date filter — we want full history
        getProducts(),
      ])
      setAllMovements(movements)
      setProducts(prods)
      // Auto-select from URL or first product
      if (urlProductId) {
        setSelectedProductId(urlProductId)
      } else if (prods.length > 0 && !selectedProductId) {
        setSelectedProductId(String(prods[0].genericProductId))
      }
    } catch (e: any) {
      toast({ title: "Could not load product data", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const selectedProduct = useMemo(
    () => products.find((p) => String(p.genericProductId) === selectedProductId),
    [products, selectedProductId],
  )

  // Filter movements for selected product, sorted by date ascending for running balance
  const productMovements = useMemo(() => {
    if (!selectedProductId) return []
    let moves = allMovements
      .filter((m) => String(m.genericProductId) === selectedProductId)
      .sort((a, b) => new Date(a.movementDate).getTime() - new Date(b.movementDate).getTime())

    // Apply date filters
    if (dateFrom) moves = moves.filter((m) => m.movementDate >= dateFrom)
    if (dateTo) moves = moves.filter((m) => m.movementDate <= dateTo + "T23:59:59")

    return filterByDateAndSearch(moves, {
      search,
      searchKeys: ["movementType", "reason", "notes"],
    })
  }, [allMovements, selectedProductId, dateFrom, dateTo, search])

  // Compute running balance
  const movementsWithBalance = useMemo(() => {
    let balance = selectedProduct?.openingStock ?? 0
    // First compute balance up to the start of our filtered window
    if (dateFrom && selectedProductId) {
      const before = allMovements
        .filter((m) => String(m.genericProductId) === selectedProductId && m.movementDate < dateFrom)
        .sort((a, b) => new Date(a.movementDate).getTime() - new Date(b.movementDate).getTime())
      for (const m of before) balance += m.quantity
    }
    return productMovements.map((m) => {
      balance += m.quantity
      return { ...m, runningBalance: balance }
    })
  }, [productMovements, selectedProduct, allMovements, selectedProductId, dateFrom])

  const totals = useMemo(() => {
    let inQty = 0, outQty = 0
    for (const m of productMovements) {
      if (m.quantity > 0) inQty += m.quantity
      else outQty += Math.abs(m.quantity)
    }
    return { inQty, outQty, netChange: inQty - outQty }
  }, [productMovements])

  const pg = usePagination(movementsWithBalance)

  function doExport() {
    if (!selectedProduct) return
    const opts: PdfExportOptions = {
      title: `Product Tracker: ${selectedProduct.productName}`,
      subtitle: dateFrom || dateTo ? `${dateFrom || "start"} to ${dateTo || "now"}` : "Full history",
      columns: [
        { header: "Date", key: "date", width: 70 },
        { header: "Type", key: "movementType", width: 70 },
        { header: "In", key: "in", width: 50, align: "right" },
        { header: "Out", key: "out", width: 50, align: "right" },
        { header: "Balance", key: "runningBalance", width: 60, align: "right" },
        { header: "Reason", key: "reason", width: 120 },
      ],
      rows: movementsWithBalance.map((m) => ({
        date: fmtDateTime(m.movementDate, m),
        movementType: m.movementType,
        in: m.quantity > 0 ? `+${m.quantity}` : "",
        out: m.quantity < 0 ? String(m.quantity) : "",
        runningBalance: m.runningBalance,
        reason: m.reason ?? m.notes ?? "",
      })),
    }
    exportTableToPdf(opts)
  }

  function onProductChange(val: string) {
    setSelectedProductId(val)
    // Update URL without navigation
    const url = new URL(window.location.href)
    url.searchParams.set("productId", val)
    window.history.replaceState({}, "", url.toString())
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back"><ArrowLeft className="w-5 h-5 text-slate-600" /></button>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
                <History className="h-6 w-6 text-emerald-600" /> Product Tracker
              </h1>
              <p className="text-xs text-slate-500">
                Track the complete history of a product — every movement, with a running stock balance.
              </p>
            </div>
            <Button size="sm" variant="outline" onClick={doExport}
                    disabled={loading || movementsWithBalance.length === 0 || !selectedProduct}>
              <Download className="h-4 w-4 mr-1" /> Export PDF
            </Button>
          </div>

          {/* Product selector */}
          <Card>
            <CardContent className="pt-6">
              <div className="flex flex-col sm:flex-row gap-3">
                <div className="flex-1 min-w-[250px]">
                  <Select value={selectedProductId} onValueChange={onProductChange}>
                    <SelectTrigger className="h-10">
                      <SelectValue placeholder="Select a product to track" />
                    </SelectTrigger>
                    <SelectContent>
                      {products.map((p) => (
                        <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                          <span className="flex items-center gap-2">
                            <Package className="h-4 w-4 text-slate-400" />
                            {p.productName}
                            <span className="text-xs text-slate-500">
                              ({p.currentStock} in stock)
                            </span>
                          </span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <ListFilters
                  search={search} setSearch={setSearch}
                  searchPlaceholder="Search type, reason…"
                  dateFrom={dateFrom} setDateFrom={setDateFrom}
                  dateTo={dateTo} setDateTo={setDateTo}
                />
              </div>
            </CardContent>
          </Card>

          {selectedProduct && (
            <>
              {/* Product info + KPI tiles */}
              <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
                <Card><CardContent className="p-3">
                  <div className="text-[11px] uppercase tracking-wide text-slate-500">Current Stock</div>
                  <div className="mt-1 text-xl font-bold tabular-nums text-slate-900">
                    {selectedProduct.currentStock.toLocaleString()}
                  </div>
                  <div className="text-xs text-slate-500">{selectedProduct.unitOfMeasure ?? "units"}</div>
                </CardContent></Card>
                <Card><CardContent className="p-3">
                  <div className="text-[11px] uppercase tracking-wide text-slate-500">Opening Stock</div>
                  <div className="mt-1 text-xl font-bold tabular-nums text-slate-600">
                    {selectedProduct.openingStock.toLocaleString()}
                  </div>
                </CardContent></Card>
                <Card><CardContent className="p-3">
                  <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
                    <TrendingUp className="h-3.5 w-3.5" /> Total In
                  </div>
                  <div className="mt-1 text-xl font-bold tabular-nums text-emerald-700">
                    +{totals.inQty.toLocaleString()}
                  </div>
                </CardContent></Card>
                <Card><CardContent className="p-3">
                  <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
                    <TrendingDown className="h-3.5 w-3.5" /> Total Out
                  </div>
                  <div className="mt-1 text-xl font-bold tabular-nums text-red-700">
                    −{totals.outQty.toLocaleString()}
                  </div>
                </CardContent></Card>
                <Card><CardContent className="p-3">
                  <div className="text-[11px] uppercase tracking-wide text-slate-500">
                    {selectedProduct.currentStock <= selectedProduct.minimumStockAlert ? "⚠ Low Stock" : "Stock Status"}
                  </div>
                  <div className={cn(
                    "mt-1 text-xl font-bold",
                    selectedProduct.currentStock <= selectedProduct.minimumStockAlert ? "text-red-600" : "text-emerald-700",
                  )}>
                    {selectedProduct.currentStock <= selectedProduct.minimumStockAlert ? "Low" : "OK"}
                  </div>
                  <div className="text-xs text-slate-500">Min: {selectedProduct.minimumStockAlert}</div>
                </CardContent></Card>
              </div>

              {/* Product details card */}
              <Card>
                <CardContent className="p-4">
                  <div className="flex flex-wrap gap-4 text-sm">
                    <div><span className="text-slate-500">SKU:</span> <span className="font-medium">{selectedProduct.sku ?? "—"}</span></div>
                    <div><span className="text-slate-500">Category:</span> <span className="font-medium">{selectedProduct.categoryName ?? "—"}</span></div>
                    <div><span className="text-slate-500">Cost:</span> <span className="font-medium">{gh(selectedProduct.costPrice)}</span></div>
                    <div><span className="text-slate-500">Selling:</span> <span className="font-medium">{gh(selectedProduct.sellingPrice)}</span></div>
                    <div><span className="text-slate-500">Value at cost:</span> <span className="font-medium">{gh(selectedProduct.currentStock * selectedProduct.costPrice)}</span></div>
                    {selectedProduct.expiryDate && (
                      <div><span className="text-slate-500">Expiry:</span> <span className="font-medium">{selectedProduct.expiryDate.slice(0, 10)}</span></div>
                    )}
                  </div>
                </CardContent>
              </Card>
            </>
          )}

          {/* Movement history */}
          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading product history…</CardContent></Card>
          ) : !selectedProduct ? (
            <Card><CardContent className="py-12 text-center text-slate-500">Select a product above to see its stock history.</CardContent></Card>
          ) : movementsWithBalance.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">No stock movements found for this product.</CardContent></Card>
          ) : (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Stock History</CardTitle>
                <CardDescription className="text-xs">
                  {movementsWithBalance.length} movement(s) · showing running balance
                </CardDescription>
              </CardHeader>
              <CardContent className="p-0 md:p-2">
                <MobileCardList
                  defaultOpen
                  striped
                  stripeAccent="blue"
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r: any) => r.genericStockMovementId}
                  primary={(r: any) => r.movementType}
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
                    { label: "Balance", value: String(r.runningBalance), accent: "blue" },
                  ]}
                  details={(r: any) => [
                    { label: "Reason", value: r.reason ?? "—" },
                    { label: "Notes", value: r.notes ?? "—" },
                    { label: "Unit cost", value: r.unitCost != null ? gh(r.unitCost) : "—" },
                    { label: "Total value", value: r.totalCostValue != null ? gh(Math.abs(r.totalCostValue)) : "—" },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Type</TableHead>
                            <TableHead className="text-right">In</TableHead>
                            <TableHead className="text-right">Out</TableHead>
                            <TableHead className="text-right font-semibold">Balance</TableHead>
                            <TableHead className="text-right">Value</TableHead>
                            <TableHead>Reason / Notes</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r: any) => (
                            <TableRow key={r.genericStockMovementId}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(r.movementDate, r)}</TableCell>
                              <TableCell>
                                <Badge className={MOVE_COLORS[r.movementType] ?? MOVE_COLOR_FALLBACK}>
                                  {r.movementType}
                                </Badge>
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-emerald-700 font-medium">
                                {r.quantity > 0 ? `+${r.quantity}` : ""}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-red-600 font-medium">
                                {r.quantity < 0 ? String(r.quantity) : ""}
                              </TableCell>
                              <TableCell className={cn(
                                "text-right tabular-nums font-bold",
                                r.runningBalance <= (selectedProduct?.minimumStockAlert ?? 0) ? "text-red-600" : "text-slate-900",
                              )}>
                                {r.runningBalance}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-slate-600">
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

export default function GenericProductTrackerPage() {
  return (
    <Suspense fallback={null}>
      <ProductTrackerInner />
    </Suspense>
  )
}

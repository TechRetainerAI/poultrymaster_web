"use client"

// Generic company inventory page. Mirrors the Water one but simpler — Generic only
// has one inventory stream (products), so this is a single table with cards on top
// and search. Adjustments still go through /generic-stock-adjustments to preserve
// the audit trail (this page is the at-a-glance view).

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Boxes, AlertTriangle, AlertCircle, Loader2, ExternalLink, Filter } from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useFmt } from "@/lib/currency"
import { getProducts, type GenericProduct } from "@/lib/api/generic"
import { ListFilters } from "@/components/ui/list-filters"

function StatCard({ label, value, icon: Icon, accent }: { label: string; value: string | number; icon: any; accent?: "amber" | "rose" | "emerald" }) {
  const colors = accent === "amber" ? "bg-amber-100 text-amber-700"
    : accent === "rose" ? "bg-rose-100 text-rose-700"
    : accent === "emerald" ? "bg-emerald-100 text-emerald-700"
    : "bg-indigo-100 text-indigo-700"
  return (
    <Card>
      <CardContent className="p-4 flex items-center gap-3">
        <div className={`rounded-lg p-2 ${colors}`}><Icon className="h-5 w-5" /></div>
        <div>
          <div className="text-xs text-slate-500">{label}</div>
          <div className="text-2xl font-semibold text-slate-900 tabular-nums">{value}</div>
        </div>
      </CardContent>
    </Card>
  )
}

const STATUS_ALL = "ALL"

export default function GenericInventoryPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const fmtGhc = useFmt()

  const [products, setProducts] = useState<GenericProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [q, setQ] = useState("")
  // James (2026-05-27): filter dropdowns default to "All".
  const [category, setCategory] = useState<string>(STATUS_ALL)
  const [stockStatus, setStockStatus] = useState<string>(STATUS_ALL)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    const load = async () => {
      setLoading(true); setError(null)
      try {
        const data = await getProducts()
        if (!cancelled) setProducts(Array.isArray(data) ? data : [])
      } catch (e: any) {
        if (!cancelled) setError(e?.message ?? String(e))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void load()
    return () => { cancelled = true }
  }, [activeFarmType, router])

  const categories = useMemo(() => {
    const set = new Set<string>()
    for (const p of products) if (p.categoryName) set.add(p.categoryName)
    return Array.from(set).sort()
  }, [products])

  const status = (p: GenericProduct): { label: string; tone: "ok" | "low" | "out" } => {
    if (!p.trackInventory) return { label: "Not tracked", tone: "ok" }
    const s = p.currentStock ?? 0
    const min = p.minimumStockAlert ?? 0
    if (s <= 0) return { label: "Out of stock", tone: "out" }
    if (min > 0 && s <= min) return { label: "Low stock", tone: "low" }
    return { label: "In stock", tone: "ok" }
  }

  const matchesQ = (s?: string | null) => !q || (s ?? "").toLowerCase().includes(q.toLowerCase())

  const filtered = useMemo(() => {
    return products.filter((p) => {
      if (!(matchesQ(p.productName) || matchesQ(p.sku) || matchesQ(p.barcode) || matchesQ(p.categoryName))) return false
      if (category !== STATUS_ALL && p.categoryName !== category) return false
      if (stockStatus !== STATUS_ALL) {
        const t = status(p).tone
        if (stockStatus === "out" && t !== "out") return false
        if (stockStatus === "low" && t !== "low") return false
        if (stockStatus === "ok" && t !== "ok") return false
      }
      return true
    })
  }, [products, q, category, stockStatus])

  const counts = useMemo(() => {
    let total = products.length
    let low = 0
    let out = 0
    let trackedValue = 0  // sum of currentStock * costPrice
    for (const p of products) {
      const t = status(p).tone
      if (t === "low") low++
      else if (t === "out") out++
      if (p.trackInventory) trackedValue += (p.currentStock ?? 0) * (p.costPrice ?? 0)
    }
    return { total, low, out, trackedValue }
  }, [products])

  const ToneBadge = ({ tone, label }: { tone: "ok" | "low" | "out"; label: string }) =>
    tone === "out" ? <Badge className="bg-rose-100 text-rose-700">{label}</Badge>
      : tone === "low" ? <Badge className="bg-amber-100 text-amber-700">{label}</Badge>
      : <Badge className="bg-emerald-100 text-emerald-700">{label}</Badge>

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div className="flex items-center gap-3">
              <div className="rounded-lg bg-indigo-100 p-2"><Boxes className="h-6 w-6 text-indigo-700" /></div>
              <div>
                <h1 className="text-2xl font-semibold text-slate-900">Inventory</h1>
                <p className="text-sm text-slate-600">Stock-on-hand for every tracked product. Adjustments via Stock Adjustments page.</p>
              </div>
            </div>
            <Button asChild variant="outline" className="w-full sm:w-auto h-11 sm:h-10">
              <Link href="/generic-stock-adjustments"><ExternalLink className="h-4 w-4 mr-1" /> Stock adjustments</Link>
            </Button>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <StatCard label="Total products" value={loading ? "…" : counts.total} icon={Boxes} />
            <StatCard label="Low stock" value={loading ? "…" : counts.low} icon={AlertTriangle} accent="amber" />
            <StatCard label="Out of stock" value={loading ? "…" : counts.out} icon={AlertCircle} accent="rose" />
            <StatCard label="Stock value (cost)" value={loading ? "…" : fmtGhc(counts.trackedValue)} icon={Boxes} accent="emerald" />
          </div>

          {/* Filters */}
          <ListFilters
            search={q} setSearch={setQ}
            searchOnly
            searchPlaceholder="Search by name, SKU, barcode, category…"
            extras={
              <>
                <Select value={category} onValueChange={setCategory}>
                  <SelectTrigger className="w-[180px]"><Filter className="h-4 w-4 mr-1" /><SelectValue placeholder="All categories" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={STATUS_ALL}>All categories</SelectItem>
                    {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={stockStatus} onValueChange={setStockStatus}>
                  <SelectTrigger className="w-[160px]"><SelectValue placeholder="All status" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={STATUS_ALL}>All status</SelectItem>
                    <SelectItem value="ok">In stock</SelectItem>
                    <SelectItem value="low">Low stock</SelectItem>
                    <SelectItem value="out">Out of stock</SelectItem>
                  </SelectContent>
                </Select>
                {(category !== STATUS_ALL || stockStatus !== STATUS_ALL) && (
                  <Button variant="ghost" size="sm" onClick={() => { setCategory(STATUS_ALL); setStockStatus(STATUS_ALL) }}>Reset extras</Button>
                )}
              </>
            }
          />

          {error && (
            <Card className="border-rose-200 bg-rose-50">
              <CardContent className="flex items-center gap-2 p-3 text-rose-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : filtered.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  {products.length === 0
                    ? <>No products yet. <Link href="/generic-products" className="text-indigo-600 hover:underline">Add your first product</Link>.</>
                    : "No products match your filters."}
                </div>
              ) : (
                <MobileCardList
                  items={filtered}
                  getKey={(p) => p.genericProductId}
                  primary={(p) => p.productName}
                  secondary={(p) => (
                    <>
                      {p.sku && <span>{p.sku}</span>}
                      {p.categoryName && <><span>·</span><span>{p.categoryName}</span></>}
                    </>
                  )}
                  trailing={(p) => {
                    const st = status(p)
                    return <ToneBadge tone={st.tone} label={st.label} />
                  }}
                  details={(p) => [
                    { label: "SKU", value: p.sku ?? "—" },
                    { label: "Category", value: p.categoryName ?? "—" },
                    { label: "Unit", value: p.unitOfMeasure ?? "—" },
                    { label: "Cost", value: fmtGhc(p.costPrice) },
                    { label: "Selling", value: fmtGhc(p.sellingPrice) },
                    { label: "Stock", value: p.trackInventory ? (p.currentStock ?? 0).toLocaleString() : "n/a" },
                    { label: "Min alert", value: p.trackInventory ? ((p.minimumStockAlert ?? 0).toLocaleString() || "—") : "—" },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Product</TableHead>
                          <TableHead>SKU</TableHead>
                          <TableHead>Category</TableHead>
                          <TableHead>Unit</TableHead>
                          <TableHead className="text-right">Cost</TableHead>
                          <TableHead className="text-right">Selling</TableHead>
                          <TableHead className="text-right">Stock</TableHead>
                          <TableHead className="text-right">Min alert</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {filtered.map((p) => {
                          const st = status(p)
                          return (
                            <TableRow key={p.genericProductId}>
                              <TableCell className="font-medium">{p.productName}</TableCell>
                              <TableCell className="text-slate-600">{p.sku ?? "—"}</TableCell>
                              <TableCell>{p.categoryName ?? "—"}</TableCell>
                              <TableCell>{p.unitOfMeasure ?? "—"}</TableCell>
                              <TableCell className="text-right tabular-nums">{fmtGhc(p.costPrice)}</TableCell>
                              <TableCell className="text-right tabular-nums">{fmtGhc(p.sellingPrice)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">
                                {p.trackInventory ? (p.currentStock ?? 0).toLocaleString() : <span className="text-slate-400">n/a</span>}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-slate-500">
                                {p.trackInventory ? ((p.minimumStockAlert ?? 0).toLocaleString() || "—") : "—"}
                              </TableCell>
                              <TableCell><ToneBadge tone={st.tone} label={st.label} /></TableCell>
                            </TableRow>
                          )
                        })}
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

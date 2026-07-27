"use client"

// Water company inventory page. James asked for a proper Inventory view; we have
// finished products and raw materials, each with their own stock-on-hand counter.
// One page, two tabs, three top cards (total items / low stock / out of stock).
//
// Read-only here on purpose — adjustments go through the dedicated routes
// (/water-products for restock, /water-raw-materials for raw-material purchases)
// so the audit log captures who/what/when. This page is the at-a-glance view.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Boxes, Box, ShoppingBag, AlertTriangle, AlertCircle, Loader2, Search, ExternalLink } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterProducts, listWaterRawMaterialItems, reconcileWaterProductStock,
  type WaterProduct, type WaterRawMaterialItem,
} from "@/lib/api/water"
import { WaterRecalculateStockButton } from "@/components/water/recalculate-stock-button"
import { ReconcileProductStockButton } from "@/components/inventory/reconcile-product-stock-button"
import { useFmt } from "@/lib/currency"

// Anything below this many units triggers a "low stock" badge for finished products.
// Raw materials have their own per-item minimumStockAlert; we use that instead.
const LOW_STOCK_FINISHED_DEFAULT = 50

function StatCard({ label, value, icon: Icon, accent }: { label: string; value: string | number; icon: any; accent?: "amber" | "rose" | "emerald" }) {
  const colors = accent === "amber" ? "bg-amber-100 text-amber-700"
    : accent === "rose" ? "bg-rose-100 text-rose-700"
    : accent === "emerald" ? "bg-emerald-100 text-emerald-700"
    : "bg-sky-100 text-sky-700"
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

export default function WaterInventoryPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const fmtGhc = useFmt()
  const { toast } = useToast()

  const [products, setProducts] = useState<WaterProduct[]>([])
  const [rawItems, setRawItems] = useState<WaterRawMaterialItem[]>([])
  const [loading, setLoading] = useState(true)
  const [q, setQ] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    let cancelled = false
    const load = async () => {
      setLoading(true)
      try {
        const [p, r] = await Promise.all([listWaterProducts(), listWaterRawMaterialItems()])
        if (!cancelled) { setProducts(p); setRawItems(r) }
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load inventory", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void load()
    return () => { cancelled = true }
  }, [activeFarmType, router])

  // Search across finished products + raw materials.
  const matchesQ = (s?: string | null) => !q || (s ?? "").toLowerCase().includes(q.toLowerCase())

  const filteredProducts = useMemo(
    () => products.filter((p) => matchesQ(p.name) || matchesQ(p.sku) || matchesQ(p.unit)),
    [products, q]
  )
  const filteredRaw = useMemo(
    () => rawItems.filter((r) => matchesQ(r.itemName) || matchesQ(r.category) || matchesQ((r as any).unitOfMeasure)),
    [rawItems, q]
  )

  // Status helpers.
  const productStatus = (p: WaterProduct): { label: string; tone: "ok" | "low" | "out" } => {
    const s = p.stockOnHand ?? 0
    if (s <= 0) return { label: "Out of stock", tone: "out" }
    if (s <= LOW_STOCK_FINISHED_DEFAULT) return { label: "Low stock", tone: "low" }
    return { label: "In stock", tone: "ok" }
  }
  const rawStatus = (r: WaterRawMaterialItem): { label: string; tone: "ok" | "low" | "out" } => {
    const s = r.currentQuantity ?? 0
    const min = (r as any).minimumStockAlert ?? 0
    if (s <= 0) return { label: "Out of stock", tone: "out" }
    if (min > 0 && s <= min) return { label: "Low stock", tone: "low" }
    return { label: "In stock", tone: "ok" }
  }

  const counts = useMemo(() => {
    let totalItems = products.length + rawItems.length
    let low = 0
    let out = 0
    for (const p of products) {
      const t = productStatus(p).tone
      if (t === "low") low++
      else if (t === "out") out++
    }
    for (const r of rawItems) {
      const t = rawStatus(r).tone
      if (t === "low") low++
      else if (t === "out") out++
    }
    return { totalItems, low, out }
  }, [products, rawItems])

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
              <div className="rounded-lg bg-sky-100 p-2"><Boxes className="h-6 w-6 text-sky-700" /></div>
              <div>
                <h1 className="text-2xl font-semibold text-slate-900">Water inventory</h1>
                <p className="text-sm text-slate-600">Finished products and raw materials in one place.</p>
              </div>
            </div>
            <div className="flex items-center gap-2 w-full md:w-auto">
              <div className="relative w-full md:w-80">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search by name, SKU, category…" className="pl-9" value={q} onChange={(e) => setQ(e.target.value)} />
              </div>
              <WaterRecalculateStockButton items={rawItems} onDone={async () => setRawItems(await listWaterRawMaterialItems())} />
              <ReconcileProductStockButton products={products.map((p) => ({ id: p.waterProductId, name: p.name }))} reconcile={reconcileWaterProductStock} onDone={async () => setProducts(await listWaterProducts())} />
            </div>
          </div>

          {/* Top stat cards */}
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            <StatCard label="Total items" value={loading ? "…" : counts.totalItems} icon={Boxes} />
            <StatCard label="Low stock" value={loading ? "…" : counts.low} icon={AlertTriangle} accent="amber" />
            <StatCard label="Out of stock" value={loading ? "…" : counts.out} icon={AlertCircle} accent="rose" />
          </div>


          <Tabs defaultValue="products" className="w-full">
            <TabsList className="flex flex-wrap h-auto gap-1 bg-slate-100 p-1">
              <TabsTrigger value="products" className="data-[state=active]:bg-white">
                <ShoppingBag className="h-4 w-4 mr-1.5" /> Finished products
                <Badge variant="secondary" className="ml-2">{filteredProducts.length}</Badge>
              </TabsTrigger>
              <TabsTrigger value="raw" className="data-[state=active]:bg-white">
                <Box className="h-4 w-4 mr-1.5" /> Raw materials
                <Badge variant="secondary" className="ml-2">{filteredRaw.length}</Badge>
              </TabsTrigger>
            </TabsList>

            <TabsContent value="products" className="mt-4">
              <Card>
                <CardContent className="p-0">
                  <div className="flex flex-col gap-2 p-3 border-b bg-slate-50 sm:flex-row sm:items-center sm:justify-between">
                    <div className="min-w-0 text-sm text-slate-600">Sachets, bottles, dispensers. Stock = SUM(WaterStockTransactions).</div>
                    <Button asChild size="sm" variant="outline" className="w-full shrink-0 sm:w-auto">
                      <Link href="/water-products"><ExternalLink className="h-4 w-4 mr-1" /> Manage products</Link>
                    </Button>
                  </div>
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : filteredProducts.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">{q ? "No products match your search." : "No products yet."}</div>
                  ) : (
                    <MobileCardList
                      items={filteredProducts}
                      defaultOpen
                      getKey={(p) => p.waterProductId}
                      primary={(p) => p.name}
                      secondary={(p) => {
                        const st = productStatus(p)
                        return <ToneBadge tone={st.tone} label={st.label} />
                      }}
                      details={(p) => {
                        // Treat unit "sachet" as sachet-bearing even when the
                        // legacy IsSachetProduct flag wasn't set (#10.2).
                        const isSachet = !!p.isSachetProduct || (p.unit ?? "").trim().toLowerCase() === "sachet"
                        const sachetsPerBag = p.sachetsPerBag ?? 30
                        const sachetCount = isSachet ? (p.stockOnHand ?? 0) * sachetsPerBag : null
                        return [
                          { label: "SKU", value: p.sku ?? "—" },
                          { label: "Size", value: p.sizeMl ? `${p.sizeMl} ${p.sizeUnit ?? "ml"}` : "—" },
                          { label: "Unit", value: p.unit ?? "—" },
                          { label: "Unit price", value: fmtGhc(p.unitPrice) },
                          { label: "Stock (Bags)", value: (p.stockOnHand ?? 0).toLocaleString() },
                          { label: "Stock (Sachets)", value: sachetCount !== null ? sachetCount.toLocaleString() : "—" },
                        ]
                      }}
                      desktopTable={
                        <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Name</TableHead>
                              <TableHead>SKU</TableHead>
                              <TableHead>Size</TableHead>
                              <TableHead>Unit</TableHead>
                              <TableHead className="text-right">Unit price</TableHead>
                              <TableHead className="text-right">Stock (Bags)</TableHead>
                              <TableHead className="text-right">Stock (Sachets)</TableHead>
                              <TableHead>Status</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {filteredProducts.map((p) => {
                              const st = productStatus(p)
                              const isSachet = !!p.isSachetProduct || (p.unit ?? "").trim().toLowerCase() === "sachet"
                              const sachetsPerBag = p.sachetsPerBag ?? 30
                              const sachetCount = isSachet ? (p.stockOnHand ?? 0) * sachetsPerBag : null
                              return (
                                <TableRow key={p.waterProductId}>
                                  <TableCell className="font-medium">{p.name}</TableCell>
                                  <TableCell className="text-slate-600">{p.sku ?? "—"}</TableCell>
                                  <TableCell>{p.sizeMl ? `${p.sizeMl} ${p.sizeUnit ?? "ml"}` : "—"}</TableCell>
                                  <TableCell>{p.unit ?? "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums">{fmtGhc(p.unitPrice)}</TableCell>
                                  <TableCell className="text-right tabular-nums font-semibold">{(p.stockOnHand ?? 0).toLocaleString()}</TableCell>
                                  <TableCell className="text-right tabular-nums text-slate-600">
                                    {sachetCount !== null ? sachetCount.toLocaleString() : "—"}
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
            </TabsContent>

            <TabsContent value="raw" className="mt-4">
              <Card>
                <CardContent className="p-0">
                  <div className="flex items-center justify-between p-3 border-b bg-slate-50">
                    <div className="text-sm text-slate-600">Sachet rolls, caps, labels. Stock updated by raw-material purchases + production usage.</div>
                    <Button asChild size="sm" variant="outline">
                      <Link href="/water-raw-materials"><ExternalLink className="h-4 w-4 mr-1" /> Manage raw materials</Link>
                    </Button>
                  </div>
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : filteredRaw.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">{q ? "No raw materials match your search." : "No raw materials yet."}</div>
                  ) : (
                    <MobileCardList
                      items={filteredRaw}
                      defaultOpen
                      getKey={(r) => r.waterRawMaterialItemId}
                      primary={(r) => r.itemName}
                      secondary={(r) => {
                        const st = rawStatus(r)
                        return <ToneBadge tone={st.tone} label={st.label} />
                      }}
                      details={(r) => [
                        { label: "Category", value: r.category ?? "—" },
                        { label: "Unit", value: (r as any).unitOfMeasure ?? "—" },
                        { label: "Stock", value: (r.currentQuantity ?? 0).toLocaleString() },
                        { label: "Min alert", value: ((r as any).minimumStockAlert ?? 0).toLocaleString() || "—" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Item</TableHead>
                              <TableHead>Category</TableHead>
                              <TableHead>Unit</TableHead>
                              <TableHead className="text-right">Stock</TableHead>
                              <TableHead className="text-right">Min alert</TableHead>
                              <TableHead>Status</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {filteredRaw.map((r) => {
                              const st = rawStatus(r)
                              return (
                                <TableRow key={r.waterRawMaterialItemId}>
                                  <TableCell className="font-medium">{r.itemName}</TableCell>
                                  <TableCell>{r.category ?? "—"}</TableCell>
                                  <TableCell>{(r as any).unitOfMeasure ?? "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums font-semibold">{(r.currentQuantity ?? 0).toLocaleString()}</TableCell>
                                  <TableCell className="text-right tabular-nums text-slate-500">{((r as any).minimumStockAlert ?? 0).toLocaleString() || "—"}</TableCell>
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
            </TabsContent>
          </Tabs>
        </main>
      </div>
    </div>
  )
}

"use client"

// Poultry inventory page. Same shape as /water-inventory: one page, two tabs
// (finished products / raw materials), stat cards up top, search in the header.
//
// Read-only here on purpose — adjustments go through the dedicated routes
// (/poultry-products, /poultry-raw-materials) so the audit log captures
// who/what/when. This page is the at-a-glance view, plus the PDF/email report
// and the per-item links into the egg / birds / feed / medication trackers.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Boxes, Box, ShoppingBag, AlertTriangle, AlertCircle, Layers, Loader2, Search,
  ExternalLink, RefreshCw, Download, Mail,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryProducts, listPoultryRawMaterialItems, ensurePoultryDefaults,
  setPoultryProductStock, reconcilePoultryProductStock,
  type PoultryProduct, type PoultryRawMaterialItem,
} from "@/lib/api/poultry-inventory"
import { RecalculateStockButton } from "@/components/poultry/recalculate-stock-button"
import { SetProductStockButton } from "@/components/inventory/set-product-stock-button"
import { ReconcileProductStockButton } from "@/components/inventory/reconcile-product-stock-button"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

type Tone = "ok" | "low" | "out" | "inactive"

function StatCard({ label, value, icon: Icon, accent }: { label: string; value: string | number; icon: any; accent?: "amber" | "rose" | "emerald" }) {
  const colors = accent === "amber" ? "bg-amber-100 text-amber-700"
    : accent === "rose" ? "bg-rose-100 text-rose-700"
    : accent === "emerald" ? "bg-emerald-100 text-emerald-700"
    : "bg-orange-100 text-orange-700"
  return (
    <Card>
      <CardContent className="p-4 flex items-center gap-3">
        <div className={`rounded-lg p-2 ${colors}`}><Icon className="h-5 w-5" /></div>
        <div className="min-w-0">
          <div className="text-xs text-slate-500">{label}</div>
          <div className="text-2xl font-semibold text-slate-900 tabular-nums">{value}</div>
        </div>
      </CardContent>
    </Card>
  )
}

const ToneBadge = ({ tone, label }: { tone: Tone; label: string }) =>
  tone === "inactive" ? <Badge variant="secondary">{label}</Badge>
    : tone === "out" ? <Badge className="bg-rose-100 text-rose-700">{label}</Badge>
    : tone === "low" ? <Badge className="bg-amber-100 text-amber-700"><AlertTriangle className="h-3 w-3 mr-1" />{label}</Badge>
    : <Badge className="bg-emerald-100 text-emerald-700">{label}</Badge>

// Details link routes to the right tracker, filtered by the item.
function productLink(p: PoultryProduct): { href: string; label: string } {
  if (p.isRawEggProduct) return { href: `/egg-tracker?inventoryItemId=${p.poultryProductId}`, label: "Egg Tracker" }
  if (p.isBirdProduct) return { href: `/birds-left-tracker?inventoryItemId=${p.poultryProductId}`, label: "Birds Tracker" }
  return { href: `/poultry-stock?productId=${p.poultryProductId}`, label: "View Stock" }
}
function rawLink(r: PoultryRawMaterialItem): { href: string; label: string } {
  const id = r.poultryRawMaterialItemId
  if (r.category === "FeedIngredient") return { href: `/feed-tracker?inventoryItemId=${id}`, label: "Feed Tracker" }
  if (r.category === "Medication" || r.category === "Vaccine") return { href: `/medication-tracker?inventoryItemId=${id}`, label: "Medication Tracker" }
  return { href: `/poultry-stock?rawId=${id}`, label: "View Details" }
}

const DetailLink = ({ href, label }: { href: string; label: string }) => (
  <Link href={href} className="text-blue-600 hover:underline text-sm whitespace-nowrap">{label}</Link>
)

export default function PoultryInventoryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [loading, setLoading] = useState(true)
  const [q, setQ] = useState("")
  const [category, setCategory] = useState("ALL")
  const [status, setStatus] = useState("ALL")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [emailingReport, setEmailingReport] = useState(false)
  const resetFilters = () => { setQ(""); setCategory("ALL"); setStatus("ALL"); setDateFrom(""); setDateTo("") }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        await ensurePoultryDefaults().catch(() => {})   // doc: Eggs + Birds defaults visible in inventory
        const [ps, is] = await Promise.all([listPoultryProducts(), listPoultryRawMaterialItems()])
        if (!cancelled) { setProducts(ps); setItems(is) }
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load inventory", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // Egg stock is counted in individual eggs everywhere (production records count
  // eggs; the sales form converts crates × 30 + loose into pieces before saving).
  // Crates are still how the farm thinks, so show the equivalent beside the count
  // — same 30/crate the Egg Stock Balance report uses.
  const EGGS_PER_CRATE = 30
  const crateEquivalent = (eggs: number): string | null => {
    if (eggs < EGGS_PER_CRATE) return null
    const crates = Math.floor(eggs / EGGS_PER_CRATE)
    const loose = eggs % EGGS_PER_CRATE
    return `${crates.toLocaleString()} crate${crates === 1 ? "" : "s"}${loose ? ` + ${loose}` : ""}`
  }

  // Status helpers.
  const productStatus = (p: PoultryProduct): { label: string; tone: Tone } => {
    if (!p.isActive) return { label: "Inactive", tone: "inactive" }
    if ((p.stockOnHand ?? 0) <= 0) return { label: "Out of stock", tone: "out" }
    return { label: "In stock", tone: "ok" }
  }
  const rawStatus = (r: PoultryRawMaterialItem): { label: string; tone: Tone } => {
    if (!r.isActive) return { label: "Inactive", tone: "inactive" }
    const s = r.currentQuantity ?? 0
    const min = r.minimumStockAlert ?? 0
    if (s <= 0) return { label: "Out of stock", tone: "out" }
    if (r.isLowStock || (min > 0 && s <= min)) return { label: "Low stock", tone: "low" }
    return { label: "In stock", tone: "ok" }
  }

  // Distinct Type / Category values across finished products + raw materials.
  const categories = useMemo(() => {
    const set = new Set<string>()
    products.forEach((p) => { if (p.productType) set.add(p.productType) })
    items.forEach((i) => { if (i.category) set.add(i.category) })
    return Array.from(set).sort((a, b) => a.localeCompare(b))
  }, [products, items])

  // Shared filter predicate: search + category + status + date-added range.
  const matchesQ = (...fields: (string | null | undefined)[]) =>
    !q.trim() || fields.some((f) => (f ?? "").toLowerCase().includes(q.trim().toLowerCase()))
  const matchesDate = (iso?: string | null) => {
    const day = iso ? iso.slice(0, 10) : ""
    if (dateFrom && (!day || day < dateFrom)) return false
    if (dateTo && (!day || day > dateTo)) return false
    return true
  }
  const matchesStatus = (tone: Tone) => {
    if (status === "ALL") return true
    if (status === "inactive") return tone === "inactive"
    if (status === "low") return tone === "low"
    if (status === "out") return tone === "out"
    return tone === "ok"
  }

  const filteredProducts = useMemo(
    () => products
      .filter((p) => matchesQ(p.name, p.sku, p.productType, p.unit))
      .filter((p) => category === "ALL" || p.productType === category)
      .filter((p) => matchesStatus(productStatus(p).tone))
      .filter((p) => matchesDate(p.createdDate))
      .sort((a, b) => a.name.localeCompare(b.name)),
    [products, q, category, status, dateFrom, dateTo]
  )
  const filteredRaw = useMemo(
    () => items
      .filter((r) => matchesQ(r.itemName, r.category, r.unitOfMeasure))
      .filter((r) => category === "ALL" || r.category === category)
      .filter((r) => matchesStatus(rawStatus(r).tone))
      .filter((r) => matchesDate(r.createdAt))
      .sort((a, b) => a.itemName.localeCompare(b.itemName)),
    [items, q, category, status, dateFrom, dateTo]
  )

  // Client-side paging — one pager per tab, each fed the same slice its cards
  // and its desktop table render.
  const pgProducts = usePagination(filteredProducts)
  const pgRaw = usePagination(filteredRaw)

  const counts = useMemo(() => {
    let low = 0, out = 0
    for (const p of products) {
      const t = productStatus(p).tone
      if (t === "low") low++
      else if (t === "out") out++
    }
    for (const r of items) {
      const t = rawStatus(r).tone
      if (t === "low") low++
      else if (t === "out") out++
    }
    return {
      totalItems: products.length + items.length,
      low,
      out,
      finishedStock: products.reduce((s, p) => s + (p.stockOnHand || 0), 0),
    }
  }, [products, items])

  // PDF / email report built from the currently filtered rows (both tabs).
  const buildPdfOpts = (): PdfExportOptions => ({
    title: "Inventory Report",
    filename: "poultry-inventory",
    columns: [
      { header: "Item" },
      { header: "Parent Type" },
      { header: "Type / Category" },
      { header: "Size" },
      { header: "Unit" },
      { header: "Unit price", align: "right" },
      { header: "In stock", align: "right" },
      { header: "Status" },
    ],
    rows: [
      ...filteredProducts.map((p) => [
        p.name, "Finished Product", p.productType, p.size ?? "", p.unit ?? "",
        gh(p.unitPrice), (p.stockOnHand ?? 0).toLocaleString(), productStatus(p).label,
      ]),
      ...filteredRaw.map((r) => [
        r.itemName, "Raw Material", r.category, "", r.unitOfMeasure ?? "",
        "", (r.currentQuantity ?? 0).toLocaleString(), rawStatus(r).label,
      ]),
    ],
    summaryLines: [`Items: ${filteredProducts.length + filteredRaw.length}`],
    headFillColor: [234, 88, 12],
  })

  const reportRowCount = filteredProducts.length + filteredRaw.length

  const handleExportPdf = async () => {
    if (reportRowCount === 0) { toast({ title: "Nothing to export", description: "No inventory items match the current filters.", variant: "destructive" }); return }
    try { await exportTableToPdf(buildPdfOpts()) }
    catch { toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" }) }
  }

  const handleEmailReport = async () => {
    if (reportRowCount === 0) { toast({ title: "Nothing to email", description: "No inventory items match the current filters.", variant: "destructive" }); return }
    setEmailingReport(true)
    try {
      const res = await emailTableAsPdf(buildPdfOpts())
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${res.recipient}.` })
      else toast({ title: "Email failed", description: res.message || "Could not send report.", variant: "destructive" })
    } finally { setEmailingReport(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div className="flex items-center gap-3">
              <div className="rounded-lg bg-orange-100 p-2"><Boxes className="h-6 w-6 text-orange-700" /></div>
              <div>
                <h1 className="text-2xl font-semibold text-slate-900">Poultry inventory</h1>
                <p className="text-sm text-slate-600">Finished products and raw materials in one place.</p>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
              <div className="relative w-full md:w-80">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search by name, SKU, category…" className="pl-9" value={q} onChange={(e) => setQ(e.target.value)} />
              </div>
              <RecalculateStockButton items={items} size="sm" onDone={async () => setItems(await listPoultryRawMaterialItems())} />
              <ReconcileProductStockButton size="sm" products={products.map((p) => ({ id: p.poultryProductId, name: p.name }))} reconcile={reconcilePoultryProductStock} onDone={async () => setProducts(await listPoultryProducts())} />
              <SetProductStockButton size="sm" products={products.map((p) => ({ id: p.poultryProductId, name: p.name, currentStock: p.stockOnHand, disabledReason: (p.isBirdProduct || p.name === "Birds") ? "Bird stock comes from the birds left in your flocks — correct it in the flock / production records (record mortality, or edit the flock)." : undefined }))} setStock={setPoultryProductStock} onDone={async () => setProducts(await listPoultryProducts())} />
            </div>
          </div>

          {/* Top stat cards */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <StatCard label="Total items" value={loading ? "…" : counts.totalItems} icon={Boxes} />
            <StatCard label="Low stock" value={loading ? "…" : counts.low} icon={AlertTriangle} accent="amber" />
            <StatCard label="Out of stock" value={loading ? "…" : counts.out} icon={AlertCircle} accent="rose" />
            <StatCard label="Total finished stock" value={loading ? "…" : counts.finishedStock.toLocaleString()} icon={Layers} accent="emerald" />
          </div>

          {/* Filters + report actions */}
          <Card>
            <CardContent className="p-3">
              <div className="flex flex-wrap items-center gap-2">
                <Select value={category} onValueChange={setCategory}>
                  <SelectTrigger className="w-full sm:w-[190px]"><SelectValue placeholder="Type / Category" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All categories</SelectItem>
                    {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={status} onValueChange={setStatus}>
                  <SelectTrigger className="w-full sm:w-[160px]"><SelectValue placeholder="Status" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All statuses</SelectItem>
                    <SelectItem value="ok">In stock</SelectItem>
                    <SelectItem value="low">Low stock</SelectItem>
                    <SelectItem value="out">Out of stock</SelectItem>
                    <SelectItem value="inactive">Inactive</SelectItem>
                  </SelectContent>
                </Select>
                <Input type="date" aria-label="Date added from" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-full sm:w-[160px]" />
                <Input type="date" aria-label="Date added to" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-full sm:w-[160px]" />
                <div className="flex flex-wrap items-center gap-2 sm:ml-auto">
                  <Button variant="outline" size="sm" onClick={handleExportPdf} className="gap-2"><Download className="h-4 w-4" /> Export PDF</Button>
                  <Button variant="outline" size="sm" onClick={handleEmailReport} disabled={emailingReport} className="gap-2">
                    {emailingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />} Email Report
                  </Button>
                  <Button variant="outline" size="sm" onClick={resetFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                </div>
              </div>
            </CardContent>
          </Card>

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
                    <div className="min-w-0 text-sm text-slate-600">Eggs and packaged products: stock = SUM(PoultryStockTransactions), the same ledger the Egg Tracker balances. Birds: birds left in your flocks.</div>
                    <Button asChild size="sm" variant="outline" className="w-full shrink-0 sm:w-auto">
                      <Link href="/poultry-products"><ExternalLink className="h-4 w-4 mr-1" /> Manage products</Link>
                    </Button>
                  </div>
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : filteredProducts.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">{q || category !== "ALL" || status !== "ALL" || dateFrom || dateTo ? "No products match your filters." : "No products yet."}</div>
                  ) : (
                    <MobileCardList
                      items={pgProducts.pageItems}
                      pagination={pgProducts.paginationProps}
                      defaultOpen
                      getKey={(p) => p.poultryProductId}
                      primary={(p) => p.name}
                      secondary={(p) => {
                        const st = productStatus(p)
                        return <ToneBadge tone={st.tone} label={st.label} />
                      }}
                      details={(p) => {
                        const l = productLink(p)
                        return [
                          { label: "Type", value: p.productType || "—" },
                          { label: "SKU", value: p.sku ?? "—" },
                          { label: "Size", value: p.size ?? "—" },
                          { label: "Unit", value: p.unit ?? "—" },
                          { label: "Unit price", value: gh(p.unitPrice) },
                          {
                            label: "In stock",
                            value: p.isRawEggProduct && crateEquivalent(p.stockOnHand ?? 0)
                              ? `${(p.stockOnHand ?? 0).toLocaleString()} (${crateEquivalent(p.stockOnHand ?? 0)})`
                              : (p.stockOnHand ?? 0).toLocaleString(),
                          },
                          { label: "Details", value: <DetailLink href={l.href} label={l.label} /> },
                        ]
                      }}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table className="min-w-[720px]">
                            <TableHeader>
                              <TableRow>
                                <TableHead>Item</TableHead>
                                <TableHead>Type</TableHead>
                                <TableHead>SKU</TableHead>
                                <TableHead>Size</TableHead>
                                <TableHead>Unit</TableHead>
                                <TableHead className="text-right">Unit price</TableHead>
                                <TableHead className="text-right">In stock</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead>Details</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pgProducts.pageItems.map((p) => {
                                const st = productStatus(p)
                                const l = productLink(p)
                                return (
                                  <TableRow key={p.poultryProductId}>
                                    <TableCell className="font-medium">{p.name}</TableCell>
                                    <TableCell>{p.productType || "—"}</TableCell>
                                    <TableCell className="text-slate-600">{p.sku ?? "—"}</TableCell>
                                    <TableCell>{p.size ?? "—"}</TableCell>
                                    <TableCell>{p.unit ?? "—"}</TableCell>
                                    <TableCell className="text-right tabular-nums">{gh(p.unitPrice)}</TableCell>
                                    <TableCell className="text-right tabular-nums font-semibold">
                                      {(p.stockOnHand ?? 0).toLocaleString()}
                                      {p.isRawEggProduct && crateEquivalent(p.stockOnHand ?? 0) && (
                                        <div className="text-xs font-normal text-slate-500">{crateEquivalent(p.stockOnHand ?? 0)}</div>
                                      )}
                                    </TableCell>
                                    <TableCell><ToneBadge tone={st.tone} label={st.label} /></TableCell>
                                    <TableCell><DetailLink href={l.href} label={l.label} /></TableCell>
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
                  <div className="flex flex-col gap-2 p-3 border-b bg-slate-50 sm:flex-row sm:items-center sm:justify-between">
                    <div className="min-w-0 text-sm text-slate-600">Feed ingredients, medication, vaccines. Stock updated by purchases + production usage.</div>
                    <Button asChild size="sm" variant="outline" className="w-full shrink-0 sm:w-auto">
                      <Link href="/poultry-raw-materials"><ExternalLink className="h-4 w-4 mr-1" /> Manage raw materials</Link>
                    </Button>
                  </div>
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : filteredRaw.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">{q || category !== "ALL" || status !== "ALL" || dateFrom || dateTo ? "No raw materials match your filters." : "No raw materials yet."}</div>
                  ) : (
                    <MobileCardList
                      items={pgRaw.pageItems}
                      pagination={pgRaw.paginationProps}
                      defaultOpen
                      getKey={(r) => r.poultryRawMaterialItemId}
                      primary={(r) => r.itemName}
                      secondary={(r) => {
                        const st = rawStatus(r)
                        return <ToneBadge tone={st.tone} label={st.label} />
                      }}
                      details={(r) => {
                        const l = rawLink(r)
                        return [
                          { label: "Category", value: r.category ?? "—" },
                          { label: "Unit", value: r.unitOfMeasure ?? "—" },
                          { label: "In stock", value: (r.currentQuantity ?? 0).toLocaleString() },
                          { label: "Min alert", value: (r.minimumStockAlert ?? 0).toLocaleString() },
                          { label: "Details", value: <DetailLink href={l.href} label={l.label} /> },
                        ]
                      }}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table className="min-w-[720px]">
                            <TableHeader>
                              <TableRow>
                                <TableHead>Item</TableHead>
                                <TableHead>Category</TableHead>
                                <TableHead>Unit</TableHead>
                                <TableHead className="text-right">In stock</TableHead>
                                <TableHead className="text-right">Min alert</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead>Details</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pgRaw.pageItems.map((r) => {
                                const st = rawStatus(r)
                                const l = rawLink(r)
                                return (
                                  <TableRow key={r.poultryRawMaterialItemId}>
                                    <TableCell className="font-medium">{r.itemName}</TableCell>
                                    <TableCell>{r.category ?? "—"}</TableCell>
                                    <TableCell>{r.unitOfMeasure ?? "—"}</TableCell>
                                    <TableCell className="text-right tabular-nums font-semibold">{(r.currentQuantity ?? 0).toLocaleString()}</TableCell>
                                    <TableCell className="text-right tabular-nums text-slate-500">{(r.minimumStockAlert ?? 0).toLocaleString()}</TableCell>
                                    <TableCell><ToneBadge tone={st.tone} label={st.label} /></TableCell>
                                    <TableCell><DetailLink href={l.href} label={l.label} /></TableCell>
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

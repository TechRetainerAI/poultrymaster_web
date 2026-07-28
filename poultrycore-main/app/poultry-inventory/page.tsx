"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { FieldCard } from "@/components/ui/field-card"
import { Loader2, AlertTriangle, Box, Package, Search, RefreshCw, Download, Mail } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import Link from "next/link"
import { listPoultryProducts, listPoultryRawMaterialItems, ensurePoultryDefaults, setPoultryProductStock, type PoultryProduct, type PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"
import { RecalculateStockButton } from "@/components/poultry/recalculate-stock-button"
import { SetProductStockButton } from "@/components/inventory/set-product-stock-button"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

type Row = {
  key: string; seq: number; parentType: "Finished Product" | "Raw Material"
  id: number; name: string; type: string; size: string | null; unit: string | null
  unitPrice: number | null; stock: number; low: boolean; active: boolean
  date: string | null; isEgg?: boolean; isBird?: boolean
}

// Doc 2 §3-5: Details link routes to the right tracker, filtered by the item.
function detailLink(r: Row): { href: string; label: string } {
  if (r.parentType === "Finished Product") {
    if (r.isEgg) return { href: `/egg-tracker?inventoryItemId=${r.id}`, label: "View Egg Tracker" }
    if (r.isBird) return { href: `/birds-left-tracker?inventoryItemId=${r.id}`, label: "View Birds Tracker" }
    return { href: `/poultry-stock?productId=${r.id}`, label: "View Stock" }
  }
  if (r.type === "FeedIngredient") return { href: `/feed-tracker?inventoryItemId=${r.id}`, label: "View Feed Tracker" }
  if (r.type === "Medication" || r.type === "Vaccine") return { href: `/medication-tracker?inventoryItemId=${r.id}`, label: "View Medication Tracker" }
  return { href: `/poultry-stock?rawId=${r.id}`, label: "View Details" }
}

export default function PoultryInventoryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  // Filters (mirrors the /inventory "Other Inventory" filter bar).
  const [parentType, setParentType] = useState<string>("ALL")
  const [category, setCategory] = useState<string>("ALL")
  const [status, setStatus] = useState<string>("ALL")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [emailingReport, setEmailingReport] = useState(false)
  const resetFilters = () => { setSearch(""); setParentType("ALL"); setCategory("ALL"); setStatus("ALL"); setDateFrom(""); setDateTo("") }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    ;(async () => {
      try {
        await ensurePoultryDefaults().catch(() => {})   // doc: Eggs + Birds defaults visible in inventory
        const [ps, is] = await Promise.all([listPoultryProducts(), listPoultryRawMaterialItems()]); setProducts(ps); setItems(is)
      }
      catch (e: any) { toast({ title: "Could not load inventory", description: e?.message, variant: "destructive" }) }
      finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // Distinct Type / Category values across finished products + raw materials.
  const categories = useMemo(() => {
    const set = new Set<string>()
    products.forEach((p) => { if (p.productType) set.add(p.productType) })
    items.forEach((i) => { if (i.category) set.add(i.category) })
    return Array.from(set).sort((a, b) => a.localeCompare(b))
  }, [products, items])

  // doc 2/3/8: one table, Finished Products first (seq 1), then Raw Materials (seq 2).
  const rows: Row[] = useMemo(() => {
    const fin: Row[] = products.map((p) => ({ key: `p${p.poultryProductId}`, seq: 1, parentType: "Finished Product", id: p.poultryProductId, name: p.name, type: p.productType, size: p.size ?? null, unit: p.unit ?? null, unitPrice: p.unitPrice, stock: p.stockOnHand, low: false, active: p.isActive, date: p.createdDate ?? null, isEgg: p.isRawEggProduct, isBird: p.isBirdProduct }))
    const raw: Row[] = items.map((i) => ({ key: `r${i.poultryRawMaterialItemId}`, seq: 2, parentType: "Raw Material", id: i.poultryRawMaterialItemId, name: i.itemName, type: i.category, size: null, unit: i.unitOfMeasure ?? null, unitPrice: null, stock: i.currentQuantity, low: !!i.isLowStock, active: i.isActive, date: i.createdAt ?? null }))
    const all = [...fin, ...raw]
    const q = search.trim().toLowerCase()
    const filtered = all.filter((r) => {
      if (q && !(r.name.toLowerCase().includes(q) || r.type.toLowerCase().includes(q) || r.parentType.toLowerCase().includes(q))) return false
      if (parentType !== "ALL" && r.parentType !== parentType) return false
      if (category !== "ALL" && r.type !== category) return false
      if (status !== "ALL") {
        const s = !r.active ? "inactive" : r.low ? "low" : "ok"
        if (s !== status) return false
      }
      // Date added range (compare the YYYY-MM-DD portion).
      const day = r.date ? r.date.slice(0, 10) : ""
      if (dateFrom && (!day || day < dateFrom)) return false
      if (dateTo && (!day || day > dateTo)) return false
      return true
    })
    return filtered.sort((a, b) => a.seq - b.seq || a.name.localeCompare(b.name))
  }, [products, items, search, parentType, category, status, dateFrom, dateTo])

  const lowRaw = items.filter((i) => i.isActive && i.isLowStock).length
  const stat = (label: string, value: string | number, cls = "") => (
    <Card><CardContent className="p-4"><div className="text-sm text-slate-500">{label}</div><div className={`text-2xl font-bold ${cls}`}>{value}</div></CardContent></Card>
  )

  // PDF / email report built from the currently filtered rows.
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
    rows: rows.map((r) => [
      r.name,
      r.parentType,
      r.type,
      r.size ?? "",
      r.unit ?? "",
      r.unitPrice != null ? gh(r.unitPrice) : "",
      r.stock.toLocaleString(),
      !r.active ? "Inactive" : r.low ? "Low" : "OK",
    ]),
    summaryLines: [`Items: ${rows.length}`],
    headFillColor: [234, 88, 12],
  })

  const handleExportPdf = async () => {
    if (rows.length === 0) { toast({ title: "Nothing to export", description: "No inventory items match the current filters.", variant: "destructive" }); return }
    try { await exportTableToPdf(buildPdfOpts()) }
    catch { toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" }) }
  }

  const handleEmailReport = async () => {
    if (rows.length === 0) { toast({ title: "Nothing to email", description: "No inventory items match the current filters.", variant: "destructive" }); return }
    setEmailingReport(true)
    try {
      const res = await emailTableAsPdf(buildPdfOpts())
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${res.recipient}.` })
      else toast({ title: "Email failed", description: res.message || "Could not send report.", variant: "destructive" })
    } finally { setEmailingReport(false) }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div><h1 className="text-2xl font-bold">Inventory</h1><p className="text-sm text-slate-500">All finished products and raw materials in one view. Finished products first.</p></div>
            <div className="flex flex-wrap items-center gap-2 sm:justify-end">
              <span className="text-sm font-medium text-slate-600">Applicable Inventory:</span>
              <Link href="/poultry-raw-materials" className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50 hover:text-slate-900">
                <Box className="h-4 w-4" /> Manage/Add Raw Materials
              </Link>
              <Link href="/poultry-products" className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50 hover:text-slate-900">
                <Package className="h-4 w-4" /> Manage Finished Products
              </Link>
              <RecalculateStockButton items={items} size="sm" onDone={async () => setItems(await listPoultryRawMaterialItems())} />
              <SetProductStockButton size="sm" products={products.map((p) => ({ id: p.poultryProductId, name: p.name, currentStock: p.stockOnHand }))} setStock={setPoultryProductStock} onDone={async () => setProducts(await listPoultryProducts())} />
            </div>
          </div>
          {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
            <>
              <Card><CardContent className="p-4">
                <div className="flex flex-wrap items-center gap-2">
                  <div className="relative w-full sm:w-[240px]">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                    <Input placeholder="Search inventory…" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                  </div>
                  <Select value={parentType} onValueChange={setParentType}>
                    <SelectTrigger className="w-[190px]"><SelectValue placeholder="Parent type" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All parent types</SelectItem>
                      <SelectItem value="Finished Product">Finished Product</SelectItem>
                      <SelectItem value="Raw Material">Raw Material</SelectItem>
                    </SelectContent>
                  </Select>
                  <Select value={category} onValueChange={setCategory}>
                    <SelectTrigger className="w-[190px]"><SelectValue placeholder="Type / Category" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All categories</SelectItem>
                      {categories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Select value={status} onValueChange={setStatus}>
                    <SelectTrigger className="w-[150px]"><SelectValue placeholder="Status" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All statuses</SelectItem>
                      <SelectItem value="ok">OK</SelectItem>
                      <SelectItem value="low">Low stock</SelectItem>
                      <SelectItem value="inactive">Inactive</SelectItem>
                    </SelectContent>
                  </Select>
                  <Input type="date" aria-label="Date added from" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[160px]" />
                  <Input type="date" aria-label="Date added to" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[160px]" />
                  <div className="ml-auto flex items-center gap-2">
                    <Button variant="outline" size="sm" onClick={handleExportPdf} className="gap-2"><Download className="h-4 w-4" /> Export PDF</Button>
                    <Button variant="outline" size="sm" onClick={handleEmailReport} disabled={emailingReport} className="gap-2">
                      {emailingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />} Email Report
                    </Button>
                    <Button variant="outline" size="sm" onClick={resetFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                  </div>
                </div>
              </CardContent></Card>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {stat("Finished products", products.length)}
                {stat("Raw material items", items.length)}
                {stat("Low-stock raw items", lowRaw, lowRaw > 0 ? "text-amber-600" : "")}
                {stat("Total finished stock", products.reduce((s, p) => s + (p.stockOnHand || 0), 0).toLocaleString())}
              </div>
              <Card><CardContent className="p-4 space-y-3">
                <div className="hidden md:block overflow-x-auto">
                <Table className="min-w-[720px]">
                  <TableHeader><TableRow>
                    <TableHead>Item</TableHead><TableHead>Parent Type</TableHead><TableHead>Type / Category</TableHead>
                    <TableHead>Size</TableHead><TableHead>Unit</TableHead><TableHead className="text-right">Unit Price</TableHead>
                    <TableHead className="text-right">In stock</TableHead><TableHead>Status</TableHead><TableHead>Details</TableHead>
                  </TableRow></TableHeader>
                  <TableBody>
                    {rows.length === 0 ? <TableRow><TableCell colSpan={9} className="text-center text-slate-500 py-6">No inventory yet.</TableCell></TableRow>
                      : rows.map((r) => (
                        <TableRow key={r.key}>
                          <TableCell className="font-medium">{r.name}</TableCell>
                          <TableCell><Badge className={r.parentType === "Finished Product" ? "bg-blue-100 text-blue-700" : "bg-slate-100 text-slate-700"}>{r.parentType}</Badge></TableCell>
                          <TableCell>{r.type}</TableCell>
                          <TableCell>{r.size ?? "—"}</TableCell>
                          <TableCell>{r.unit ?? "—"}</TableCell>
                          <TableCell className="text-right">{r.unitPrice != null ? gh(r.unitPrice) : "—"}</TableCell>
                          <TableCell className="text-right">{r.stock.toLocaleString()}</TableCell>
                          <TableCell>{!r.active ? <Badge variant="secondary">Inactive</Badge> : r.low ? <Badge className="bg-amber-100 text-amber-700"><AlertTriangle className="w-3 h-3 mr-1" />Low</Badge> : <Badge className="bg-green-100 text-green-700">OK</Badge>}</TableCell>
                          <TableCell>{(() => { const l = detailLink(r); return <Link href={l.href} className="text-blue-600 hover:underline text-sm whitespace-nowrap">{l.label}</Link> })()}</TableCell>
                        </TableRow>
                      ))}
                  </TableBody>
                </Table>
                </div>
                {/* Mobile cards */}
                <div className="md:hidden space-y-2">
                  {rows.length === 0 ? <div className="text-center text-slate-500 py-6">No inventory yet.</div>
                    : rows.map((r) => (
                      <FieldCard key={r.key} title={r.name}
                        badge={!r.active ? <Badge variant="secondary">Inactive</Badge> : r.low ? <Badge className="bg-amber-100 text-amber-700">Low</Badge> : <Badge className="bg-green-100 text-green-700">OK</Badge>}
                        fields={[["Type", r.parentType], ["Category", r.type], ["Unit", r.unit ?? "—"], ["Unit price", r.unitPrice != null ? gh(r.unitPrice) : "—"], ["In stock", r.stock.toLocaleString()], ["", (() => { const l = detailLink(r); return <Link href={l.href} className="text-blue-600 hover:underline">{l.label}</Link> })()]]} />
                    ))}
                </div>
              </CardContent></Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

"use client"

// Generic Production Records — track goods produced by the business.
//
// Deep-copied from the poultry production system but adapted for any business:
// a bakery making bread, a workshop making furniture, a processor making chips.
// Each record increases the product's stock via a Production movement.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ReasonSelect } from "@/components/ui/reason-select"
import { REVERSAL_REASONS } from "@/lib/reversal-reasons"
import {
  Factory, Loader2, Plus, Undo2, Download, Package,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { getProducts, type GenericProduct } from "@/lib/api/generic"
import {
  getProductionRecords, createProductionRecord, reverseProductionRecord,
  type GenericProductionRecord,
} from "@/lib/api/generic-production"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { exportTableToPdf } from "@/lib/utils/pdf-export"

const DEFAULT = defaultReportRange()
const today = () => new Date().toISOString().slice(0, 10)

/** Auto-generate a batch number: PROD-YYYYMMDD-NNN */
function generateBatchNumber(existingRecords: GenericProductionRecord[]): string {
  const date = new Date()
  const dateStr = date.toISOString().slice(0, 10).replace(/-/g, "")
  const prefix = `PROD-${dateStr}-`
  // Find the highest sequence number for today
  let maxSeq = 0
  for (const r of existingRecords) {
    if (r.batchNumber?.startsWith(prefix)) {
      const seq = parseInt(r.batchNumber.slice(prefix.length), 10)
      if (!isNaN(seq) && seq > maxSeq) maxSeq = seq
    }
  }
  return `${prefix}${String(maxSeq + 1).padStart(3, "0")}`
}

export default function GenericProductionPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericProductionRecord[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [statusFilter, setStatusFilter] = useState("All")
  const [productFilter, setProductFilter] = useState("ALL")

  // Record dialog
  const [recordOpen, setRecordOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    productId: "", quantity: "0", unitCost: "0",
    productionDate: today(), batchNumber: "", materialsUsed: "", notes: "",
  })

  // Reverse dialog
  const [reversing, setReversing] = useState<GenericProductionRecord | null>(null)
  const [reason, setReason] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [recs, prods] = await Promise.all([
        getProductionRecords(),
        getProducts().catch(() => []),
      ])
      setRows(recs)
      setProducts(prods)
    } catch (e: any) {
      toast({ title: "Could not load production records", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const filtered = useMemo(() => {
    let data = rows
    if (statusFilter !== "All") data = data.filter((r) => r.status === statusFilter)
    if (productFilter !== "ALL") data = data.filter((r) => String(r.genericProductId) === productFilter)
    return filterByDateAndSearch(data, {
      search, searchKeys: ["productName", "batchNumber", "materialsUsed", "notes"],
      dateFrom, dateTo, dateKey: "productionDate",
    })
  }, [rows, statusFilter, productFilter, search, dateFrom, dateTo])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    const posted = rows.filter((r) => r.status === "Posted")
    return {
      totalProduced: posted.reduce((s, r) => s + r.quantityProduced, 0),
      totalCost: posted.reduce((s, r) => s + r.totalCost, 0),
      recordCount: posted.length,
      productCount: new Set(posted.map((r) => r.genericProductId)).size,
    }
  }, [rows])

  const productOptions = useMemo(() => {
    const seen = new Map<number, string>()
    for (const r of rows) if (r.genericProductId && r.productName) seen.set(r.genericProductId, r.productName)
    return [...seen.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [rows])

  async function onRecord() {
    if (!form.productId) { toast({ title: "Select a product", variant: "destructive" }); return }
    const qty = Number(form.quantity)
    if (qty <= 0) { toast({ title: "Quantity must be greater than zero", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createProductionRecord({
        genericProductId: Number(form.productId),
        quantityProduced: qty,
        unitCost: Number(form.unitCost) || 0,
        productionDate: form.productionDate ? `${form.productionDate}T00:00:00Z` : undefined,
        batchNumber: form.batchNumber.trim() || null,
        materialsUsed: form.materialsUsed.trim() || null,
        notes: form.notes.trim() || null,
      })
      toast({ title: "Production recorded", description: `+${qty} units added to stock.` })
      setRecordOpen(false)
      setForm({ productId: "", quantity: "0", unitCost: "0", productionDate: today(), batchNumber: "", materialsUsed: "", notes: "" })
      await load()
    } catch (e: any) {
      toast({ title: "Could not record production", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function onReverse() {
    if (!reversing) return
    if (!reason.trim()) { toast({ title: "A reason is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await reverseProductionRecord(reversing.genericProductionRecordId, reason.trim())
      toast({ title: "Reversed", description: "Production reversed and stock reduced." })
      setReversing(null); setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  function doExport() {
    exportTableToPdf({
      title: "Production Records",
      subtitle: `${dateFrom} to ${dateTo}`,
      columns: [
        { header: "Date", key: "date", width: 70 },
        { header: "Product", key: "productName", width: 100 },
        { header: "Qty", key: "quantityProduced", width: 50, align: "right" },
        { header: "Unit Cost", key: "unitCost", width: 60, align: "right", format: "currency" },
        { header: "Total Cost", key: "totalCost", width: 70, align: "right", format: "currency" },
        { header: "Batch", key: "batchNumber", width: 60 },
        { header: "Status", key: "status", width: 50 },
      ],
      rows: filtered.map((r) => ({ ...r, date: fmtDateTime(r.productionDate, r) })),
    })
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
                <Factory className="h-6 w-6 text-emerald-600" /> Production Records
              </h1>
              <p className="text-xs text-slate-500">
                Track goods produced — each record increases product stock automatically.
              </p>
            </div>
            <div className="flex gap-2 flex-wrap">
              <Button size="sm" variant="outline" onClick={doExport} disabled={loading || filtered.length === 0}>
                <Download className="h-4 w-4 mr-1" /> Export PDF
              </Button>
              <Button size="sm" onClick={() => {
                setForm((f) => ({ ...f, batchNumber: generateBatchNumber(rows), productionDate: today() }))
                setRecordOpen(true)
              }}>
                <Plus className="h-4 w-4 mr-1" /> Record Production
              </Button>
            </div>
          </div>

          {/* KPI tiles */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Total Produced</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{totals.totalProduced.toLocaleString()} units</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Total Cost</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-slate-900">{fmt(totals.totalCost)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Records</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-slate-900">{totals.recordCount}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Products</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-slate-900">{totals.productCount}</div>
            </CardContent></Card>
          </div>

          <Card className="mb-2">
            <CardContent className="pt-6 space-y-3">
              <ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search product, batch, materials..."
                dateFrom={dateFrom} setDateFrom={setDateFrom} dateTo={dateTo} setDateTo={setDateTo} />
              <div className="flex flex-wrap gap-2">
                <Select value={productFilter} onValueChange={setProductFilter}>
                  <SelectTrigger className="h-8 w-[14rem]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All products</SelectItem>
                    {productOptions.map(([id, name]) => <SelectItem key={id} value={String(id)}>{name}</SelectItem>)}
                  </SelectContent>
                </Select>
                {(["All", "Posted", "Reversed"] as const).map((s) => (
                  <Button key={s} size="sm" variant={statusFilter === s ? "default" : "outline"}
                    onClick={() => setStatusFilter(s)}>{s}</Button>
                ))}
              </div>
            </CardContent>
          </Card>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading production records…</CardContent></Card>
          ) : filtered.length === 0 ? (
            <Card><CardContent className="py-12 text-center text-slate-500">
              {rows.length === 0 ? "No production recorded yet. Use the button above when you produce goods." : "Nothing matches these filters."}
            </CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0 md:p-2">
                <MobileCardList
                  defaultOpen striped stripeAccent="emerald"
                  items={pg.pageItems} pagination={pg.paginationProps}
                  getKey={(r: any) => r.genericProductionRecordId}
                  primary={(r: any) => r.productName ?? `Product #${r.genericProductId}`}
                  secondary={(r: any) => fmtDateTime(r.productionDate, r)}
                  trailing={(r: any) => (
                    <Badge className={r.status === "Reversed" ? "bg-slate-100 text-slate-700 hover:bg-slate-100" : "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"}>
                      {r.status}
                    </Badge>
                  )}
                  highlights={(r: any) => [
                    { label: "Qty", value: `+${r.quantityProduced}`, accent: "emerald" },
                    { label: "Cost", value: fmt(r.totalCost) },
                  ]}
                  details={(r: any) => [
                    { label: "Unit cost", value: fmt(r.unitCost) },
                    { label: "Batch", value: r.batchNumber ?? "—" },
                    { label: "Materials", value: r.materialsUsed ?? "—" },
                    { label: "Notes", value: r.notes ?? "—" },
                  ]}
                  actions={(r: any) => r.status === "Posted" ? (
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200"
                      onClick={() => { setReversing(r); setReason("") }}>
                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                    </Button>
                  ) : null}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead className="text-right">Qty</TableHead>
                            <TableHead className="text-right">Unit Cost</TableHead>
                            <TableHead className="text-right">Total Cost</TableHead>
                            <TableHead>Batch</TableHead>
                            <TableHead>Materials</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead />
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r: any) => (
                            <TableRow key={r.genericProductionRecordId} className={r.status === "Reversed" ? "opacity-60" : ""}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(r.productionDate, r)}</TableCell>
                              <TableCell className="font-medium">{r.productName ?? `#${r.genericProductId}`}</TableCell>
                              <TableCell className="text-right tabular-nums text-emerald-700 font-medium">+{r.quantityProduced}</TableCell>
                              <TableCell className="text-right tabular-nums">{fmt(r.unitCost)}</TableCell>
                              <TableCell className="text-right tabular-nums font-medium">{fmt(r.totalCost)}</TableCell>
                              <TableCell>{r.batchNumber ?? "—"}</TableCell>
                              <TableCell className="max-w-[200px] truncate text-slate-600">{r.materialsUsed ?? "—"}</TableCell>
                              <TableCell>
                                <Badge className={r.status === "Reversed" ? "bg-slate-100 text-slate-700 hover:bg-slate-100" : "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"}>
                                  {r.status}
                                </Badge>
                              </TableCell>
                              <TableCell className="text-right">
                                {r.status === "Posted" && (
                                  <Button size="sm" variant="outline" onClick={() => { setReversing(r); setReason("") }}>
                                    <Undo2 className="h-3 w-3 mr-1" /> Reverse
                                  </Button>
                                )}
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

      {/* Record Production dialog */}
      <Dialog open={recordOpen} onOpenChange={setRecordOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Factory className="w-5 h-5 text-emerald-600" /> Record Production
            </DialogTitle>
            <DialogDescription>
              What was produced? This increases the product's stock automatically.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Production" color="emerald">
              <FormField label="Product *" full>
                <Select value={form.productId} onValueChange={(v) => setForm((f) => ({ ...f, productId: v }))}>
                  <SelectTrigger><SelectValue placeholder="What was produced?" /></SelectTrigger>
                  <SelectContent>
                    {products.filter((p) => p.isActive !== false).map((p) => (
                      <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                        <span className="flex items-center gap-2">
                          <Package className="h-4 w-4 text-slate-400" />
                          {p.productName} ({p.currentStock} in stock)
                        </span>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Quantity produced *">
                <NumberInput value={form.quantity} min={0}
                  onChange={(e) => setForm((f) => ({ ...f, quantity: e.target.value }))} />
              </FormField>
              <FormField label="Date">
                <Input type="date" value={form.productionDate}
                  onChange={(e) => setForm((f) => ({ ...f, productionDate: e.target.value }))} />
              </FormField>
            </FormSection>

            <FormSection title="Costing" color="amber">
              <FormField label="Unit cost" hint="Cost to produce one unit">
                <NumberInput value={form.unitCost} min={0} step="0.01"
                  onChange={(e) => setForm((f) => ({ ...f, unitCost: e.target.value }))} />
              </FormField>
              <FormField label="Total cost">
                <div className="text-lg font-bold text-slate-900 py-2">
                  {fmt((Number(form.quantity) || 0) * (Number(form.unitCost) || 0))}
                </div>
              </FormField>
            </FormSection>

            <FormSection title="Details" color="slate">
              <FormField label="Batch number" hint="Auto-generated. Edit if needed.">
                <Input value={form.batchNumber} placeholder="e.g., PROD-20261114-001"
                  onChange={(e) => setForm((f) => ({ ...f, batchNumber: e.target.value }))} />
              </FormField>
              <FormField label="Materials used" full hint="What inputs or raw materials went into this production?">
                <Textarea rows={2} value={form.materialsUsed}
                  placeholder="e.g., 50kg flour, 10L water, 5kg sugar"
                  onChange={(e) => setForm((f) => ({ ...f, materialsUsed: e.target.value }))} />
              </FormField>
              <FormField label="Notes" full>
                <Textarea rows={2} value={form.notes}
                  onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
              </FormField>
            </FormSection>
          </div>
          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setRecordOpen(false)}
              className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={onRecord} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording…</> : <><Factory className="w-4 h-4 mr-2" />Record Production</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reverse dialog */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) { setReversing(null); setReason("") } }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Undo2 className="w-5 h-5 text-amber-600" /> Reverse Production
            </DialogTitle>
            <DialogDescription>
              {reversing && `${reversing.quantityProduced} units of ${reversing.productName ?? "product"} produced on ${fmtDateTime(reversing.productionDate, reversing)}. `}
              The stock will be reduced by this amount.
            </DialogDescription>
          </DialogHeader>
          <ReasonSelect options={REVERSAL_REASONS} value={reason} onChange={setReason} />
          <div className="flex gap-3 justify-end pt-2">
            <Button variant="ghost" onClick={() => setReversing(null)}>Keep it</Button>
            <Button className="bg-red-600 hover:bg-red-700 text-white" onClick={onReverse} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Reversing…</> : "Reverse"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

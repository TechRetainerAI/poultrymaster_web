"use client"

import { LOSS_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"
import { Plus, Pencil, Loader2, Trash2, CheckCircle2, Undo2, ChevronDown, ChevronUp, ExternalLink, Search, X } from "lucide-react"
import { SortableHeader, toggleSort, sortData, type SortDirection } from "@/components/ui/sortable-header"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryLossRecords, createPoultryLossRecord, updatePoultryLossRecord, approvePoultryLossRecord, unapprovePoultryLossRecord, deletePoultryLossRecord,
  listPoultryProducts, listPoultryProductionLosses, listPoultryStockTransactions, listPoultryAutoDamage,
  type PoultryLossRecord, type PoultryProduct,
} from "@/lib/api/poultry-inventory"
import { getProductionRecords } from "@/lib/api/production-record"
import { getUserContext } from "@/lib/utils/user-context"
import { buildAutoLossEntries, fromAutoDamageApi, type AutoLossEntry } from "@/lib/poultry/auto-loss-entries"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const LOSS_TYPES = ["Damage", "Mortality", "Theft", "Spoilage", "MissingStock", "Other"]
// One list: manual records (editable, approvable) and the automatic damage rows
// read from production records, driver returns and egg sorting (read-only).
type Row =
  | { kind: "manual"; key: string; date: string; l: PoultryLossRecord }
  | { kind: "auto"; key: string; date: string; a: AutoLossEntry }

const rowType = (r: Row) => (r.kind === "auto" ? r.a.lossType : r.l.lossType) || ""
const rowProduct = (r: Row) => (r.kind === "auto" ? r.a.productName : r.l.productName) || ""
const rowQty = (r: Row) => (r.kind === "auto" ? r.a.quantity : r.l.quantity) ?? null
const rowValue = (r: Row) => (r.kind === "auto" ? r.a.estimatedValue : r.l.estimatedValue) ?? null
const rowReason = (r: Row) => (r.kind === "auto" ? r.a.reason : r.l.reason) || ""
/** Approved / Pending for manual records, Automatic for rows read from other pages. */
const rowStatus = (r: Row) => (r.kind === "auto" ? "Automatic" : r.l.status === "Approved" ? "Approved" : "Pending")
/** Manual, or the page an automatic row came from. */
const rowSource = (r: Row) => (r.kind === "auto" ? r.a.sourceLabel : "Entered here")

const EMPTY = { lossDate: new Date().toISOString().split("T")[0], lossType: "Damage", poultryProductId: 0, quantity: 0, estimatedValue: 0, reason: "", notes: "" }

export default function PoultryLossRecordsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [manual, setManual] = useState<PoultryLossRecord[]>([])
  const [auto, setAuto] = useState<AutoLossEntry[]>([])
  const rows = useMemo<Row[]>(() => [
    ...manual.map((l) => ({ kind: "manual" as const, key: `m-${l.poultryLossRecordId}`, date: (l.lossDate || "").split("T")[0], l })),
    ...auto.map((a) => ({ kind: "auto" as const, key: a.key, date: (a.lossDate || "").split("T")[0], a })),
  ].sort((x, y) => (x.date < y.date ? 1 : x.date > y.date ? -1 : 0)), [manual, auto])
  // Filters and sorting (both the cards and the table follow them).
  const [search, setSearch] = useState("")
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [productFilter, setProductFilter] = useState("ALL")
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [sourceFilter, setSourceFilter] = useState("ALL")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [sortKey, setSortKey] = useState<string | null>("date")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")
  const onSort = (key: string) => {
    const next = toggleSort(key, sortKey, sortDir)
    setSortKey(next.key); setSortDir(next.direction)
  }
  const typeOptions = useMemo(() => Array.from(new Set([...LOSS_TYPES, ...rows.map(rowType)].filter(Boolean))).sort(), [rows])
  const productOptions = useMemo(() => Array.from(new Set(rows.map(rowProduct).filter(Boolean))).sort((a, b) => a.localeCompare(b)), [rows])
  const sourceOptions = useMemo(() => Array.from(new Set(rows.map(rowSource))).sort((a, b) => a.localeCompare(b)), [rows])
  const filtersActive = search.trim() !== "" || typeFilter !== "ALL" || productFilter !== "ALL" || statusFilter !== "ALL"
    || sourceFilter !== "ALL" || dateFrom !== "" || dateTo !== ""
  const clearFilters = () => {
    setSearch(""); setTypeFilter("ALL"); setProductFilter("ALL"); setStatusFilter("ALL")
    setSourceFilter("ALL"); setDateFrom(""); setDateTo("")
  }
  const shown = useMemo(() => {
    const term = search.trim().toLowerCase()
    const list = rows.filter((r) => {
      if (term && ![rowType(r), rowProduct(r), rowReason(r), rowSource(r), r.kind === "manual" ? r.l.notes ?? "" : ""]
        .some((x) => x.toLowerCase().includes(term))) return false
      if (typeFilter !== "ALL" && rowType(r) !== typeFilter) return false
      if (productFilter !== "ALL" && rowProduct(r) !== productFilter) return false
      if (statusFilter !== "ALL" && rowStatus(r) !== statusFilter) return false
      if (sourceFilter !== "ALL" && rowSource(r) !== sourceFilter) return false
      if (dateFrom && r.date < dateFrom) return false
      if (dateTo && r.date > dateTo) return false
      return true
    })
    return sortData(list, sortKey, sortDir, (r, key) => {
      switch (key) {
        case "date": return r.kind === "auto" ? r.a.lossDate : r.l.lossDate
        case "type": return rowType(r)
        case "product": return rowProduct(r) || null
        case "qty": return rowQty(r)
        case "value": return rowValue(r)
        case "status": return rowStatus(r)
        default: return null
      }
    })
  }, [rows, search, typeFilter, productFilter, statusFilter, sourceFilter, dateFrom, dateTo, sortKey, sortDir])
  const shownTotals = useMemo(() => shown.reduce((t, r) => ({
    qty: t.qty + (Number(rowQty(r)) || 0),
    value: t.value + (Number(rowValue(r)) || 0),
    pending: t.pending + (rowStatus(r) === "Pending" ? 1 : 0),
  }), { qty: 0, value: 0, pending: 0 }), [shown])
  const pg = usePagination(shown)
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [delTarget, setDelTarget] = useState<PoultryLossRecord | null>(null)
  const isMobile = useIsMobile()
  // Mobile opens on scorecards; "View table format" flips to the wide table.
  const [showTableMobile, setShowTableMobile] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [ls, ps] = await Promise.all([listPoultryLossRecords(), listPoultryProducts()])
      setManual(ls); setProducts(ps)
      setAuto(await loadAutoDamage())
    }
    catch (e: any) { toast({ title: "Could not load loss records", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Automatic damage rows. Fast path: the server query (migration 405), which
  // returns only damage rows. If that endpoint is missing (API or DB not yet
  // updated) fall back to building them here from the full production records
  // and stock ledger. Never throws: the manual records must still show.
  async function loadAutoDamage(): Promise<AutoLossEntry[]> {
    try { return fromAutoDamageApi(await listPoultryAutoDamage()) } catch { /* fall back */ }
    const { userId, farmId } = getUserContext()
    const [prs, losses, txns] = await Promise.all([
      userId && farmId ? getProductionRecords(userId, farmId).then((r) => (r.success ? r.data : [])).catch(() => []) : Promise.resolve([]),
      listPoultryProductionLosses().catch(() => []),
      listPoultryStockTransactions().catch(() => []),
    ])
    return buildAutoLossEntries({ records: prs as any, losses, txns })
  }

  function openNew() { setEditId(null); setForm({ ...EMPTY }); setOpen(true) }
  function openEdit(l: PoultryLossRecord) {
    setEditId(l.poultryLossRecordId)
    setForm({ lossDate: (l.lossDate || "").split("T")[0], lossType: l.lossType, poultryProductId: l.poultryProductId ?? 0, quantity: l.quantity ?? 0, estimatedValue: l.estimatedValue ?? 0, reason: l.reason ?? "", notes: l.notes ?? "" })
    setOpen(true)
  }
  async function save() {
    setSaving(true)
    try {
      const payload = { ...form, poultryProductId: form.poultryProductId || null, quantity: form.quantity || null, estimatedValue: form.estimatedValue || null }
      if (editId) await updatePoultryLossRecord(editId, payload); else await createPoultryLossRecord(payload)
      toast({ title: editId ? "Loss record updated" : "Loss record added" }); setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }
  async function doApprove(id: number) { try { await approvePoultryLossRecord(id); toast({ title: "Approved" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function doUnapprove(id: number) { try { await unapprovePoultryLossRecord(id); toast({ title: "Reverted to pending" }); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function confirmDelete() { if (!delTarget) return; try { await deletePoultryLossRecord(delTarget.poultryLossRecordId); toast({ title: "Removed" }); setDelTarget(null); await load() } catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) } }

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Loss & Damage Records</h1><p className="text-sm text-slate-500">Damages, mortality, spoilage, missing stock. Damaged eggs from production records, driver returns and egg sorting are added automatically — change those at their source.</p></div>
            <Button onClick={openNew}><Plus className="w-4 h-4 mr-1" /> New record</Button>
          </div>
          {!loading && rows.length > 0 && (
            <Card><CardContent className="p-3 space-y-3">
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-8">
                <div className="relative sm:col-span-2 lg:col-span-2">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                  <Input className="h-9 pl-9" placeholder="Search product, reason, notes" value={search} onChange={(e) => setSearch(e.target.value)} />
                </div>
                <LossFilter label="Type" value={typeFilter} onChange={setTypeFilter} allLabel="All types" options={typeOptions} />
                <LossFilter label="Product" value={productFilter} onChange={setProductFilter} allLabel="All products" options={productOptions} />
                <LossFilter label="Status" value={statusFilter} onChange={setStatusFilter} allLabel="All statuses" options={["Pending", "Approved", "Automatic"]} />
                <LossFilter label="Source" value={sourceFilter} onChange={setSourceFilter} allLabel="All sources" options={sourceOptions} />
                <Input type="date" aria-label="From date" title="From date" className="h-9" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                <Input type="date" aria-label="To date" title="To date" className="h-9" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
              </div>
              <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-slate-600">
                <span><span className="font-semibold text-slate-900">{shown.length.toLocaleString()}</span> of {rows.length.toLocaleString()} records</span>
                <span>Qty <span className="font-semibold text-slate-900">{shownTotals.qty.toLocaleString()}</span></span>
                <span>Value <span className="font-semibold text-slate-900">{gh(shownTotals.value)}</span></span>
                {shownTotals.pending > 0 && <span className="text-amber-700">{shownTotals.pending} pending approval</span>}
                {filtersActive && (
                  <Button size="sm" variant="ghost" className="ml-auto h-8 gap-1 text-slate-600" onClick={clearFilters}>
                    <X className="h-3.5 w-3.5" /> Clear filters
                  </Button>
                )}
              </div>
            </CardContent></Card>
          )}
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
              : isMobile && !showTableMobile ? (
              shown.length === 0 ? <div className="py-8 text-center text-slate-500">{rows.length === 0 ? "No loss records yet." : "No records match these filters."}</div> : (
              <div className="space-y-3">
                {pg.pageItems.map((row, idx) => row.kind === "auto" ? (
                  <div key={row.key} className={cn("rounded-xl border shadow-sm px-2.5 py-3", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold text-slate-900">{fmtDateTime(row.a.lossDate)}</span>
                      <Badge className="bg-slate-200 text-slate-700">Automatic</Badge>
                    </div>
                    <div className="mt-0.5 truncate text-xs text-slate-500">{row.a.productName} · from {row.a.sourceLabel}</div>
                    <div className="mt-3 grid grid-cols-2 gap-2">
                      <div className="rounded-lg bg-rose-100 border border-rose-300 px-3 py-2 shadow-sm">
                        <p className="text-[11px] font-semibold uppercase tracking-wide text-rose-900">{row.a.lossType}</p>
                        <p className="text-xl font-extrabold leading-tight text-rose-800">{row.a.quantity.toLocaleString()}</p>
                      </div>
                      <div className="rounded-lg bg-violet-100 border border-violet-300 px-3 py-2 shadow-sm">
                        <p className="text-[11px] font-semibold uppercase tracking-wide text-violet-900">Value</p>
                        <p className="text-xl font-extrabold leading-tight text-violet-900">{row.a.estimatedValue != null ? gh(row.a.estimatedValue) : "—"}</p>
                      </div>
                    </div>
                    {row.a.reason && <div className="mt-2 text-sm"><span className="text-slate-500">Details</span> <span className="font-medium">{row.a.reason}</span></div>}
                    {row.a.href && (
                      <Button asChild variant="outline" size="sm" className="mt-3 h-10 w-full bg-white">
                        <Link href={row.a.href}><ExternalLink className="h-4 w-4 mr-2" /> Open {row.a.sourceLabel}</Link>
                      </Button>
                    )}
                  </div>
                ) : (() => { const l = row.l; return (
                  <Collapsible
                    key={row.key}
                    defaultOpen
                    className={cn("group w-full rounded-xl border shadow-sm overflow-hidden",
                      idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}
                  >
                    <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 0 ? "active:bg-black/10" : "active:bg-black/5")}>
                      <CollapsibleTrigger asChild>
                        <div className="relative cursor-pointer">
                          <ChevronDown className="absolute right-0 top-0 h-4 w-4 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                          <div className="min-w-0">
                            <div className="pr-6">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="font-semibold text-slate-900">{fmtDateTime(l.lossDate, l)}</span>
                                {l.status === "Approved"
                                  ? <Badge className="bg-green-100 text-green-700">Approved</Badge>
                                  : <Badge className="bg-amber-100 text-amber-700">Pending</Badge>}
                              </div>
                              <div className="mt-0.5 truncate text-xs text-slate-500">{l.productName ?? "No product"}</div>
                            </div>
                            <div className="mt-3 grid grid-cols-2 gap-2">
                              <div className="rounded-lg bg-rose-100 border border-rose-300 px-3 py-2 shadow-sm">
                                <p className="text-[11px] font-semibold uppercase tracking-wide text-rose-900">{l.lossType}</p>
                                <p className="text-xl font-extrabold leading-tight text-rose-800">{l.quantity?.toLocaleString() ?? "—"}</p>
                              </div>
                              <div className="rounded-lg bg-violet-100 border border-violet-300 px-3 py-2 shadow-sm">
                                <p className="text-[11px] font-semibold uppercase tracking-wide text-violet-900">Value</p>
                                <p className="text-xl font-extrabold leading-tight text-violet-900">{l.estimatedValue != null ? gh(l.estimatedValue) : "—"}</p>
                              </div>
                            </div>
                          </div>
                        </div>
                      </CollapsibleTrigger>
                      <CollapsibleContent>
                        <div className="mt-4 space-y-2 border-t border-slate-200/70 pt-4 text-sm">
                          {l.reason && <div><span className="text-slate-500">Reason</span> <span className="font-medium">{l.reason}</span></div>}
                          {/* Two per row: labelled buttons overflow a 375px card on one flex line. */}
                          <div className="grid grid-cols-2 gap-2 pt-2">
                            {l.status === "Pending" ? <>
                              <Button variant="outline" size="sm" className="h-10 w-full bg-white text-green-700 border-green-200 hover:bg-green-50" onClick={(e) => { e.stopPropagation(); void doApprove(l.poultryLossRecordId) }}>
                                <CheckCircle2 className="h-4 w-4 mr-2" /> Approve
                              </Button>
                              <Button variant="outline" size="sm" className="h-10 w-full bg-white" onClick={(e) => { e.stopPropagation(); openEdit(l) }}>
                                <Pencil className="h-4 w-4 mr-2" /> Edit
                              </Button>
                              <Button variant="outline" size="sm" className="col-span-2 h-10 w-full bg-white text-red-600 border-red-200 hover:bg-red-50" onClick={(e) => { e.stopPropagation(); setDelTarget(l) }}>
                                <Trash2 className="h-4 w-4 mr-2" /> Delete
                              </Button>
                            </> : (
                              <Button variant="outline" size="sm" className="col-span-2 h-10 w-full bg-white text-amber-700 border-amber-200 hover:bg-amber-50" onClick={(e) => { e.stopPropagation(); void doUnapprove(l.poultryLossRecordId) }}>
                                <Undo2 className="h-4 w-4 mr-2" /> Unapprove
                              </Button>
                            )}
                          </div>
                        </div>
                      </CollapsibleContent>
                    </div>
                  </Collapsible>
                )})())}
                <div className="rounded-lg border bg-slate-50/60 px-4 py-2">
                  <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowTableMobile(true)}>
                    View table format <ChevronDown className="h-4 w-4 ml-1" />
                  </Button>
                </div>
              </div>
              )
              ) : (
              <>
              {isMobile && (
                <div className="-mx-4 mb-3 flex items-center justify-between gap-2 border-b bg-slate-50 px-4 py-2">
                  <span className="text-xs text-slate-600">Table view • Scroll → for more</span>
                  <Button variant="ghost" size="sm" onClick={() => setShowTableMobile(false)}>
                    <ChevronUp className="h-4 w-4 mr-1" /> Cards
                  </Button>
                </div>
              )}
              <div className="overflow-x-auto -mx-4 px-4"><Table className="min-w-[640px]">
                <TableHeader><TableRow>
                  {([["date", "Date", ""], ["type", "Type", ""], ["product", "Product", ""], ["qty", "Qty", "text-right"], ["value", "Value", "text-right"], ["status", "Status", ""]] as const).map(([k, label, cls]) => (
                    <SortableHeader key={k} label={label} sortKey={k} currentSort={sortKey} currentDirection={sortDir} onSort={onSort} className={cls} />
                  ))}
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {shown.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">{rows.length === 0 ? "No loss records yet." : "No records match these filters."}</TableCell></TableRow>
                    : pg.pageItems.map((row) => row.kind === "auto" ? (
                      <TableRow key={row.key} className="bg-slate-50/60">
                        <TableCell>{fmtDateTime(row.a.lossDate)}</TableCell>
                        <TableCell>{row.a.lossType}<div className="text-xs text-slate-500">from {row.a.sourceLabel}</div></TableCell>
                        <TableCell>{row.a.productName}{row.a.reason && <div className="text-xs text-slate-500">{row.a.reason}</div>}</TableCell>
                        <TableCell className="text-right">{row.a.quantity.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{row.a.estimatedValue != null ? gh(row.a.estimatedValue) : "—"}</TableCell>
                        <TableCell><Badge className="bg-slate-200 text-slate-700">Automatic</Badge></TableCell>
                        <TableCell className="text-right">
                          {row.a.href && <Button asChild variant="ghost" size="sm" title={`Open ${row.a.sourceLabel}`}><Link href={row.a.href}><ExternalLink className="w-4 h-4" /></Link></Button>}
                        </TableCell>
                      </TableRow>
                    ) : (() => { const l = row.l; return (
                      <TableRow key={row.key}>
                        <TableCell>{fmtDateTime(l.lossDate, l)}</TableCell>
                        <TableCell>{l.lossType}</TableCell>
                        <TableCell>{l.productName ?? "—"}</TableCell>
                        <TableCell className="text-right">{l.quantity?.toLocaleString() ?? "—"}</TableCell>
                        <TableCell className="text-right">{l.estimatedValue != null ? gh(l.estimatedValue) : "—"}</TableCell>
                        <TableCell>{l.status === "Approved" ? <Badge className="bg-green-100 text-green-700">Approved</Badge> : <Badge className="bg-amber-100 text-amber-700">Pending</Badge>}</TableCell>
                        <TableCell className="text-right">
                          {l.status === "Pending" ? <>
                            <Button variant="ghost" size="sm" onClick={() => doApprove(l.poultryLossRecordId)} title="Approve"><CheckCircle2 className="w-4 h-4 text-green-600" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => openEdit(l)}><Pencil className="w-4 h-4" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDelTarget(l)}><Trash2 className="w-4 h-4 text-red-500" /></Button>
                          </> : <Button variant="ghost" size="sm" onClick={() => doUnapprove(l.poultryLossRecordId)} title="Unapprove"><Undo2 className="w-4 h-4 text-amber-600" /></Button>}
                        </TableCell>
                      </TableRow>
                    )})())}
                </TableBody>
              </Table></div>
              </>
            )}
            <DataPagination {...pg.paginationProps} />
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>{editId ? "Edit loss record" : "New loss record"}</DialogTitle></DialogHeader>
          <FormSection title="Loss details" color="amber">
            <FormField label="Date"><Input type="date" value={form.lossDate} onChange={(e) => setForm({ ...form, lossDate: e.target.value })} /></FormField>
            <FormField label="Type">
              <Select value={form.lossType} onValueChange={(v) => setForm({ ...form, lossType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{LOSS_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Product (optional)">
              <Select value={form.poultryProductId ? String(form.poultryProductId) : "0"} onValueChange={(v) => setForm({ ...form, poultryProductId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent><SelectItem value="0">—</SelectItem>{products.map((p) => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity"><NumberInput min={0} step="0.001" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Estimated value"><NumberInput min={0} step="0.01" value={form.estimatedValue} onChange={(e) => setForm({ ...form, estimatedValue: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Reason" full><ReasonSelect options={LOSS_REASONS} value={form.reason} onChange={(v: string) => setForm({ ...form, reason: v })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog open={!!delTarget} onOpenChange={(o) => !o && setDelTarget(null)} onConfirm={confirmDelete} title="Delete loss record?" description="This removes the pending record." />
    </div>
  )
}

function LossFilter({ label, value, onChange, allLabel, options }: {
  label: string; value: string; onChange: (v: string) => void; allLabel: string; options: string[]
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger aria-label={label} title={label} className={cn("h-9", value !== "ALL" && "border-blue-300 bg-blue-50")}>
        <SelectValue placeholder={allLabel} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="ALL">{allLabel}</SelectItem>
        {options.map((o) => <SelectItem key={o} value={o}>{o}</SelectItem>)}
      </SelectContent>
    </Select>
  )
}

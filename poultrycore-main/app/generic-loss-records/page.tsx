"use client"

// Generic Loss & Damage Tracker — track damaged, spoiled, stolen, or lost products.
// Uses stock adjustments with "Decrease" type to record losses.

import { STOCK_ADJUSTMENT_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { NumberInput } from "@/components/ui/number-input"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Plus, Loader2, AlertTriangle, Trash2, Package } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  getProducts, getStockAdjustments, createStockAdjustment,
  submitStockAdjustment, approveStockAdjustment,
  type GenericProduct, type GenericStockAdjustment,
} from "@/lib/api/generic"

const LOSS_TYPES = [
  { value: "Damage", label: "Damage" },
  { value: "Spoilage", label: "Spoilage / Expired" },
  { value: "Theft", label: "Theft" },
  { value: "MissingStock", label: "Missing Stock" },
  { value: "Breakage", label: "Breakage" },
  { value: "Other", label: "Other" },
]

export default function GenericLossRecordsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [loading, setLoading] = useState(true)
  const [adjustments, setAdjustments] = useState<GenericStockAdjustment[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  // Dialog
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    genericProductId: "",
    lossType: "Damage",
    quantity: "0",
    reason: "",
    lossDate: new Date().toISOString().slice(0, 10),
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [adj, prods] = await Promise.all([
        getStockAdjustments(null),
        getProducts(),
      ])
      // Only show Decrease adjustments (losses)
      setAdjustments(adj.filter((a) => a.adjustmentType === "Decrease"))
      setProducts(prods.filter((p) => p.isActive && p.trackInventory))
    } catch (e: any) {
      toast({ title: "Could not load", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  const filtered = useMemo(() => {
    return filterByDateAndSearch(adjustments, {
      search, dateFrom, dateTo,
      searchKeys: ["productName", "reason"],
      dateKey: "adjustmentDate",
    })
  }, [adjustments, search, dateFrom, dateTo])

  const pg = usePagination(filtered)

  const stats = useMemo(() => {
    const approved = adjustments.filter((a) => a.status === "Approved")
    return {
      total: adjustments.length,
      totalQty: approved.reduce((s, a) => s + a.quantity, 0),
      pending: adjustments.filter((a) => a.status === "Draft" || a.status === "Submitted").length,
    }
  }, [adjustments])

  async function onSave() {
    const qty = Number(form.quantity)
    if (!form.genericProductId || qty <= 0 || !form.reason.trim()) {
      toast({ title: "Fill all required fields", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      const created = await createStockAdjustment({
        genericProductId: Number(form.genericProductId),
        adjustmentType: "Decrease",
        quantity: qty,
        reason: `[${form.lossType}] ${form.reason}`,
        adjustmentDate: form.lossDate || null,
        notes: form.notes || null,
      })
      if (created?.genericStockAdjustmentId) {
        await submitStockAdjustment(created.genericStockAdjustmentId).catch(() => {})
        await approveStockAdjustment(created.genericStockAdjustmentId).catch(() => {})
      }
      toast({ title: "Loss recorded" })
      setOpen(false)
      setForm({ genericProductId: "", lossType: "Damage", quantity: "0", reason: "", lossDate: new Date().toISOString().slice(0, 10), notes: "" })
      await load()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  const lossTypeFromReason = (reason: string) => {
    const match = reason.match(/^\[(\w+)\]/)
    return match ? match[1] : "Other"
  }

  const lossTypeBadge = (type: string) => {
    switch (type) {
      case "Damage": return <Badge className="bg-red-100 text-red-800">Damage</Badge>
      case "Spoilage": return <Badge className="bg-amber-100 text-amber-800">Spoilage</Badge>
      case "Theft": return <Badge className="bg-rose-100 text-rose-800">Theft</Badge>
      case "MissingStock": return <Badge className="bg-orange-100 text-orange-800">Missing</Badge>
      case "Breakage": return <Badge className="bg-purple-100 text-purple-800">Breakage</Badge>
      default: return <Badge className="bg-slate-100 text-slate-800">{type}</Badge>
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
                <AlertTriangle className="h-6 w-6 text-red-600" /> Loss &amp; Damage Tracker
              </h1>
              <p className="text-sm text-slate-500">Track damaged, spoiled, stolen, or lost products.</p>
            </div>
            <Button onClick={() => setOpen(true)}><Plus className="w-4 h-4 mr-1" /> Record Loss</Button>
          </div>

          <div className="grid grid-cols-3 gap-3">
            <div className="rounded-xl border bg-white p-3 shadow-sm">
              <div className="text-[11px] font-medium uppercase text-slate-500">Total records</div>
              <div className="mt-1 text-xl font-bold">{stats.total}</div>
            </div>
            <div className="rounded-xl border border-red-200 bg-white p-3 shadow-sm">
              <div className="text-[11px] font-medium uppercase text-slate-500">Units lost</div>
              <div className="mt-1 text-xl font-bold text-red-600 tabular-nums">{stats.totalQty.toLocaleString()}</div>
            </div>
            <div className="rounded-xl border bg-white p-3 shadow-sm">
              <div className="text-[11px] font-medium uppercase text-slate-500">Pending</div>
              <div className="mt-1 text-xl font-bold text-amber-700">{stats.pending}</div>
            </div>
          </div>

          <ListFilters search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search product or reason" />

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Product</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead className="text-right">Quantity</TableHead>
                      <TableHead>Reason</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.length === 0 ? (
                      <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-8">No loss records yet.</TableCell></TableRow>
                    ) : pg.pageItems.map((a) => {
                      const type = lossTypeFromReason(a.reason)
                      const cleanReason = a.reason.replace(/^\[\w+\]\s*/, "")
                      return (
                        <TableRow key={a.genericStockAdjustmentId}>
                          <TableCell className="whitespace-nowrap text-sm">{fmtDateTime(a.adjustmentDate, a)}</TableCell>
                          <TableCell className="font-medium">{a.productName ?? "—"}</TableCell>
                          <TableCell>{lossTypeBadge(type)}</TableCell>
                          <TableCell className="text-right tabular-nums text-red-600 font-medium">-{a.quantity.toLocaleString()}</TableCell>
                          <TableCell className="text-sm">{cleanReason}</TableCell>
                          <TableCell>
                            <Badge className={a.status === "Approved" ? "bg-emerald-100 text-emerald-800" : a.status === "Rejected" ? "bg-rose-100 text-rose-800" : "bg-slate-100 text-slate-800"}>
                              {a.status}
                            </Badge>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
          <DataPagination {...pg.paginationProps} />
        </main>
      </div>

      {/* Record Loss dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Record Loss / Damage</DialogTitle></DialogHeader>
          <FormSection title="Loss details" color="red">
            <FormField label="Product *">
              <Select value={form.genericProductId} onValueChange={(v) => setForm({ ...form, genericProductId: v })}>
                <SelectTrigger><SelectValue placeholder="Select product" /></SelectTrigger>
                <SelectContent>
                  {products.map((p) => (
                    <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                      {p.productName} ({(p.currentStock ?? 0).toLocaleString()} {p.unitOfMeasure ?? ""})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Loss type *">
              <Select value={form.lossType} onValueChange={(v) => setForm({ ...form, lossType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {LOSS_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Quantity lost *">
              <NumberInput min={0} step="1" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: e.target.value })} />
            </FormField>
            <FormField label="Reason *">
              <ReasonSelect options={STOCK_ADJUSTMENT_REASONS} value={form.reason} onChange={(v) => setForm({ ...form, reason: v })} placeholder="Select or type a reason" />
            </FormField>
            <FormField label="Date">
              <Input type="date" value={form.lossDate} onChange={(e) => setForm({ ...form, lossDate: e.target.value })} />
            </FormField>
            <FormField label="Notes">
              <Textarea rows={2} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} placeholder="Optional notes" />
            </FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={onSave} disabled={saving} className="bg-red-600 hover:bg-red-700">
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Trash2 className="w-4 h-4 mr-1" /> Record Loss</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

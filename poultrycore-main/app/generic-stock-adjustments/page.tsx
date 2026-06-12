"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Check, Boxes, Loader2, Plus, ArrowUpCircle, ArrowDownCircle, X } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  approveStockAdjustment, createStockAdjustment, getProducts, getStockAdjustments,
  rejectStockAdjustment, submitStockAdjustment,
  type GenericProduct, type GenericStockAdjustment,
} from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

const STATUS_FILTERS = ["All", "Draft", "Submitted", "Approved", "Rejected"] as const

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Submitted": return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    case "Rejected":  return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericStockAdjustmentsPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const status = sp.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [rows, setRows] = useState<GenericStockAdjustment[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // Reject target — opens the PromptDialog with a typed reason (replaces window.prompt).
  const [rejectTarget, setRejectTarget] = useState<number | null>(null)

  const [form, setForm] = useState({
    genericProductId: "",
    adjustmentType: "Increase" as "Increase" | "Decrease",
    quantity: "0",
    reason: "",
    adjustmentDate: new Date().toISOString().slice(0, 10),
    notes: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      const [as, ps] = await Promise.all([
        getStockAdjustments(status === "All" ? null : status),
        getProducts(),
      ])
      setRows(as); setProducts(ps)
    } catch (e: any) {
      toast({ title: "Could not load", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, status])

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["productName", "reason", "notes"],
      dateKey: "adjustmentDate",
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onSave = async () => {
    if (!form.genericProductId) { toast({ title: "Pick a product", variant: "destructive" }); return }
    if (!form.reason.trim()) { toast({ title: "Reason is required", variant: "destructive" }); return }
    const qty = Number(form.quantity)
    if (!(qty > 0)) { toast({ title: "Quantity must be greater than zero", variant: "destructive" }); return }
    setSaving(true)
    try {
      const created = await createStockAdjustment({
        genericProductId: Number(form.genericProductId),
        adjustmentType: form.adjustmentType,
        quantity: qty,
        reason: form.reason,
        adjustmentDate: form.adjustmentDate,
        notes: form.notes || null,
      })
      if (created) {
        // Auto-submit so it's ready to approve.
        await submitStockAdjustment(created.genericStockAdjustmentId)
        toast({ title: `Adjustment #${created.genericStockAdjustmentId} created and submitted.` })
        setOpen(false)
        setForm({ genericProductId: "", adjustmentType: "Increase", quantity: "0", reason: "", adjustmentDate: new Date().toISOString().slice(0, 10), notes: "" })
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not create adjustment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const onApprove = async (id: number) => {
    try { await approveStockAdjustment(id); toast({ title: `Adjustment #${id} approved. Stock updated.` }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" }) }
  }

  const onReject = (id: number) => setRejectTarget(id)

  const confirmReject = async (reason: string) => {
    if (rejectTarget == null) return
    try {
      await rejectStockAdjustment(rejectTarget, reason)
      toast({ title: `Adjustment #${rejectTarget} rejected.` })
      setRejectTarget(null); await load()
    } catch (e: any) {
      toast({ title: "Reject failed", description: e?.message ?? String(e), variant: "destructive" })
      throw e
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Boxes className="h-6 w-6 text-cyan-600" /> Stock adjustments
              </h1>
              <p className="text-sm text-slate-500">Manually increase / decrease stock with a reason. Approval writes the matching movement.</p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild><Button className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />New adjustment</Button></DialogTrigger>
              <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <Boxes className="w-5 h-5 text-blue-600" /> New stock adjustment
                  </DialogTitle>
                  <DialogDescription>Adjustment lands as Submitted. Approve to commit it to inventory.</DialogDescription>
                </DialogHeader>
                <div className="space-y-4">
                  <FormSection title="Product" color="indigo" columns={1}>
                    <FormField label="Product *">
                      <Select value={form.genericProductId} onValueChange={(v) => setForm((f) => ({ ...f, genericProductId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Pick product..." /></SelectTrigger>
                        <SelectContent>
                          {products.filter((p) => p.trackInventory).map((p) => (
                            <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                              {p.productName} – current: {p.currentStock}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                  </FormSection>

                  <FormSection title="Adjustment details" color="blue">
                    <FormField label="Type *">
                      <Select value={form.adjustmentType} onValueChange={(v) => setForm((f) => ({ ...f, adjustmentType: v as "Increase" | "Decrease" }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="Increase">Increase (+)</SelectItem>
                          <SelectItem value="Decrease">Decrease (−)</SelectItem>
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Quantity *">
                      <NumberInput step="0.001" min="0" value={form.quantity} onChange={(e) => setForm((f) => ({ ...f, quantity: e.target.value }))} />
                    </FormField>
                    <FormField label="Date" full>
                      <Input type="date" value={form.adjustmentDate} onChange={(e) => setForm((f) => ({ ...f, adjustmentDate: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Reason & notes" color="amber" columns={1}>
                    <FormField label="Reason *">
                      <Input maxLength={500} value={form.reason} onChange={(e) => setForm((f) => ({ ...f, reason: e.target.value }))} placeholder="e.g. damaged in storage, found extras, stocktake correction" />
                    </FormField>
                    <FormField label="Notes">
                      <Textarea rows={2} maxLength={1000} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <div className="flex gap-3 justify-end pt-2">
                    <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Create & submit"}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-stock-adjustments" : `/generic-stock-adjustments?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No stock adjustments yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search product, reason or notes"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(a) => a.genericStockAdjustmentId}
                  primary={(a) => `#${a.genericStockAdjustmentId} · ${a.productName ?? `#${a.genericProductId}`}`}
                  secondary={(a) => (
                    <>
                      <span>{new Date(a.adjustmentDate).toLocaleDateString()}</span>
                      <span>·</span>
                      {a.adjustmentType === "Increase"
                        ? <span className="inline-flex items-center text-emerald-700"><ArrowUpCircle className="h-3 w-3 mr-1" />+{a.quantity}</span>
                        : <span className="inline-flex items-center text-rose-700"><ArrowDownCircle className="h-3 w-3 mr-1" />-{a.quantity}</span>}
                    </>
                  )}
                  trailing={(a) => <Badge className={badgeClass(a.status)}>{a.status}</Badge>}
                  details={(a) => [
                    { label: "Date", value: new Date(a.adjustmentDate).toLocaleDateString() },
                    { label: "Product", value: a.productName ?? `#${a.genericProductId}` },
                    { label: "Type", value: a.adjustmentType === "Increase"
                      ? <span className="inline-flex items-center text-emerald-700"><ArrowUpCircle className="h-3 w-3 mr-1" />Increase</span>
                      : <span className="inline-flex items-center text-rose-700"><ArrowDownCircle className="h-3 w-3 mr-1" />Decrease</span> },
                    { label: "Qty", value: a.quantity },
                    { label: "Reason", value: a.reason },
                  ]}
                  actions={(a) => (
                    <>
                      {a.status === "Submitted" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => onApprove(a.genericStockAdjustmentId)}>
                            <Check className="h-4 w-4 mr-1" /> Approve
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => onReject(a.genericStockAdjustmentId)}>
                            <X className="h-4 w-4 mr-1" /> Reject
                          </Button>
                        </>
                      )}
                      {a.status === "Draft" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10" onClick={async () => { try { await submitStockAdjustment(a.genericStockAdjustmentId); toast({ title: "Submitted." }); await load() } catch (e: any) { toast({ title: "Submit failed", description: e?.message ?? String(e), variant: "destructive" }) } }}>Submit</Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>#</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Product</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="text-right">Qty</TableHead>
                          <TableHead>Reason</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((a) => (
                          <TableRow key={a.genericStockAdjustmentId}>
                            <TableCell>#{a.genericStockAdjustmentId}</TableCell>
                            <TableCell>{new Date(a.adjustmentDate).toLocaleDateString()}</TableCell>
                            <TableCell>{a.productName ?? `#${a.genericProductId}`}</TableCell>
                            <TableCell>
                              {a.adjustmentType === "Increase"
                                ? <span className="inline-flex items-center text-emerald-700"><ArrowUpCircle className="h-3 w-3 mr-1" />Increase</span>
                                : <span className="inline-flex items-center text-rose-700"><ArrowDownCircle className="h-3 w-3 mr-1" />Decrease</span>}
                            </TableCell>
                            <TableCell className="text-right">{a.quantity}</TableCell>
                            <TableCell className="max-w-xs truncate" title={a.reason}>{a.reason}</TableCell>
                            <TableCell><Badge className={badgeClass(a.status)}>{a.status}</Badge></TableCell>
                            <TableCell className="flex gap-1">
                              {a.status === "Submitted" && (
                                <>
                                  <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => onApprove(a.genericStockAdjustmentId)}><Check className="h-3 w-3 mr-1" />Approve</Button>
                                  <Button size="sm" variant="outline" onClick={() => onReject(a.genericStockAdjustmentId)}><X className="h-3 w-3 mr-1" />Reject</Button>
                                </>
                              )}
                              {a.status === "Draft" && (
                                <Button size="sm" onClick={async () => { try { await submitStockAdjustment(a.genericStockAdjustmentId); toast({ title: "Submitted." }); await load() } catch (e: any) { toast({ title: "Submit failed", description: e?.message ?? String(e), variant: "destructive" }) } }}>Submit</Button>
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
            </>
          )}
        </main>
      </div>

      <PromptDialog
        open={rejectTarget != null}
        onOpenChange={(v) => { if (!v) setRejectTarget(null) }}
        title="Reject stock adjustment"
        description={rejectTarget ? `Adjustment #${rejectTarget} will be rejected. Tell the originator why.` : ""}
        label="Rejection reason"
        placeholder="e.g. wrong product, count looks off, missing receipt…"
        confirmLabel="Reject"
        confirmVariant="destructive"
        onSubmit={confirmReject}
      />
    </div>
  )
}

export default function GenericStockAdjustmentsPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericStockAdjustmentsPageInner />
    </Suspense>
  )
}

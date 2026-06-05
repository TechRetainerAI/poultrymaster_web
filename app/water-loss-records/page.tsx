"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, AlertTriangle, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterLossRecords, createWaterLossRecord, approveWaterLossRecord,
  updateWaterLossRecord, unapproveWaterLossRecord,
  listWaterProducts, type WaterLossRecord, type WaterProduct,
} from "@/lib/api/water"
import { fmtMoney, useCurrency } from "@/lib/currency"
import { Pencil, Undo2 } from "lucide-react"
import { PromptDialog } from "@/components/ui/prompt-dialog"

const gh = (n: number) => fmtMoney(n)

const LOSS_TYPES = [
  "ProductionDamage","DamagedBags","RejectedSachets","BurstSachets",
  "ReturnedBags","MachineWaste","PackagingWaste","DriverShortage",
  "MissingStock","BadDebt","Other",
]
const STATUS_COLOR: Record<string, string> = {
  Pending:  "bg-amber-100 text-amber-700",
  Approved: "bg-green-100 text-green-700",
  Reopened: "bg-amber-100 text-amber-700",
  Draft:    "bg-slate-100 text-slate-700",
}

export default function WaterLossRecordsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  // Column-header / Stat-card unit suffix. Hardcoding " (GHC)" leaked the
  // currency symbol even when the user toggled "Show currency symbol" off in
  // setup (and was always wrong when the currency wasn't GHC). Drive it from
  // the same store fmtMoney reads so labels and values flip together.
  const { symbol, showSymbol } = useCurrency()
  // James (2026-05-30): currency symbols belong on the *values* (driven by
  // fmtMoney + the showCurrencySymbol toggle), never duplicated into the
  // column header. Force empty so headers stay clean regardless of toggle.
  const cur = ""

  const [items, setItems] = useState<WaterLossRecord[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [typeFilter, setTypeFilter] = useState<string>("ALL")
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({
    lossDate: new Date().toISOString().split("T")[0],
    lossType: "DamagedBags",
    waterProductId: 0,
    quantityBags: 0,
    quantitySachets: 0,
    estimatedValue: 0,
    reason: "",
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, typeFilter])

  async function load() {
    setLoading(true)
    try {
      const [ls, ps] = await Promise.all([
        listWaterLossRecords(typeFilter === "ALL" ? undefined : { lossType: typeFilter }),
        listWaterProducts(),
      ])
      setItems(ls); setProducts(ps)
    } catch (e: any) { toast({ title: "Could not load loss records", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setForm({
      lossDate: new Date().toISOString().split("T")[0],
      lossType: "DamagedBags",
      waterProductId: products[0]?.waterProductId ?? 0,
      quantityBags: 0, quantitySachets: 0, estimatedValue: 0, reason: "", notes: "",
    })
    setOpen(true)
  }

  async function save() {
    if (!form.reason.trim()) return toast({ title: "Reason required", variant: "destructive" })
    try {
      const payload = {
        ...form,
        waterProductId: form.waterProductId || null,
        quantityBags: form.quantityBags || null,
        quantitySachets: form.quantitySachets || null,
        estimatedValue: form.estimatedValue || null,
      } as any
      if (editingId != null) {
        await updateWaterLossRecord(editingId, payload)
        toast({ title: "Loss updated" })
      } else {
        await createWaterLossRecord(payload)
        toast({ title: "Loss recorded — pending approval" })
      }
      setOpen(false); setEditingId(null); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
  }

  async function approve(l: WaterLossRecord) {
    try { await approveWaterLossRecord(l.waterLossRecordId); toast({ title: "Loss approved" }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  // Migration 068 — edit pending loss inline. We reuse the same form modal,
  // populating it from the loss row + flipping into edit mode.
  const [editingId, setEditingId] = useState<number | null>(null)
  const [unapproveTarget, setUnapproveTarget] = useState<WaterLossRecord | null>(null)

  function openEdit(l: WaterLossRecord) {
    setEditingId(l.waterLossRecordId)
    setForm({
      lossDate:        l.lossDate.split("T")[0],
      lossType:        l.lossType,
      waterProductId:  l.waterProductId ?? 0,
      quantityBags:    l.quantityBags ?? 0,
      quantitySachets: l.quantitySachets ?? 0,
      estimatedValue:  l.estimatedValue ?? 0,
      reason:          l.reason ?? "",
      notes:           l.notes ?? "",
    })
    setOpen(true)
  }

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["lossType", "reason", "notes"],
      dateKey: "lossDate",
    }),
    [items, search, dateFrom, dateTo],
  )

  const totals = useMemo(() => {
    const approved = items.filter(i => i.status === "Approved")
    return {
      approvedValue: approved.reduce((s, i) => s + (i.estimatedValue ?? 0), 0),
      approvedBags: approved.reduce((s, i) => s + (i.quantityBags ?? 0), 0),
      pending: items.filter(i => i.status !== "Approved").length,
    }
  }, [items])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Prompt 2 §9 + §10 — page order is now:
              1. Title + primary action
              2. Filters (incl. Type dropdown)
              3. Score cards
              4. Table */}
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <AlertTriangle className="h-6 w-6 text-rose-600" /> Loss records
            </h1>
            <Button onClick={() => { setEditingId(null); openNew() }}>
              <Plus className="h-4 w-4 mr-1" /> Record loss
            </Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search loss type, reason or notes"
            extras={(
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All types</SelectItem>
                  {LOSS_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                </SelectContent>
              </Select>
            )}
          />

          <div className="mt-3 mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved value</div><div className="text-xl font-semibold tabular-nums">{gh(totals.approvedValue)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved bags lost</div><div className="text-xl font-semibold">{totals.approvedBags}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Pending</div><div className="text-xl font-semibold">{totals.pending}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total records</div><div className="text-xl font-semibold">{items.length}</div></CardContent></Card>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No losses recorded yet.</div>
              ) : (
                <MobileCardList
                  items={visibleItems}
                  getKey={(l) => l.waterLossRecordId}
                  primary={(l) => `${l.lossType} · ${gh(l.estimatedValue ?? 0)}`}
                  secondary={(l) => (
                    <>
                      <span>{l.lossDate.split("T")[0]}</span>
                      <Badge className={STATUS_COLOR[l.status ?? "Pending"] ?? ""}>{l.status ?? "Pending"}</Badge>
                    </>
                  )}
                  details={(l) => [
                    { label: "Date", value: l.lossDate.split("T")[0] },
                    { label: "Type", value: l.lossType },
                    { label: "Bags", value: l.quantityBags ?? 0 },
                    { label: "Sachets", value: l.quantitySachets ?? 0 },
                    { label: "Value", value: gh(l.estimatedValue ?? 0) },
                    { label: "Status", value: l.status ?? "Pending" },
                    { label: "Reason", value: l.reason ?? "—" },
                  ]}
                  actions={(l) => (
                    <>
                      {/* Pending records can be edited inline (Prompt 2 §11). */}
                      {l.status !== "Approved" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(l)}>
                          <Pencil className="h-4 w-4 mr-1" /> Edit
                        </Button>
                      )}
                      {l.status !== "Approved" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => approve(l)}>
                          <CheckCircle2 className="h-4 w-4 mr-1" /> Approve
                        </Button>
                      )}
                      {/* Approved → Unapprove (with reason) so the record can
                          be edited and re-approved. */}
                      {l.status === "Approved" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => setUnapproveTarget(l)}>
                          <Undo2 className="h-4 w-4 mr-1" /> Unapprove
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Bags</TableHead><TableHead className="text-right">Sachets</TableHead><TableHead className="text-right">Value</TableHead><TableHead>Reason</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleItems.map((l) => (
                          <TableRow key={l.waterLossRecordId}>
                            <TableCell>{l.lossDate.split("T")[0]}</TableCell>
                            <TableCell><Badge variant="outline">{l.lossType}</Badge></TableCell>
                            <TableCell className="text-right tabular-nums">{l.quantityBags ?? 0}</TableCell>
                            <TableCell className="text-right tabular-nums">{l.quantitySachets ?? 0}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(l.estimatedValue ?? 0)}</TableCell>
                            <TableCell className="max-w-sm whitespace-normal break-words align-top">{l.reason ?? "—"}</TableCell>
                            <TableCell><Badge className={STATUS_COLOR[l.status ?? "Pending"] ?? ""}>{l.status ?? "Pending"}</Badge></TableCell>
                            <TableCell className="text-right whitespace-nowrap">
                              {l.status !== "Approved" && <Button size="sm" variant="ghost" onClick={() => openEdit(l)} title="Edit"><Pencil className="h-4 w-4" /></Button>}
                              {l.status !== "Approved" && <Button size="sm" variant="ghost" onClick={() => approve(l)} title="Approve"><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
                              {l.status === "Approved" && <Button size="sm" variant="ghost" onClick={() => setUnapproveTarget(l)} title="Unapprove"><Undo2 className="h-4 w-4 text-amber-600" /></Button>}
                            </TableCell>
                          </TableRow>
                        ))}
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

      <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditingId(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-rose-600" />
              {editingId != null ? "Edit loss record" : "Record loss"}
            </DialogTitle>
            <DialogDescription>
              {editingId != null
                ? "Update the loss details. Approved records must be Unapproved first."
                : "Log a loss for review and approval"}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Basics" color="indigo">
              <FormField label="Date">
                <Input type="date" value={form.lossDate} onChange={(e) => setForm({ ...form, lossDate: e.target.value })} />
              </FormField>
              <FormField label="Loss type">
                <Select value={form.lossType} onValueChange={(v) => setForm({ ...form, lossType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{LOSS_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Product" full>
                <Select value={String(form.waterProductId)} onValueChange={(v) => setForm({ ...form, waterProductId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="(optional)" /></SelectTrigger>
                  <SelectContent>{products.map(p => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Quantity & Value" color="blue">
              <FormField label="Bags">
                <NumberInput min={0} value={form.quantityBags} onChange={(e) => setForm({ ...form, quantityBags: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Sachets">
                <NumberInput min={0} value={form.quantitySachets} onChange={(e) => setForm({ ...form, quantitySachets: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label={`Estimated value${cur}`} full>
                <NumberInput min={0} step="0.01" value={form.estimatedValue} onChange={(e) => setForm({ ...form, estimatedValue: Number(e.target.value) || 0 })} />
              </FormField>
            </FormSection>

            <FormSection title="Details" color="slate" columns={1}>
              <FormField label="Reason *">
                <Textarea value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
              </FormField>
              <FormField label="Notes">
                <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save}>{editingId != null ? "Save changes" : "Record"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Migration 068 — Unapprove an Approved record with a reason. */}
      <PromptDialog
        open={!!unapproveTarget}
        onOpenChange={(o) => { if (!o) setUnapproveTarget(null) }}
        title="Unapprove this loss record?"
        description={unapproveTarget
          ? <>This will flip <span className="font-medium">{unapproveTarget.lossType}</span> from Approved back to Pending so the record can be edited and approved again. Cash impact (if any) is reversed.</>
          : undefined}
        label="Reason for unapproving"
        placeholder="e.g. corrected reason / wrong quantity"
        confirmLabel="Unapprove"
        confirmVariant="destructive"
        onSubmit={async (reason) => {
          if (!unapproveTarget) return
          try {
            await unapproveWaterLossRecord(unapproveTarget.waterLossRecordId, reason)
            toast({ title: "Loss unapproved — now editable" })
            setUnapproveTarget(null); await load()
          } catch (e: any) {
            toast({ title: "Unapprove failed", description: e?.message, variant: "destructive" })
          }
        }}
      />
    </div>
  )
}

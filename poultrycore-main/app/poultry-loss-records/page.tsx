"use client"

import { useEffect, useState } from "react"
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
import { Plus, Pencil, Loader2, Trash2, CheckCircle2, Undo2, ChevronDown, ChevronUp } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryLossRecords, createPoultryLossRecord, updatePoultryLossRecord, approvePoultryLossRecord, unapprovePoultryLossRecord, deletePoultryLossRecord,
  listPoultryProducts, type PoultryLossRecord, type PoultryProduct,
} from "@/lib/api/poultry-inventory"

const LOSS_TYPES = ["Damage", "Mortality", "Theft", "Spoilage", "MissingStock", "Other"]
const EMPTY = { lossDate: new Date().toISOString().split("T")[0], lossType: "Damage", poultryProductId: 0, quantity: 0, estimatedValue: 0, reason: "", notes: "" }

export default function PoultryLossRecordsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [rows, setRows] = useState<PoultryLossRecord[]>([])
  const pg = usePagination(rows)
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
    try { const [ls, ps] = await Promise.all([listPoultryLossRecords(), listPoultryProducts()]); setRows(ls); setProducts(ps) }
    catch (e: any) { toast({ title: "Could not load loss records", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
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
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Loss & Damage Records</h1><p className="text-sm text-slate-500">Manual losses — damages, mortality, spoilage, missing stock.</p></div>
            <Button onClick={openNew}><Plus className="w-4 h-4 mr-1" /> New record</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
              : isMobile && !showTableMobile ? (
              rows.length === 0 ? <div className="py-8 text-center text-slate-500">No loss records yet.</div> : (
              <div className="space-y-3">
                {pg.pageItems.map((l, idx) => (
                  <Collapsible
                    key={l.poultryLossRecordId}
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
                                <span className="font-semibold text-slate-900">{(l.lossDate || "").split("T")[0]}</span>
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
                ))}
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
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Product</TableHead><TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Value</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow></TableHeader>
                <TableBody>
                  {rows.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No loss records yet.</TableCell></TableRow>
                    : pg.pageItems.map((l) => (
                      <TableRow key={l.poultryLossRecordId}>
                        <TableCell>{(l.lossDate || "").split("T")[0]}</TableCell>
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
                    ))}
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
            <FormField label="Reason" full><Input value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></FormField>
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

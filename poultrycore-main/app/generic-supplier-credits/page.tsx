"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { HandCoins, Plus, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getSupplierCredits, createSupplierCredit, getSuppliers, type GenericSupplierCredit, type GenericSupplier } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const CREDIT_TYPES = ["Advance", "CreditNote", "Overpayment", "Refund"]
const TYPE_COLORS: Record<string, string> = { Advance: "bg-indigo-100 text-indigo-700", CreditNote: "bg-violet-100 text-violet-700", Overpayment: "bg-blue-100 text-blue-700", Refund: "bg-amber-100 text-amber-700" }
const STATUS_COLORS: Record<string, string> = { Active: "bg-emerald-100 text-emerald-700", Used: "bg-slate-100 text-slate-700" }

export default function GenericSupplierCreditsPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericSupplierCredit[]>([])
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [loading, setLoading] = useState(true)
  const [createOpen, setCreateOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ genericSupplierId: 0, creditType: "Advance", amount: 0, creditDate: new Date().toISOString().split("T")[0], notes: "" })

  const pg = usePagination(rows)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [credits, supps] = await Promise.all([getSupplierCredits(), getSuppliers()])
      setRows(credits); setSuppliers(supps)
    } catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const totals = useMemo(() => {
    let total = 0, active = 0, used = 0
    for (const s of rows) { total += s.amount; if (s.status === "Active") active += s.remainingBalance; else used += s.amount - s.remainingBalance }
    return { total, active, used }
  }, [rows])

  async function doCreate() {
    if (!form.genericSupplierId) { toast({ title: "Select a supplier", variant: "destructive" }); return }
    if (form.amount <= 0) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createSupplierCredit(form)
      toast({ title: "Credit recorded" })
      setCreateOpen(false)
      setForm({ genericSupplierId: 0, creditType: "Advance", amount: 0, creditDate: new Date().toISOString().split("T")[0], notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2"><HandCoins className="h-5 w-5 text-emerald-600" /> Supplier Credits & Advances</h1>
              <p className="text-xs text-slate-500">Credit held with suppliers, advance payments and credit notes.</p>
            </div>
            <Button onClick={() => setCreateOpen(true)}><Plus className="h-4 w-4 mr-1" /> New Credit</Button>
          </div>

          <div className="grid grid-cols-3 gap-2">
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Total Credits</div><div className="mt-1 text-lg font-semibold tabular-nums">{gh(totals.total)}</div></CardContent></Card>
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Active Balance</div><div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{gh(totals.active)}</div></CardContent></Card>
            <Card><CardContent className="p-3"><div className="text-[11px] uppercase tracking-wide text-slate-500">Used</div><div className="mt-1 text-lg font-semibold tabular-nums text-slate-500">{gh(totals.used)}</div></CardContent></Card>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : (
            <Card><CardContent className="p-0 md:p-2">
              <MobileCardList defaultOpen striped stripeAccent="blue"
                items={pg.pageItems} pagination={pg.paginationProps}
                getKey={(s: any) => s.genericSupplierCreditId}
                primary={(s: any) => s.supplierName ?? "Unknown"}
                secondary={(s: any) => fmtDateTime(s.creditDate, s)}
                trailing={(s: any) => <Badge className={STATUS_COLORS[s.status] ?? "bg-slate-100"}>{s.status}</Badge>}
                highlights={(s: any) => [
                  { label: "Amount", value: gh(s.amount), accent: "blue" },
                  { label: "Remaining", value: gh(s.remainingBalance), accent: s.remainingBalance > 0 ? "emerald" : "neutral" },
                ]}
                details={(s: any) => [{ label: "Type", value: s.creditType }, { label: "Notes", value: s.notes ?? "—" }]}
                desktopTable={
                  <div className="overflow-x-auto"><Table>
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>Supplier</TableHead><TableHead>Type</TableHead>
                      <TableHead className="text-right">Amount</TableHead><TableHead className="text-right">Remaining</TableHead>
                      <TableHead>Status</TableHead><TableHead>Notes</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {rows.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No credits.</TableCell></TableRow>
                      : pg.pageItems.map((s: any) => (
                        <TableRow key={s.genericSupplierCreditId}>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(s.creditDate, s)}</TableCell>
                          <TableCell className="font-medium">{s.supplierName ?? "—"}</TableCell>
                          <TableCell><Badge className={TYPE_COLORS[s.creditType] ?? "bg-slate-100"}>{s.creditType}</Badge></TableCell>
                          <TableCell className="text-right tabular-nums">{gh(s.amount)}</TableCell>
                          <TableCell className="text-right tabular-nums font-semibold">{gh(s.remainingBalance)}</TableCell>
                          <TableCell><Badge className={STATUS_COLORS[s.status] ?? "bg-slate-100"}>{s.status}</Badge></TableCell>
                          <TableCell className="text-sm text-slate-600 max-w-xs truncate">{s.notes ?? "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                }
              />
            </CardContent></Card>
          )}
        </main>
      </div>

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg"><DialogHeader><DialogTitle>Record supplier credit</DialogTitle></DialogHeader>
          <FormSection title="Credit details" color="indigo">
            <FormField label="Supplier *">
              <Select value={form.genericSupplierId ? String(form.genericSupplierId) : ""} onValueChange={(v) => setForm({ ...form, genericSupplierId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Select supplier" /></SelectTrigger>
                <SelectContent>{suppliers.filter((s) => s.isActive !== false).map((s) => <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>{s.supplierName}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Credit type">
              <Select value={form.creditType} onValueChange={(v) => setForm({ ...form, creditType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CREDIT_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Amount *"><NumberInput min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Date"><Input type="date" value={form.creditDate} onChange={(e) => setForm({ ...form, creditDate: e.target.value })} /></FormField>
            <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={doCreate} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record Credit"}</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

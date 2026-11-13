"use client"

// Generic Supplier Credits & Advances — deep copy of poultry supplier-credits visual structure.
// Matches poultry's header with icon + title + description, KPI cards (p-4, text-xs,
// text-2xl), styled tabs with icons and counts, search beside tabs.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { tabCountCls, tabListCls, tabTriggerCls } from "@/lib/ui/tab-styles"
import { Plus, Loader2, Search, RefreshCw, Wallet, Truck } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getSupplierCredits, createSupplierCredit, getSuppliers, type GenericSupplierCredit, type GenericSupplier } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"


const CREDIT_TYPES = ["Advance", "CreditNote", "Overpayment", "Refund"]
const TYPE_COLORS: Record<string, string> = {
  Advance: "border-emerald-300 text-emerald-700",
  CreditNote: "border-amber-300 text-amber-700",
  Overpayment: "border-blue-300 text-blue-700",
  Refund: "border-violet-300 text-violet-700",
}
const STATUS_COLORS: Record<string, string> = {
  Active: "border-blue-300 text-blue-700",
  "Partly used": "border-amber-300 text-amber-700",
  Used: "border-slate-300 text-slate-500",
}

type Tab = "credits" | "summary"

export default function GenericSupplierCreditsPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [tab, setTab] = useState<Tab>("credits")
  const [rows, setRows] = useState<GenericSupplierCredit[]>([])
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [loading, setLoading] = useState(true)
  const [createOpen, setCreateOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [form, setForm] = useState({ genericSupplierId: 0, creditType: "Advance", amount: 0, creditDate: new Date().toISOString().split("T")[0], notes: "" })

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
    return { total, active, used, count: rows.length }
  }, [rows])

  const supplierSummary = useMemo(() => {
    const map = new Map<string, { name: string; total: number; active: number; count: number }>()
    for (const s of rows) {
      const key = s.supplierName ?? "Unknown"
      const existing = map.get(key) ?? { name: key, total: 0, active: 0, count: 0 }
      existing.total += s.amount
      existing.count++
      if (s.status === "Active") existing.active += s.remainingBalance
      map.set(key, existing)
    }
    return Array.from(map.values()).sort((a, b) => b.active - a.active)
  }, [rows])

  const filteredRows = useMemo(() => {
    if (!search) return rows
    const q = search.toLowerCase()
    return rows.filter((s) => (s.supplierName ?? "").toLowerCase().includes(q) || s.creditType.toLowerCase().includes(q) || (s.notes ?? "").toLowerCase().includes(q))
  }, [rows, search])

  const pg = usePagination(filteredRows)
  const summaryPg = usePagination(supplierSummary)

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
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          {/* Header — matching poultry supplier-credits */}
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
                <Wallet className="h-6 w-6 text-amber-600" /> Supplier Credits &amp; Advances
              </h1>
              <p className="max-w-2xl text-sm text-slate-600">
                Credit held with suppliers, advance payments and credit notes. Apply it to their purchases or record money they send back.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button onClick={() => setCreateOpen(true)} className="h-10 bg-blue-600 hover:bg-blue-700">
                <Plus className="mr-1 h-4 w-4" /> Add credit
              </Button>
              <Button variant="outline" onClick={() => void load()} disabled={loading} className="h-10">
                <RefreshCw className={loading ? "mr-1 h-4 w-4 animate-spin" : "mr-1 h-4 w-4"} /> Refresh
              </Button>
            </div>
          </div>

          {/* KPI tiles — matching poultry supplier credit style */}
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Available credit with suppliers</div>
              <div className="text-2xl font-semibold tabular-nums text-blue-700">{gh(totals.active)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Suppliers with credit</div>
              <div className="text-2xl font-semibold tabular-nums">{supplierSummary.length}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Total credited</div>
              <div className="text-2xl font-semibold tabular-nums">{gh(totals.total)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Used</div>
              <div className="text-2xl font-semibold tabular-nums">{gh(totals.used)}</div>
            </CardContent></Card>
          </div>

          {/* Tabs — matching poultry styled tabs with icons and counts */}
          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)} className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <TabsList className={tabListCls}>
                <TabsTrigger value="credits" className={tabTriggerCls}>
                  <Wallet className="h-4 w-4" /> Credits
                  <span className={tabCountCls}>{rows.length}</span>
                </TabsTrigger>
                <TabsTrigger value="summary" className={tabTriggerCls}>
                  <Truck className="h-4 w-4" /> By Supplier
                  <span className={tabCountCls}>{supplierSummary.length}</span>
                </TabsTrigger>
              </TabsList>
              <div className="relative w-full sm:w-72">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search supplier" className="h-10 pl-9" />
              </div>
            </div>

            <TabsContent value="credits">
              <Card><CardContent className="p-0 sm:p-0">
                {loading ? (
                  <div className="flex items-center gap-2 p-8 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                ) : (
                  <MobileCardList defaultOpen striped stripeAccent="blue"
                    items={pg.pageItems} pagination={pg.paginationProps}
                    getKey={(s: any) => s.genericSupplierCreditId}
                    primary={(s: any) => s.supplierName ?? "Unknown"}
                    secondary={(s: any) => fmtDateTime(s.creditDate, s)}
                    trailing={(s: any) => <Badge variant="outline" className={STATUS_COLORS[s.status] ?? ""}>{s.status}</Badge>}
                    highlights={(s: any) => [
                      { label: "Amount", value: gh(s.amount), accent: "blue" as const },
                      { label: "Remaining", value: gh(s.remainingBalance), accent: s.remainingBalance > 0 ? "emerald" as const : "slate" as const },
                    ]}
                    details={(s: any) => [{ label: "Type", value: s.creditType }, { label: "Notes", value: s.notes ?? "—" }]}
                    emptyState={
                      <div className="p-8 text-center text-sm text-slate-500">
                        {search ? "No supplier matches." : "No supplier holds credit for you."}
                      </div>
                    }
                    desktopTable={
                      <div className="overflow-x-auto"><Table>
                        <TableHeader><TableRow>
                          <TableHead>Date</TableHead><TableHead>Supplier</TableHead><TableHead>Type</TableHead>
                          <TableHead className="text-right">Amount</TableHead><TableHead className="text-right">Remaining</TableHead>
                          <TableHead>Status</TableHead><TableHead>Notes</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {filteredRows.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">{search ? "No supplier matches." : "No credits."}</TableCell></TableRow>
                          : pg.pageItems.map((s: any) => (
                            <TableRow key={s.genericSupplierCreditId}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(s.creditDate, s)}</TableCell>
                              <TableCell className="font-medium">{s.supplierName ?? "—"}</TableCell>
                              <TableCell><Badge variant="outline" className={TYPE_COLORS[s.creditType] ?? ""}>{s.creditType}</Badge></TableCell>
                              <TableCell className="text-right tabular-nums">{gh(s.amount)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{gh(s.remainingBalance)}</TableCell>
                              <TableCell><Badge variant="outline" className={STATUS_COLORS[s.status] ?? ""}>{s.status}</Badge></TableCell>
                              <TableCell className="text-sm text-slate-600 max-w-xs truncate">{s.notes ?? "—"}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table></div>
                    }
                  />
                )}
              </CardContent></Card>
            </TabsContent>

            <TabsContent value="summary">
              <Card><CardContent className="p-0 sm:p-0">
                <MobileCardList defaultOpen striped stripeAccent="blue"
                  items={summaryPg.pageItems} pagination={summaryPg.paginationProps}
                  getKey={(s: any) => s.name}
                  primary={(s: any) => s.name}
                  secondary={(s: any) => `${s.count} credit(s)`}
                  trailing={(s: any) => <span className="font-semibold tabular-nums text-blue-700">{gh(s.active)}</span>}
                  highlights={(s: any) => [
                    { label: "Total", value: gh(s.total), accent: "blue" as const },
                    { label: "Active", value: gh(s.active), accent: s.active > 0 ? "emerald" as const : "slate" as const },
                  ]}
                  details={(s: any) => [
                    { label: "Credits", value: String(s.count) },
                  ]}
                  emptyState={<div className="p-8 text-center text-sm text-slate-500">No supplier credits.</div>}
                  desktopTable={
                    <div className="overflow-x-auto"><Table>
                      <TableHeader><TableRow>
                        <TableHead>Supplier</TableHead>
                        <TableHead className="text-right">Total Credited</TableHead>
                        <TableHead className="text-right">Active Balance</TableHead>
                        <TableHead className="text-right">Credits</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {supplierSummary.length === 0 ? <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-6">No supplier credits.</TableCell></TableRow>
                        : summaryPg.pageItems.map((s: any) => (
                          <TableRow key={s.name}>
                            <TableCell className="font-medium">{s.name}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(s.total)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold text-blue-700">{gh(s.active)}</TableCell>
                            <TableCell className="text-right">{s.count}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table></div>
                  }
                />
              </CardContent></Card>
            </TabsContent>
          </Tabs>
        </main>
      </div>

      {/* Create dialog — matching poultry supplier credit dialog */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Wallet className="w-5 h-5 text-amber-600" /> Record supplier credit
            </DialogTitle>
            <DialogDescription>Add a credit with a supplier — advance payment, credit note, overpayment or refund.</DialogDescription>
          </DialogHeader>
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

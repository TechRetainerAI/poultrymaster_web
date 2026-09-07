"use client"

// Owner Money — what the owner puts into the business, and what they take out.
//
// Deliberately its own page rather than a category on income or expenses. A
// contribution is NOT revenue and a draw is NOT an operating cost, so neither
// reaches the P&L: profit stays a statement about the business, not about how
// the owner funds it. Both move cash, and that is all they do.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, Plus, ArrowDownLeft, ArrowUpRight, Wallet, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getOwnerEntries, recordOwnerEntry, reverseOwnerEntry,
  type GenericOwnerEntry, type OwnerEntryType,
} from "@/lib/api/generic-money-out"
import { getCashAccounts } from "@/lib/api/generic"

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericOwnerMoneyPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericOwnerEntry[]>([])
  const [accounts, setAccounts] = useState<{ genericCashAccountId: number; accountName: string; isActive: boolean }[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [typeFilter, setTypeFilter] = useState("All")
  const [open, setOpen] = useState(false)
  const [reversing, setReversing] = useState<GenericOwnerEntry | null>(null)
  const [reason, setReason] = useState("")

  const EMPTY = {
    entryType: "Contribution" as OwnerEntryType,
    amount: "0",
    cashAccountId: "",
    entryDate: today(),
    paymentMethod: "Bank",
    ownerName: "",
    reference: "",
    notes: "",
  }
  const [form, setForm] = useState(EMPTY)

  const load = async () => {
    setLoading(true)
    try {
      const [entries, accts] = await Promise.all([
        getOwnerEntries(),
        getCashAccounts().catch(() => []),
      ])
      setRows(entries)
      setAccounts(accts as any)
    } catch (e: any) {
      toast({
        title: "Could not load owner money",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(() => {
    const byType = typeFilter === "All" ? rows : rows.filter((r) => r.entryType === typeFilter)
    return filterByDateAndSearch(byType, {
      search,
      searchKeys: ["ownerName", "referenceNo", "notes", "cashAccountName"],
    })
  }, [rows, search, typeFilter])
  const pg = usePagination(visible)

  // Reversed entries are excluded from both totals: the money came back.
  const totals = useMemo(() => {
    const live = rows.filter((r) => r.status !== "Reversed")
    const inSum = live.filter((r) => r.entryType === "Contribution").reduce((s, r) => s + r.amount, 0)
    const outSum = live.filter((r) => r.entryType === "Draw").reduce((s, r) => s + r.amount, 0)
    return { inSum, outSum, net: inSum - outSum }
  }, [rows])

  const onSave = async () => {
    if (!form.cashAccountId) {
      toast({
        title: "Pick a cash account",
        description: "Owner money always moves cash, so it has to come from or go to somewhere.",
        variant: "destructive",
      })
      return
    }
    if (Number(form.amount) <= 0) {
      toast({ title: "The amount must be more than zero", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await recordOwnerEntry({
        entryType: form.entryType,
        amount: Number(form.amount),
        cashAccountId: Number(form.cashAccountId),
        entryDate: form.entryDate ? `${form.entryDate}T00:00:00Z` : null,
        paymentMethod: form.paymentMethod || null,
        ownerName: form.ownerName || null,
        reference: form.reference || null,
        notes: form.notes || null,
      })
      toast({
        title: form.entryType === "Contribution" ? "Contribution recorded." : "Draw recorded.",
        description: "Cash moved. This does not affect profit.",
      })
      setOpen(false)
      setForm(EMPTY)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record it", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const onReverse = async () => {
    if (!reversing) return
    if (!reason.trim()) {
      toast({ title: "A reason is required to reverse", variant: "destructive" })
      return
    }
    try {
      await reverseOwnerEntry(reversing.genericOwnerEntryId, reason.trim())
      toast({ title: "Reversed.", description: "The cash movement has been undone." })
      setReversing(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse it", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const typeBadge = (r: GenericOwnerEntry) =>
    r.entryType === "Contribution" ? (
      <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">
        <ArrowDownLeft className="h-3 w-3 mr-1" /> In
      </Badge>
    ) : (
      <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">
        <ArrowUpRight className="h-3 w-3 mr-1" /> Out
      </Badge>
    )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-6 w-6 text-indigo-600" /> Owner money
              </h1>
              <p className="text-sm text-slate-500">
                {fmt(totals.inSum)} put in · {fmt(totals.outSum)} taken out ·{" "}
                <strong>{fmt(totals.net)}</strong> net
              </p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild>
                <Button className="h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> Record</Button>
              </DialogTrigger>
              <DialogContent className="w-[95vw] max-w-[800px] max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <Wallet className="w-5 h-5 text-blue-600" /> Owner money
                  </DialogTitle>
                  <DialogDescription>
                    This moves cash and nothing else. It is not sales income and not a business
                    expense, so it will not change your profit.
                  </DialogDescription>
                </DialogHeader>

                <div className="space-y-4">
                  <FormSection title="What happened" color="indigo">
                    <FormField label="Type *">
                      <Select value={form.entryType}
                        onValueChange={(v) => setForm((f) => ({ ...f, entryType: v as OwnerEntryType }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="Contribution">
                            Contribution — the owner put money in
                          </SelectItem>
                          <SelectItem value="Draw">
                            Draw — the owner took money out
                          </SelectItem>
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Amount *">
                      <NumberInput step="0.01" value={form.amount}
                        onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                    </FormField>
                    <FormField label="Date">
                      <Input type="date" value={form.entryDate}
                        onChange={(e) => setForm((f) => ({ ...f, entryDate: e.target.value }))} />
                    </FormField>
                    <FormField label="Owner">
                      <Input value={form.ownerName} maxLength={120}
                        onChange={(e) => setForm((f) => ({ ...f, ownerName: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Which account" color="amber">
                    <FormField label="Cash account *">
                      <Select value={form.cashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, cashAccountId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Pick one" /></SelectTrigger>
                        <SelectContent>
                          {accounts.filter((a) => a.isActive).map((a) => (
                            <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                              {a.accountName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Method">
                      <Select value={form.paymentMethod}
                        onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {["Cash", "Bank", "Mobile Money", "Card", "Other"].map((m) => (
                            <SelectItem key={m} value={m}>{m}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Reference">
                      <Input value={form.reference} maxLength={60}
                        onChange={(e) => setForm((f) => ({ ...f, reference: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Notes" color="slate" columns={1}>
                    <FormField label="Notes">
                      <Textarea rows={2} value={form.notes}
                        onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <div className="flex gap-3 justify-end pt-2">
                    <Button type="button" onClick={() => setOpen(false)}
                      className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Record"}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card>
              <CardContent className="py-8 text-center text-slate-500">
                Nothing recorded yet. Money the owner puts in or takes out belongs here rather
                than in sales or expenses.
              </CardContent>
            </Card>
          ) : (
            <>
              <div className="flex flex-wrap items-end gap-2 mb-3">
                <div className="flex-1 min-w-[220px]">
                  <ListFilters search={search} setSearch={setSearch} searchOnly
                    searchPlaceholder="Search owner, reference or notes" />
                </div>
                <Select value={typeFilter} onValueChange={setTypeFilter}>
                  <SelectTrigger className="w-[180px]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {["All", "Contribution", "Draw"].map((t) => (
                      <SelectItem key={t} value={t}>{t}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <Card>
                <CardContent className="p-0">
                  <MobileCardList
                    items={pg.pageItems}
                    getKey={(r) => r.genericOwnerEntryId}
                    primary={(r) => (r.entryType === "Contribution" ? "Money in" : "Money out")}
                    secondary={(r) => (
                      <>
                        <span>{fmt(r.amount)}</span>
                        <span> · {new Date(r.entryDate).toLocaleDateString()}</span>
                      </>
                    )}
                    trailing={(r) =>
                      r.status === "Reversed"
                        ? <Badge className="bg-slate-200 text-slate-700 hover:bg-slate-200">Reversed</Badge>
                        : typeBadge(r)
                    }
                    details={(r) => [
                      { label: "Owner", value: r.ownerName ?? "—" },
                      { label: "Account", value: r.cashAccountName ?? "—" },
                      { label: "Method", value: r.paymentMethod ?? "—" },
                      { label: "Reference", value: r.referenceNo ?? "—" },
                    ]}
                    actions={(r) =>
                      r.status !== "Reversed" ? (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200"
                          onClick={() => { setReversing(r); setReason("") }}>
                          <Undo2 className="h-4 w-4 mr-1" /> Reverse
                        </Button>
                      ) : null
                    }
                    pagination={pg.paginationProps}
                    desktopTable={
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Date</TableHead>
                              <TableHead>Type</TableHead>
                              <TableHead>Owner</TableHead>
                              <TableHead>Account</TableHead>
                              <TableHead>Reference</TableHead>
                              <TableHead className="text-right">Amount</TableHead>
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pg.pageItems.map((r) => (
                              <TableRow key={r.genericOwnerEntryId}
                                className={r.status === "Reversed" ? "opacity-60" : ""}>
                                <TableCell>{new Date(r.entryDate).toLocaleDateString()}</TableCell>
                                <TableCell>
                                  {r.status === "Reversed"
                                    ? <Badge className="bg-slate-200 text-slate-700 hover:bg-slate-200">Reversed</Badge>
                                    : typeBadge(r)}
                                </TableCell>
                                <TableCell>{r.ownerName ?? "—"}</TableCell>
                                <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                                <TableCell className="font-mono text-xs">{r.referenceNo ?? "—"}</TableCell>
                                <TableCell className={`text-right font-medium ${
                                  r.entryType === "Contribution" ? "text-emerald-700" : "text-amber-700"
                                }`}>
                                  {r.entryType === "Contribution" ? "+" : "−"}{fmt(r.amount)}
                                </TableCell>
                                <TableCell className="text-right">
                                  {r.status !== "Reversed" && (
                                    <Button size="sm" variant="outline" className="text-red-600 border-red-200"
                                      onClick={() => { setReversing(r); setReason("") }}>
                                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                                    </Button>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                        <DataPagination {...pg.paginationProps} />
                      </div>
                    }
                  />
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>

      <Dialog open={reversing !== null} onOpenChange={(o) => !o && setReversing(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Reverse this entry?</DialogTitle>
            <DialogDescription>
              {reversing && `${fmt(reversing.amount)} ${reversing.entryType === "Contribution" ? "put in" : "taken out"}. `}
              The cash movement is undone with an opposite entry. The original is kept and marked
              reversed.
            </DialogDescription>
          </DialogHeader>
          <Textarea rows={3} placeholder="Why is it being reversed?"
            value={reason} onChange={(e) => setReason(e.target.value)} />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setReversing(null)}>Keep it</Button>
            <Button className="bg-red-600 hover:bg-red-700 text-white" onClick={onReverse}>
              Reverse it
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

"use client"

// Owner Money — what the owner puts into the business, and what they take out.
//
// Deliberately its own page rather than a category on income or expenses. A
// contribution is NOT revenue and a draw is NOT an operating cost, so neither
// reaches the P&L: profit stays a statement about the business, not about how
// the owner funds it. Both move cash, and that is all they do.

import { REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
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
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { SingleProjectField, EMPTY_SINGLE_PROJECT, singleAssignment, type SingleProjectValue } from "@/components/generic/projects/form-project-field"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { projectIdFromQuery } from "@/lib/generic/project-math"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import {
  Loader2, ArrowDownCircle, ArrowUpCircle, Wallet, Undo2,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getOwnerEntries, recordOwnerEntry, reverseOwnerEntry,
  type GenericOwnerEntry, type OwnerEntryType,
} from "@/lib/api/generic-money-out"
import { getCashAccounts } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { ProjectFilter } from "@/components/generic/projects/project-filter"
import { useProjectLabels } from "@/hooks/use-project-labels"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"

const PAYMENT_METHODS = ["Cash", "BankTransfer", "MoMo", "Cheque", "Card", "Other"]
const TYPE_FILTERS = ["All", "Contribution", "Draw"] as const
const STATUS_FILTERS = ["All", "Posted", "Reversed"] as const

const today = () => new Date().toISOString().slice(0, 10)

type CashAccount = { genericCashAccountId: number; accountName: string; isActive: boolean; currentBalance?: number; allowNegativeBalance?: boolean }

export default function GenericOwnerMoneyPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericOwnerEntry[]>([])
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [search, setSearch] = useState("")
  const [typeFilter, setTypeFilter] = useState("All")
  const [statusFilter, setStatusFilter] = useState("All")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  const [recording, setRecording] = useState<OwnerEntryType | null>(null)
  const [form, setForm] = useState({
    amount: "0", cashAccountId: "", entryDate: today(),
    paymentMethod: "Cash", ownerName: "", reference: "", notes: "",
  })

  // 483: owner money can be marked as funding for a project. Financing only:
  // it never touches the project's profit.
  const { enabled: projectsEnabled } = useProjectsEnabled()
  const [project, setProject] = useState<SingleProjectValue>(EMPTY_SINGLE_PROJECT)
  const [fromProject, setFromProject] = useState<number | null>(null)

  const [reversing, setReversing] = useState<GenericOwnerEntry | null>(null)
  const [reason, setReason] = useState("")

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
    const qs = new URLSearchParams(window.location.search)
    const pid = projectIdFromQuery(qs)
    const kind = qs.get("new")
    if (pid) setFromProject(pid)
    if (kind === "Contribution" || kind === "Draw") openRecord(kind, pid)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  // 483: Project / Contract filter (hidden unless the module is on).
  const [projectFilter, setProjectFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const projectLabels = useProjectLabels("OwnerEntry", rows)
  const visible = useMemo(() => {
    let list = rows.filter((r) => projectLabels.matches(r.genericOwnerEntryId, projectFilter))
    if (typeFilter !== "All") list = list.filter((r) => r.entryType === typeFilter)
    if (statusFilter !== "All") list = list.filter((r) => r.status === statusFilter)
    return filterByDateAndSearch(list, {
      dateFrom, dateTo, dateKey: "entryDate",
      search,
      searchKeys: ["ownerName", "referenceNo", "notes", "cashAccountName"],
    })
  }, [rows, typeFilter, statusFilter, search, dateFrom, dateTo, projectLabels, projectFilter])
  const pg = usePagination(visible)

  // Summary stats computed client-side from all rows
  const summary = useMemo(() => {
    const live = rows.filter((r) => r.status !== "Reversed")
    const totalContributions = live.filter((r) => r.entryType === "Contribution").reduce((s, r) => s + r.amount, 0)
    const totalDraws = live.filter((r) => r.entryType === "Draw").reduce((s, r) => s + r.amount, 0)
    const contributionCount = live.filter((r) => r.entryType === "Contribution").length
    const drawCount = live.filter((r) => r.entryType === "Draw").length
    const netFunding = totalContributions - totalDraws
    return { totalContributions, totalDraws, contributionCount, drawCount, netFunding }
  }, [rows])

  const balanceOf = (id: string) =>
    (accounts.find((a) => String(a.genericCashAccountId) === id) as any)?.currentBalance ?? 0
  const allowsNegative = (id: string) =>
    (accounts.find((a) => String(a.genericCashAccountId) === id) as any)?.allowNegativeBalance ?? false

  const amountNum = Number(form.amount) || 0
  const isDraw = recording === "Draw"
  const after = isDraw
    ? balanceOf(form.cashAccountId) - amountNum
    : balanceOf(form.cashAccountId) + amountNum
  const wouldOverdraw =
    isDraw && !!form.cashAccountId && amountNum > 0 &&
    after < 0 && !allowsNegative(form.cashAccountId)

  const openRecord = (t: OwnerEntryType, projectId: number | null = null) => {
    setRecording(t)
    setProject({ ...EMPTY_SINGLE_PROJECT, projectId, costClass: "Financing" })
    setForm({
      amount: "0", cashAccountId: "", entryDate: today(),
      paymentMethod: "Cash", ownerName: "", reference: "", notes: "",
    })
  }

  const onSave = async () => {
    if (!recording) return
    if (!form.cashAccountId) {
      toast({
        title: "Pick a cash account",
        description: "Owner money always moves cash, so it has to come from or go to somewhere.",
        variant: "destructive",
      })
      return
    }
    if (amountNum <= 0) {
      toast({ title: "Enter an amount", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await recordOwnerEntry({
        entryType: recording,
        amount: amountNum,
        cashAccountId: Number(form.cashAccountId),
        entryDate: form.entryDate ? `${form.entryDate}T00:00:00Z` : null,
        paymentMethod: form.paymentMethod || null,
        ownerName: form.ownerName.trim() || null,
        reference: form.reference.trim() || null,
        notes: form.notes.trim() || null,
        projects: projectsEnabled ? singleAssignment(project) : undefined,
      })
      toast({
        title: recording === "Contribution" ? "Contribution recorded" : "Draw recorded",
        description: recording === "Contribution"
          ? "Cash is up. It is funding, not revenue — it does not touch profit."
          : "Cash is down. It is the owner taking funding back, not a business expense.",
      })
      setRecording(null)
      if (fromProject) { router.push(`/generic-projects/${fromProject}?tab=cash`); return }
      await load()
    } catch (e: any) {
      toast({ title: "Could not record", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const onReverse = async () => {
    if (!reversing) return
    if (!reason.trim() || reason.trim().length < 3) {
      toast({ title: "Say why", description: "The reason is written to the audit trail.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await reverseOwnerEntry(reversing.genericOwnerEntryId, reason.trim())
      toast({ title: "Reversed", description: `${fmt(reversing.amount)} put back.` })
      setReversing(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const typeBadge = (t: string) =>
    t === "Contribution"
      ? "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
      : "bg-orange-100 text-orange-800 hover:bg-orange-100"

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-6 w-6 text-emerald-600" /> Owner Money
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money the owner puts into the business and takes out of it. A contribution is
                <strong> not revenue</strong> and a draw is <strong>not an expense</strong> — both move
                cash, neither touches profit.
              </p>
            </div>
            <div className="flex gap-2 flex-wrap">
              <Button onClick={() => openRecord("Contribution")} className="h-11 sm:h-10">
                <ArrowDownCircle className="h-4 w-4 mr-1" /> Record contribution
              </Button>
              <Button onClick={() => openRecord("Draw")} variant="outline" className="h-11 sm:h-10">
                <ArrowUpCircle className="h-4 w-4 mr-1" /> Record draw
              </Button>
            </div>
          </div>

          {/* Summary stat cards */}
          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
            <Stat label="Total contributions" value={fmt(summary.totalContributions)}
                  hint={`${summary.contributionCount} record(s)`} accent="emerald" />
            <Stat label="Total draws" value={fmt(summary.totalDraws)}
                  hint={`${summary.drawCount} record(s)`} accent="orange" />
            <Stat label="Net owner funding" value={fmt(summary.netFunding)}
                  hint="Contributions less draws"
                  accent={summary.netFunding >= 0 ? "emerald" : "rose"} />
            <Stat label="Contributions in range" value={fmt(
              visible.filter((r) => r.entryType === "Contribution" && r.status !== "Reversed").reduce((s, r) => s + r.amount, 0)
            )} />
            <Stat label="Draws in range" value={fmt(
              visible.filter((r) => r.entryType === "Draw" && r.status !== "Reversed").reduce((s, r) => s + r.amount, 0)
            )} />
          </div>

          {/* Filters */}
          <Card className="mb-4">
            <CardContent className="pt-6">
              <ListFilters
                search={search} setSearch={setSearch}
                searchPlaceholder="Search owner, reference, account or notes"
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
                extras={<ProjectFilter value={projectFilter} onChange={setProjectFilter} />}
              />
              <div className="flex flex-wrap gap-2 mt-3">
                {TYPE_FILTERS.map((t) => (
                  <Button key={t} size="sm" variant={typeFilter === t ? "default" : "outline"}
                          onClick={() => setTypeFilter(t)}>{t}</Button>
                ))}
                <span className="w-px bg-slate-200 mx-1" />
                {STATUS_FILTERS.map((st) => (
                  <Button key={st} size="sm" variant={statusFilter === st ? "secondary" : "outline"}
                          onClick={() => setStatusFilter(st)}>{st}</Button>
                ))}
              </div>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : visible.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              {rows.length === 0
                ? "Nothing recorded yet. Use the buttons above when the owner puts money in or takes it out."
                : "Nothing matches these filters."}
            </CardContent></Card>
          ) : (
            <MobileCardList
              defaultOpen
              striped
              items={pg.pageItems}
              getKey={(r) => r.genericOwnerEntryId}
              primary={(r) => (r.entryType === "Contribution" ? "Money in" : "Money out")}
              secondary={(r) => (
                <>
                  <span>{fmtDateTime(r.entryDate, r)}</span>
                  <span>·</span>
                  <span className="text-xs">{r.cashAccountName ?? "–"}</span>
                </>
              )}
              trailing={(r) => (
                <Badge className={r.status === "Reversed"
                  ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                  : typeBadge(r.entryType)}>
                  {r.status === "Reversed" ? "Reversed" : r.entryType}
                </Badge>
              )}
              highlights={(r) => [{
                label: r.entryType === "Contribution" ? "In" : "Out",
                value: fmt(r.amount),
              }]}
              details={(r) => [
                { label: "Type", value: r.entryType },
                { label: "Owner", value: r.ownerName ?? "–" },
                { label: "Account", value: r.cashAccountName ?? "–" },
                { label: "Method", value: r.paymentMethod ?? "–" },
                { label: "Reference", value: r.referenceNo ?? "–" },
                { label: "Notes", value: r.notes ?? "–" },
                ...(r.status === "Reversed"
                  ? [{ label: "Reversed", value: r.reversalReason ?? "–" }]
                  : []),
              ]}
              actions={(r) =>
                r.status !== "Reversed" ? (
                  <Button size="sm" variant="outline" className="flex-1 h-10"
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
                        <TableHead>Owner</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Cash account</TableHead>
                        <TableHead>Method</TableHead>
                        <TableHead>Reference</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pg.pageItems.map((r) => (
                        <TableRow key={r.genericOwnerEntryId}>
                          <TableCell className="whitespace-nowrap">
                            {fmtDateTime(r.entryDate, r)}
                          </TableCell>
                          <TableCell>{r.ownerName ?? "–"}</TableCell>
                          <TableCell>
                            <Badge className={typeBadge(r.entryType)}>{r.entryType}</Badge>
                          </TableCell>
                          <TableCell className="text-right font-medium tabular-nums">
                            <span className={r.status === "Reversed" ? "line-through text-slate-400" : ""}>
                              {r.entryType === "Draw" ? "−" : "+"}{fmt(r.amount)}
                            </span>
                          </TableCell>
                          <TableCell>{r.cashAccountName ?? "–"}</TableCell>
                          <TableCell className="text-slate-500">{r.paymentMethod ?? "–"}</TableCell>
                          <TableCell className="text-slate-500">{r.referenceNo ?? "–"}</TableCell>
                          <TableCell>
                            <Badge className={r.status === "Reversed"
                              ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                              : "bg-sky-100 text-sky-800 hover:bg-sky-100"}>
                              {r.status}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right">
                            {r.status !== "Reversed" && (
                              <Button size="sm" variant="outline"
                                      onClick={() => { setReversing(r); setReason("") }}>
                                <Undo2 className="h-3 w-3 mr-1" /> Reverse
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
          )}
        </main>
      </div>

      {/* ---- record ---------------------------------------------------- */}
      <Dialog open={!!recording} onOpenChange={(o) => { if (!o) setRecording(null) }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {recording === "Draw"
                ? <><ArrowUpCircle className="w-5 h-5 text-orange-600" /> Record Owner Draw</>
                : <><ArrowDownCircle className="w-5 h-5 text-emerald-600" /> Record Owner Contribution</>}
            </DialogTitle>
            <DialogDescription>
              {recording === "Draw"
                ? "Cash leaves the account. It is the owner taking funding back — it is not an operating expense and it will not reduce profit."
                : "Cash arrives in the account. It is the owner funding the business — it is not a sale and it will not increase revenue."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title={recording === "Draw" ? "Draw" : "Contribution"}
                         color={recording === "Draw" ? "amber" : "emerald"}>
              <FormField label="Date *">
                <Input type="date" value={form.entryDate}
                       onChange={(e) => setForm((f) => ({ ...f, entryDate: e.target.value }))} />
              </FormField>
              <FormField label="Amount *">
                <NumberInput value={form.amount} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
              </FormField>
              <FormField label="Cash account *" full>
                <Select value={form.cashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, cashAccountId: v }))}>
                  <SelectTrigger>
                    <SelectValue placeholder={recording === "Draw" ? "Which account does it leave?" : "Which account does it arrive in?"} />
                  </SelectTrigger>
                  <SelectContent>
                    {accounts.filter((a) => a.isActive).map((a) => (
                      <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                        {a.accountName}{a.currentBalance != null ? ` — ${fmt(a.currentBalance)}` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            {form.cashAccountId && amountNum > 0 && (
              <FormSection title="After this" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="flex items-center justify-between">
                    <span className="text-slate-500">Account balance</span>
                    <span className="tabular-nums">
                      <span className="text-slate-400">{fmt(balanceOf(form.cashAccountId))}</span>
                      {" → "}
                      <span className={after < 0 ? "font-medium text-rose-600" : "font-medium text-slate-900"}>
                        {fmt(after)}
                      </span>
                    </span>
                  </div>
                  {wouldOverdraw && (
                    <p className="text-rose-600 text-xs pt-1">
                      This would take the account below zero, and it is not allowed to go negative.
                      The draw will be rejected.
                    </p>
                  )}
                </div>
              </FormSection>
            )}

            <FormSection title="Details" color="slate">
              <FormField label="Owner">
                <Input value={form.ownerName} placeholder="Whose money is this?"
                       onChange={(e) => setForm((f) => ({ ...f, ownerName: e.target.value }))} />
              </FormField>
              <FormField label="Method">
                <Select value={form.paymentMethod}
                        onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Reference">
                <Input value={form.reference} placeholder="Bank or MoMo reference"
                       onChange={(e) => setForm((f) => ({ ...f, reference: e.target.value }))} />
              </FormField>
              {projectsEnabled && (
                <FormField label="Project / contract" full>
                  <SingleProjectField value={project} onChange={setProject} amount={amountNum} showCostClass={false} label=""
                    hint="Shows as owner funding on the project. It is financing, never revenue or profit." />
                </FormField>
              )}
              <FormField label="Notes" full>
                <Textarea rows={2} value={form.notes}
                          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
              </FormField>
            </FormSection>
          </div>

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setRecording(null)}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={onSave} disabled={saving || wouldOverdraw}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                : recording === "Draw"
                  ? <><ArrowUpCircle className="w-4 h-4 mr-2" />Record Draw</>
                  : <><ArrowDownCircle className="w-4 h-4 mr-2" />Record Contribution</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- reverse --------------------------------------------------- */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) { setReversing(null); setReason("") } }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Undo2 className="w-5 h-5 text-amber-600" /> Reverse Owner Money
            </DialogTitle>
            <DialogDescription>
              The original stays on the record. One opposite cash row is added, putting the account
              back where it was, and the record stops counting towards owner funding.
            </DialogDescription>
          </DialogHeader>

          {reversing && (
            <div className="space-y-4">
              <FormSection title="Record being reversed" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">
                    #{reversing.genericOwnerEntryId} · {reversing.entryType}
                  </div>
                  <div className="mt-1">
                    {fmt(reversing.amount)} on {fmtDateTime(reversing.entryDate, reversing)}
                    {reversing.cashAccountName ? " · " + reversing.cashAccountName : ""}
                  </div>
                  <div className="text-xs text-slate-500 mt-2">
                    {reversing.entryType === "Contribution"
                      ? "The money comes back out of the account. If it has since been spent and the account cannot go negative, the reversal will be refused."
                      : "The money goes back into the account."}
                  </div>
                </div>
              </FormSection>

              <FormSection title="Why" color="amber" columns={1}>
                <FormField label="Reason *" hint="Written to the audit trail.">
                  <ReasonSelect options={REVERSAL_REASONS} value={reason} onChange={setReason} />
                </FormField>
              </FormSection>
            </div>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => { setReversing(null); setReason("") }}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button variant="destructive" onClick={onReverse} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Reversing...</>
                      : <><Undo2 className="w-4 h-4 mr-2" />Reverse</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Stat({
  label, value, hint, accent = "slate",
}: {
  label: string
  value: string
  hint?: string
  accent?: "slate" | "emerald" | "orange" | "rose"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    orange: "text-orange-700",
    rose: "text-rose-600",
  }[accent]
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{label}</p>
        <div className={`text-lg sm:text-xl font-bold mt-1 truncate ${colour}`}>{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-0.5 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}

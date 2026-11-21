"use client"

// Water Employee Credit (migration 460): the Poultry page (app/poultry-employee-credit,
// 441) on Water staff, cash accounts and API -- ported from the Generic copy (450).
//
// Money the business is KEEPING FOR ITS STAFF: a worker asked not to be paid every
// period and to collect the savings in one go later. It is her money -- a
// liability, the mirror of Employee Loans & Advances.
//
// THE RULE THIS PAGE MUST TEACH
// -----------------------------
// The wage cost lands ONCE, on the day the credit goes up (payroll approved,
// or wages owed added here). Paying it out later moves cash and nothing else:
// no expense, no P&L. That is said under the heading and again on the payout
// form, because "why didn't my expenses go up when I paid her" is exactly the
// question it provokes.
//
// Payroll savings are added on the payroll run (deduction "Keep as employee
// credit"), never here, and are undone by reopening that payroll. Every write
// on this page is owner/admin only; the server enforces the same.

import { REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { PiggyBank, Loader2, Plus, Undo2, Wallet, Info, Eye, Banknote } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  listWaterCreditCashAccounts, listWaterCreditStaff,
  listWaterEmployeeCreditBalances, listWaterEmployeeCreditEntries,
  addWaterEmployeeCredit, payoutWaterEmployeeCredit, reverseWaterEmployeeCredit,
  EMPLOYEE_CREDIT_ENTRY_LABELS, EMPLOYEE_CREDIT_MANUAL_TYPES,
  type EmployeeCreditManualType,
  type WaterEmployeeCreditBalance, type WaterEmployeeCreditEntry,
  type WaterCashAccount, type WaterCreditStaff as WaterStaff,
} from "@/lib/api/water-employee-credit"

const today = () => new Date().toISOString().slice(0, 10)
const fmtDate = (d?: string | null) => (d ? String(d).slice(0, 10) : "—")

const MANUAL_HELP: Record<EmployeeCreditManualType, { title: string; text: string }> = {
  OpeningBalance: {
    title: "Opening balance",
    text: "Money you were already keeping for them before using this system. No expense and no cash — it was earned and recorded before.",
  },
  Deposit: {
    title: "Money handed in",
    text: "They give you their own money to keep. Cash comes IN to the account you choose. Not income — it is theirs.",
  },
  WagesOwed: {
    title: "Wages owed (outside payroll)",
    text: "Wages or a bonus you are keeping for them without a payroll run. Counts as payroll cost today; no cash moves until you pay it out.",
  },
}

const PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Other"] as const

function entryTone(t: string) {
  switch (t) {
    case "Payout": return "bg-rose-100 text-rose-700"
    case "Deposit": return "bg-sky-100 text-sky-800"
    case "OpeningBalance": return "bg-slate-100 text-slate-700"
    default: return "bg-emerald-100 text-emerald-700"
  }
}

function Stat({ label, value, hint, accent = "slate" }: {
  label: string; value: string; hint?: string; accent?: "slate" | "emerald" | "rose" | "indigo"
}) {
  const colour = { slate: "text-slate-900", emerald: "text-emerald-700", rose: "text-rose-600", indigo: "text-indigo-700" }[accent]
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

// ---------------------------------------------------------------------------
export default function WaterEmployeeCreditPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()
  const { isAdmin } = usePermissions()
  const canManage = isAdmin

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") router.replace("/dashboard")
  }, [activeFarmType, router])

  const [balances, setBalances] = useState<WaterEmployeeCreditBalance[]>([])
  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [showZero, setShowZero] = useState(false)

  // Statement dialog
  const [statementFor, setStatementFor] = useState<WaterEmployeeCreditBalance | null>(null)
  const [entries, setEntries] = useState<WaterEmployeeCreditEntry[]>([])
  const [entriesLoading, setEntriesLoading] = useState(false)

  // Add / payout / reverse
  const [addOpen, setAddOpen] = useState(false)
  const [payoutFor, setPayoutFor] = useState<WaterEmployeeCreditBalance | null>(null)
  const [reversing, setReversing] = useState<WaterEmployeeCreditEntry | null>(null)
  const [reason, setReason] = useState("")
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError("")
    try {
      const [b, s, a] = await Promise.all([
        listWaterEmployeeCreditBalances(), listWaterCreditStaff(), listWaterCreditCashAccounts(),
      ])
      setBalances(b)
      setStaff(s.filter((x) => !x.isDeleted))
      setAccounts(a.filter((x) => x.isActive))
    } catch (e: any) {
      setError(e?.message ?? "Could not load employee credit.")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { void load() }, [load])

  const loadEntries = useCallback(async (staffId: number) => {
    setEntriesLoading(true)
    try {
      setEntries(await listWaterEmployeeCreditEntries(staffId))
    } catch (e: any) {
      toast({ title: "Could not load the statement", description: e?.message, variant: "destructive" })
    } finally {
      setEntriesLoading(false)
    }
  }, [toast])

  useEffect(() => {
    if (statementFor) void loadEntries(statementFor.waterStaffId)
  }, [statementFor, loadEntries])

  const totalHeld = balances.reduce((s, b) => s + b.balance, 0)
  const holding = balances.filter((b) => b.balance > 0).length
  const totalIn = balances.reduce((s, b) => s + b.totalIn, 0)
  const totalOut = balances.reduce((s, b) => s + b.totalPaidOut, 0)
  const rows = useMemo(
    () => (showZero ? balances : balances.filter((b) => b.balance !== 0)),
    [balances, showZero])
  const cashOnHand = accounts.reduce((s, a) => s + a.currentBalance, 0)

  const afterChange = async () => {
    await load()
    if (statementFor) {
      await loadEntries(statementFor.waterStaffId)
      const fresh = await listWaterEmployeeCreditBalances().catch(() => null)
      const me = fresh?.find((b) => b.waterStaffId === statementFor.waterStaffId)
      if (me) setStatementFor(me)
    }
  }

  const doReverse = async () => {
    if (!reversing || !reason.trim()) return
    setBusy(true)
    try {
      await reverseWaterEmployeeCredit(reversing.waterEmployeeCreditId, reason.trim())
      toast({ title: "Entry reversed" })
      setReversing(null)
      setReason("")
      await afterChange()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message, variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <PiggyBank className="h-6 w-6 text-emerald-600" /> Employee Credit
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money you are keeping for staff, to pay them later. It is <strong>their money</strong>:
                the wage is a payroll cost on the day it is kept, and paying it out later is{" "}
                <strong>not an expense</strong> — only cash leaves.
              </p>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" asChild className="h-11 sm:h-10">
                <Link href="/water-payroll">Payroll</Link>
              </Button>
              {canManage && (
                <Button onClick={() => setAddOpen(true)} className="h-11 sm:h-10">
                  <Plus className="h-4 w-4 mr-1" /> Add credit
                </Button>
              )}
            </div>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <Stat label="Holding for staff" value={fmt(totalHeld)}
                  hint="What you owe staff now" accent="indigo" />
            <Stat label="Staff with credit" value={String(holding)} />
            <Stat label="Kept so far" value={fmt(totalIn)} accent="emerald" />
            <Stat label="Paid out so far" value={fmt(totalOut)} accent="rose" />
          </div>

          {/* The cash guard, as a warning only: the money is still in your
              accounts, so spending it would leave nothing to pay them with. */}
          {totalHeld > 0 && (
            <div className={cn(
              "mb-4 flex items-start gap-2 rounded-md border p-3 text-sm",
              cashOnHand < totalHeld ? "border-amber-300 bg-amber-50 text-amber-900" : "border-sky-200 bg-sky-50 text-sky-900")}>
              <Info className="h-4 w-4 mt-0.5 shrink-0" />
              <p>
                {fmt(totalHeld)} of the {fmt(cashOnHand)} in your cash accounts belongs to staff.
                {cashOnHand < totalHeld
                  ? " You do not have enough cash to pay all of it out today."
                  : ` Money that is really the business's: ${fmt(cashOnHand - totalHeld)}.`}
              </p>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2 mb-4">
            <Button size="sm" variant={!showZero ? "default" : "outline"} onClick={() => setShowZero(false)}>
              Holding credit
            </Button>
            <Button size="sm" variant={showZero ? "default" : "outline"} onClick={() => setShowZero(true)}>
              All
            </Button>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="p-4 text-sm text-red-800">{error}</CardContent>
            </Card>
          )}

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-sm text-slate-500 space-y-1">
              <p>{balances.length === 0 ? "You are not keeping money for anyone yet." : "Nobody has credit right now."}</p>
              <p>
                To keep part of a wage, open a payroll line&apos;s deductions and choose{" "}
                <strong>Keep as employee credit</strong>.
              </p>
            </CardContent></Card>
          ) : (
            <MobileCardList
              striped
              defaultOpen
              items={rows}
              getKey={(b: WaterEmployeeCreditBalance) => b.waterStaffId}
              primary={(b: WaterEmployeeCreditBalance) => <>{b.staffName}</>}
              secondary={(b: WaterEmployeeCreditBalance) => (
                <>
                  <span className="text-xs">{b.staffRole || "Staff"}</span>
                  <span>·</span>
                  <span className="text-xs">Last entry {fmtDate(b.lastEntryDate)}</span>
                </>
              )}
              trailing={(b: WaterEmployeeCreditBalance) => !b.isActive
                ? <Badge className="bg-slate-200 text-slate-600">Inactive</Badge> : null}
              highlights={(b: WaterEmployeeCreditBalance) => [
                { label: "Holding", value: fmt(b.balance), accent: "blue" as const, wide: true },
                { label: "Kept", value: fmt(b.totalIn), accent: "emerald" as const },
                { label: "Paid out", value: fmt(b.totalPaidOut), accent: "rose" as const },
              ]}
              actions={(b: WaterEmployeeCreditBalance) => (
                <div className="flex gap-2">
                  <Button size="sm" variant="outline" className="h-10 flex-1" onClick={() => setStatementFor(b)}>
                    <Eye className="h-4 w-4 mr-1" /> Statement
                  </Button>
                  {canManage && b.balance > 0 && (
                    <Button size="sm" className="h-10 flex-1" onClick={() => setPayoutFor(b)}>
                      <Banknote className="h-4 w-4 mr-1" /> Pay out
                    </Button>
                  )}
                </div>
              )}
              desktopTable={
                <Card><CardContent className="p-0 overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Staff</TableHead>
                        <TableHead>Last entry</TableHead>
                        <TableHead className="text-right">Kept</TableHead>
                        <TableHead className="text-right">Paid out</TableHead>
                        <TableHead className="text-right">Holding</TableHead>
                        <TableHead className="w-56" />
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {rows.map((b) => (
                        <TableRow key={b.waterStaffId}>
                          <TableCell>
                            <div className="font-medium">{b.staffName}</div>
                            <div className="text-xs text-slate-500">
                              {b.staffRole || "Staff"}{!b.isActive && " · inactive"}
                            </div>
                          </TableCell>
                          <TableCell>{fmtDate(b.lastEntryDate)}</TableCell>
                          <TableCell className="text-right tabular-nums text-emerald-700">{fmt(b.totalIn)}</TableCell>
                          <TableCell className="text-right tabular-nums text-rose-600">{fmt(b.totalPaidOut)}</TableCell>
                          <TableCell className="text-right tabular-nums font-semibold">{fmt(b.balance)}</TableCell>
                          <TableCell className="text-right space-x-2">
                            <Button size="sm" variant="outline" onClick={() => setStatementFor(b)}>
                              <Eye className="h-4 w-4 mr-1" /> Statement
                            </Button>
                            {canManage && b.balance > 0 && (
                              <Button size="sm" onClick={() => setPayoutFor(b)}>
                                <Banknote className="h-4 w-4 mr-1" /> Pay out
                              </Button>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent></Card>
              }
            />
          )}
        </main>
      </div>

      {/* ---- Statement ---------------------------------------------------- */}
      <Dialog open={!!statementFor} onOpenChange={(o) => { if (!o) { setStatementFor(null); setEntries([]) } }}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-3xl")}>
          <DialogHeader>
            <FormDialogTitle icon={PiggyBank} color="emerald">
              {statementFor?.staffName} — employee credit
            </FormDialogTitle>
            <DialogDescription>
              Holding <strong>{fmt(statementFor?.balance ?? 0)}</strong> for them now. Reversed entries
              stay on the statement, struck through, so the balance can always be explained.
            </DialogDescription>
          </DialogHeader>
          <div className="min-w-0">
            {entriesLoading ? (
              <div className="flex items-center gap-2 py-4 text-sm text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : entries.length === 0 ? (
              <p className="py-4 text-sm text-slate-500">No entries.</p>
            ) : (
              <div className="space-y-2">
                {entries.map((e) => {
                  const reversed = e.status === "Reversed"
                  return (
                    <div key={e.waterEmployeeCreditId}
                         className={cn("rounded-md border bg-white p-3", reversed && "opacity-60")}>
                      <div className="flex flex-wrap items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <Badge className={entryTone(e.entryType)}>
                              {EMPLOYEE_CREDIT_ENTRY_LABELS[e.entryType] ?? e.entryType}
                            </Badge>
                            <span className="text-sm text-slate-600">{fmtDate(e.entryDate)}</span>
                            {reversed && <Badge className="bg-slate-200 text-slate-600">Reversed</Badge>}
                          </div>
                          <div className="mt-1 text-xs text-slate-500 break-words">
                            {e.payrollPeriod ? `Payroll ${e.payrollPeriod}` : e.description}
                            {e.accountName && ` · ${e.accountName}`}
                            {e.paymentMethod && ` · ${e.paymentMethod}`}
                            {e.reference && ` · Ref ${e.reference}`}
                          </div>
                          {reversed && e.reversalReason && (
                            <div className="mt-1 text-xs text-slate-500">Reversed: {e.reversalReason}</div>
                          )}
                        </div>
                        <div className="text-right">
                          <div className={cn("font-semibold tabular-nums",
                                             reversed && "line-through",
                                             e.signedAmount < 0 ? "text-rose-600" : "text-emerald-700")}>
                            {e.signedAmount < 0 ? "−" : "+"}{fmt(Math.abs(e.signedAmount))}
                          </div>
                          {!reversed && (
                            <div className="text-xs text-slate-500 tabular-nums">Balance {fmt(e.runningBalance)}</div>
                          )}
                        </div>
                      </div>
                      {canManage && !reversed && (
                        <div className="mt-2 flex justify-end">
                          {e.entryType === "PayrollSaving" ? (
                            <span className="text-[11px] text-slate-500">
                              Undo by reopening that payroll.
                            </span>
                          ) : (
                            <Button size="sm" variant="ghost" className="h-9 text-rose-600"
                                    onClick={() => { setReversing(e); setReason("") }}>
                              <Undo2 className="h-4 w-4 mr-1" /> Reverse
                            </Button>
                          )}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            )}
          </div>
          <FormDialogFooter onCancel={() => { setStatementFor(null); setEntries([]) }} cancelLabel="Close">
            {canManage && statementFor && statementFor.balance > 0 && (
              <Button className={FORM_DIALOG_PRIMARY.emerald} onClick={() => setPayoutFor(statementFor)}>
                <Banknote className="h-4 w-4 mr-1" /> Pay out
              </Button>
            )}
          </FormDialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---- Reverse ------------------------------------------------------ */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) setReversing(null) }}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-lg")}>
          <DialogHeader>
            <FormDialogTitle icon={Undo2} color="rose">Reverse this entry?</FormDialogTitle>
            <DialogDescription>
              {reversing && (
                <>
                  {EMPLOYEE_CREDIT_ENTRY_LABELS[reversing.entryType]} of {fmt(reversing.amount)} on{" "}
                  {fmtDate(reversing.entryDate)}.{" "}
                  {reversing.entryType === "Payout" && "The money goes back into the cash account and back onto their credit."}
                  {reversing.entryType === "Deposit" && "The money is taken back out of the cash account."}
                  {reversing.entryType === "WagesOwed" && "The payroll cost it added is removed."}
                  {reversing.entryType === "OpeningBalance" && "Their credit goes down by this amount."}
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 pb-4">
            <Label>Reason *</Label>
            <ReasonSelect options={REVERSAL_REASONS} value={reason} onChange={setReason} />
          </div>
          <FormDialogFooter onCancel={() => setReversing(null)} cancelDisabled={busy}>
            <Button className={FORM_DIALOG_PRIMARY.rose} disabled={busy || !reason.trim()} onClick={() => void doReverse()}>
              {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Reverse
            </Button>
          </FormDialogFooter>
        </DialogContent>
      </Dialog>

      <AddCreditDialog
        open={addOpen}
        onClose={() => setAddOpen(false)}
        staff={staff}
        accounts={accounts}
        fmt={fmt}
        onDone={afterChange}
      />
      <PayoutDialog
        target={payoutFor}
        onClose={() => setPayoutFor(null)}
        accounts={accounts}
        fmt={fmt}
        onDone={afterChange}
      />
    </div>
  )
}

// ---------------------------------------------------------------------------
// Add credit by hand: opening balance, money handed in, or wages owed.
// Top-level, so typing never remounts it.
// ---------------------------------------------------------------------------
function AddCreditDialog({ open, onClose, staff, accounts, fmt, onDone }: {
  open: boolean
  onClose: () => void
  staff: WaterStaff[]
  accounts: WaterCashAccount[]
  fmt: (n: number) => string
  onDone: () => Promise<void>
}) {
  const { toast } = useToast()
  const [staffId, setStaffId] = useState("")
  const [type, setType] = useState<EmployeeCreditManualType>("OpeningBalance")
  const [amount, setAmount] = useState(0)
  const [date, setDate] = useState(today())
  const [accountId, setAccountId] = useState("")
  const [method, setMethod] = useState("Cash")
  const [reference, setReference] = useState("")
  const [description, setDescription] = useState("")
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (open) {
      setStaffId(""); setType("OpeningBalance"); setAmount(0); setDate(today())
      setAccountId(accounts[0] ? String(accounts[0].waterCashAccountId) : "")
      setMethod("Cash"); setReference(""); setDescription("")
    }
  }, [open, accounts])

  const isDeposit = type === "Deposit"
  const valid = !!staffId && amount > 0 && !!date && (!isDeposit || !!accountId)

  const save = async () => {
    if (!valid) return
    setBusy(true)
    try {
      await addWaterEmployeeCredit({
        waterStaffId: Number(staffId),
        entryType: type,
        amount,
        entryDate: date,
        waterCashAccountId: isDeposit ? Number(accountId) : null,
        paymentMethod: isDeposit ? method : null,
        reference: reference || null,
        description: description || null,
      })
      toast({ title: "Credit added" })
      onClose()
      await onDone()
    } catch (e: any) {
      toast({ title: "Could not add credit", description: e?.message, variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={PiggyBank} color="emerald">Add employee credit</FormDialogTitle>
          <DialogDescription>
            To keep part of a wage from payroll, use the payroll line&apos;s deductions instead.
          </DialogDescription>
        </DialogHeader>
        <div className="min-w-0 space-y-4">
          <FormSection title="Who and what" color="emerald" tinted>
            <div className="space-y-1">
              <Label>Staff *</Label>
              <Select value={staffId} onValueChange={setStaffId}>
                <SelectTrigger className="h-11 sm:h-10"><SelectValue placeholder="Choose staff" /></SelectTrigger>
                <SelectContent>
                  {staff.map((s) => (
                    <SelectItem key={s.waterStaffId} value={String(s.waterStaffId)}>
                      {s.firstName} {s.lastName}{!s.isActive ? " (inactive)" : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Kind *</Label>
              <Select value={type} onValueChange={(v) => setType(v as EmployeeCreditManualType)}>
                <SelectTrigger className="h-11 sm:h-10"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {EMPLOYEE_CREDIT_MANUAL_TYPES.map((t) => (
                    <SelectItem key={t} value={t}>{MANUAL_HELP[t].title}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <p className="sm:col-span-2 rounded-md bg-white/70 p-2 text-xs text-slate-700">
              {MANUAL_HELP[type].text}
            </p>
          </FormSection>

          <FormSection title="Amount" color="emerald" tinted>
            <div className="space-y-1">
              <Label>Amount *</Label>
              <NumberInput step="0.01" value={amount} onChange={(e) => setAmount(Number(e.target.value) || 0)} />
            </div>
            <div className="space-y-1">
              <Label>Date *</Label>
              <Input type="date" value={date} max={today()} onChange={(e) => setDate(e.target.value)} className="h-11 sm:h-10" />
            </div>
            {isDeposit && (
              <>
                <div className="space-y-1">
                  <Label>Into account *</Label>
                  <Select value={accountId} onValueChange={setAccountId}>
                    <SelectTrigger className="h-11 sm:h-10"><SelectValue placeholder="Choose account" /></SelectTrigger>
                    <SelectContent>
                      {accounts.map((a) => (
                        <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
                          {a.accountName} — {fmt(a.currentBalance)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label>How</Label>
                  <Select value={method} onValueChange={setMethod}>
                    <SelectTrigger className="h-11 sm:h-10"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </>
            )}
            <div className="space-y-1">
              <Label>Reference</Label>
              <Input value={reference} onChange={(e) => setReference(e.target.value)} className="h-11 sm:h-10" />
            </div>
            <div className="space-y-1">
              <Label>Note</Label>
              <Input value={description} onChange={(e) => setDescription(e.target.value)} className="h-11 sm:h-10"
                     placeholder="Saving for school fees…" />
            </div>
          </FormSection>
        </div>
        <FormDialogFooter onCancel={onClose} cancelDisabled={busy}>
          <Button className={FORM_DIALOG_PRIMARY.emerald} disabled={busy || !valid} onClick={() => void save()}>
            {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
            Add credit{amount > 0 ? ` · ${fmt(amount)}` : ""}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
// Pay out. Cash leaves; no expense.
// ---------------------------------------------------------------------------
function PayoutDialog({ target, onClose, accounts, fmt, onDone }: {
  target: WaterEmployeeCreditBalance | null
  onClose: () => void
  accounts: WaterCashAccount[]
  fmt: (n: number) => string
  onDone: () => Promise<void>
}) {
  const { toast } = useToast()
  const [amount, setAmount] = useState(0)
  const [date, setDate] = useState(today())
  const [accountId, setAccountId] = useState("")
  const [method, setMethod] = useState("Cash")
  const [reference, setReference] = useState("")
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (target) {
      setAmount(target.balance); setDate(today()); setMethod("Cash"); setReference("")
      setAccountId(accounts[0] ? String(accounts[0].waterCashAccountId) : "")
    }
  }, [target, accounts])

  const account = accounts.find((a) => String(a.waterCashAccountId) === accountId)
  const over = !!target && amount > target.balance
  const overdraw = !!account && !account.allowNegativeBalance && amount > account.currentBalance
  const valid = !!target && amount > 0 && !over && !overdraw && !!accountId && !!date

  const save = async () => {
    if (!target || !valid) return
    setBusy(true)
    try {
      await payoutWaterEmployeeCredit({
        waterStaffId: target.waterStaffId,
        amount,
        waterCashAccountId: Number(accountId),
        entryDate: date,
        paymentMethod: method,
        reference: reference || null,
      })
      toast({ title: `Paid ${fmt(amount)} to ${target.staffName}` })
      onClose()
      await onDone()
    } catch (e: any) {
      toast({ title: "Could not pay out", description: e?.message, variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog open={!!target} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Wallet} color="emerald">Pay out to {target?.staffName}</FormDialogTitle>
          <DialogDescription>
            You are holding {fmt(target?.balance ?? 0)} for them. Paying it out takes cash from the
            account and lowers what you owe them. <strong>It is not an expense</strong> — the wage
            was already counted as payroll cost when it was kept.
          </DialogDescription>
        </DialogHeader>
        <div className="min-w-0 space-y-4">
          <FormSection title="Payment" color="emerald" tinted>
            <div className="space-y-1">
              <Label>Amount *</Label>
              <NumberInput step="0.01" value={amount} onChange={(e) => setAmount(Number(e.target.value) || 0)} />
              <div className="flex items-center gap-2">
                <button type="button" className="text-[11px] text-emerald-700 underline underline-offset-2"
                        onClick={() => target && setAmount(target.balance)}>
                  Pay all ({fmt(target?.balance ?? 0)})
                </button>
              </div>
              {over && <p className="text-[11px] text-rose-600">You are only holding {fmt(target?.balance ?? 0)}.</p>}
            </div>
            <div className="space-y-1">
              <Label>Date *</Label>
              <Input type="date" value={date} max={today()} onChange={(e) => setDate(e.target.value)} className="h-11 sm:h-10" />
            </div>
            <div className="space-y-1">
              <Label>From account *</Label>
              <Select value={accountId} onValueChange={setAccountId}>
                <SelectTrigger className="h-11 sm:h-10"><SelectValue placeholder="Choose account" /></SelectTrigger>
                <SelectContent>
                  {accounts.map((a) => (
                    <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
                      {a.accountName} — {fmt(a.currentBalance)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {overdraw && (
                <p className="text-[11px] text-rose-600">
                  {account?.accountName} only has {fmt(account?.currentBalance ?? 0)}.
                </p>
              )}
            </div>
            <div className="space-y-1">
              <Label>How</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger className="h-11 sm:h-10"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1 sm:col-span-2">
              <Label>Reference</Label>
              <Input value={reference} onChange={(e) => setReference(e.target.value)} className="h-11 sm:h-10"
                     placeholder="MoMo transaction ID, receipt number…" />
            </div>
          </FormSection>
        </div>
        <FormDialogFooter onCancel={onClose} cancelDisabled={busy}>
          <Button className={FORM_DIALOG_PRIMARY.emerald} disabled={busy || !valid} onClick={() => void save()}>
            {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
            Pay out{amount > 0 ? ` · ${fmt(amount)}` : ""}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

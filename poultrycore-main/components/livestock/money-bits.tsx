"use client"

// Small pieces shared by the money pages: the cash account picker (with what
// each holds and a too-little warning), a period picker, and the words for
// cash categories.

import { useCallback, useEffect, useState } from "react"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { listCashAccounts, type CashAccount } from "@/lib/api/livestock"
import { fmtMoney, todayIso } from "./livestock-page"

export function useCashAccounts() {
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const reload = useCallback(() => listCashAccounts().then(setAccounts).catch(() => setAccounts([])), [])
  useEffect(() => { reload() }, [reload])
  const defaultId = accounts.find((a) => a.isDefault)?.accountId ?? accounts[0]?.accountId ?? null
  return { accounts, defaultId, reload }
}

export function AccountSelect({ label = "Account", value, onChange, accounts, spend, exclude }: {
  label?: string
  value: number | null
  onChange: (id: number) => void
  accounts: CashAccount[]
  /** Money leaving the account: warns when it holds less. */
  spend?: number
  exclude?: number | null
}) {
  const acct = accounts.find((a) => a.accountId === value)
  const short = acct && spend != null && spend > 0 && !acct.allowNegative && spend > acct.balance
  return (
    <div>
      <Label>{label}</Label>
      <Select value={value ? String(value) : ""} onValueChange={(v) => onChange(Number(v))}>
        <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
        <SelectContent>
          {accounts.filter((a) => a.accountId !== exclude).map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name} · {fmtMoney(a.balance)}</SelectItem>)}
        </SelectContent>
      </Select>
      {short && <p className="text-xs text-rose-700 mt-1">{acct!.name} holds only {fmtMoney(acct!.balance)}.</p>}
    </div>
  )
}

export function isShort(accounts: CashAccount[], id: number | null, spend: number) {
  const a = accounts.find((x) => x.accountId === id)
  return !!a && !a.allowNegative && spend > a.balance
}

export const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01` }
export const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export function PeriodPicker({ from, to, onChange }: { from: string; to: string; onChange: (from: string, to: string) => void }) {
  const preset = (key: string) => {
    const d = new Date()
    const iso = (x: Date) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, "0")}-${String(x.getDate()).padStart(2, "0")}`
    if (key === "month") onChange(firstOfMonth(), todayIso())
    if (key === "last") { const s = new Date(d.getFullYear(), d.getMonth() - 1, 1); const e = new Date(d.getFullYear(), d.getMonth(), 0); onChange(iso(s), iso(e)) }
    if (key === "year") onChange(`${d.getFullYear()}-01-01`, todayIso())
    if (key === "90") onChange(daysAgo(90), todayIso())
  }
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <Input type="date" className="w-40" value={from} max={to} onChange={(e) => onChange(e.target.value, to)} aria-label="From" />
      <span className="text-sm text-stone-500">to</span>
      <Input type="date" className="w-40" value={to} min={from} onChange={(e) => onChange(from, e.target.value)} aria-label="To" />
      <Select onValueChange={preset}>
        <SelectTrigger className="w-40"><SelectValue placeholder="Quick pick" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="month">This month</SelectItem>
          <SelectItem value="last">Last month</SelectItem>
          <SelectItem value="90">Last 90 days</SelectItem>
          <SelectItem value="year">This year</SelectItem>
        </SelectContent>
      </Select>
    </div>
  )
}

/** How each kind of cash movement reads. */
export const CASH_CATEGORY_LABEL: Record<string, string> = {
  CustomerPayment: "Received from customers",
  SupplierPayment: "Paid to suppliers",
  Purchase: "Paid for purchases",
  Expense: "Expenses",
  Payroll: "Staff pay",
  StaffLoan: "Advances to staff",
  StaffLoanRepayment: "Advances repaid by staff",
  OwnerIn: "Owner put in",
  OwnerOut: "Owner took out",
  LoanIn: "Loans received",
  LoanRepayment: "Loan repayments",
  AssetPurchase: "Assets bought",
  AssetSale: "Assets sold",
  CashDifference: "Cash differences at counts",
  Transfer: "Moved between accounts",
}

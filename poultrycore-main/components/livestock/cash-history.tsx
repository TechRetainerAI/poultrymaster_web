"use client"

// Transaction History on Cash flow -- every money movement in the period,
// across all cash accounts, with the running cash after each one. Like the
// poultry Cash Flow page's Transaction History.
//
// Built from each account's own ledger (getCashAccount for the same dates), so
// it adds up to the same numbers as the account pages. Money moved between
// your own accounts shows on both sides and nets to nothing. Reversed rows are
// shown greyed and leave the running cash alone.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Search, X } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { getCashAccount, listCashAccounts, type CashTransaction } from "@/lib/api/livestock"
import { CASH_CATEGORY_LABEL } from "./money-bits"
import { LoadError, Loading, fmtDate, fmtMoney } from "./livestock-page"

const ALL = "__all"
type Tx = CashTransaction & { accountId: number; accountName: string; running: number }

/** Where a movement was recorded, so it can be opened there. */
function sourceLink(t: CashTransaction): string | null {
  switch (t.sourceType ?? t.category) {
    case "Purchase": return t.sourceId ? `/livestock-purchases/${t.sourceId}` : "/livestock-purchases"
    case "Sale": return t.sourceId ? `/livestock-sales/${t.sourceId}` : "/livestock-sales"
    case "CustomerPayment": return "/livestock-customer-payments"
    case "SupplierPayment": return "/livestock-supplier-payments"
    case "Expense": return "/livestock-expenses"
    case "Payroll": return "/livestock-payroll"
    case "StaffLoan": case "StaffLoanRepayment": return "/livestock-staff"
    case "OwnerIn": case "OwnerOut": return "/livestock-owner-money"
    case "LoanIn": case "LoanRepayment": return "/livestock-loans"
    case "AssetPurchase": case "AssetSale": return "/livestock-assets"
    case "CashDifference": return "/livestock-cash-reconciliation"
    case "Transfer": return "/livestock-cash-transfers"
    default: return null
  }
}
const typeLabel = (c: string) => CASH_CATEGORY_LABEL[c] ?? c

export function CashHistory({ from, to }: { from: string; to: string }) {
  const [txs, setTxs] = useState<Tx[] | null>(null)
  const [start, setStart] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [reload, setReload] = useState(0)
  const [search, setSearch] = useState("")
  const [dir, setDir] = useState<typeof ALL | "in" | "out">(ALL)
  const [type, setType] = useState(ALL)
  const [account, setAccount] = useState(ALL)

  useEffect(() => {
    let gone = false
    setTxs(null); setError(null)
    ;(async () => {
      try {
        const accounts = await listCashAccounts(true)
        const details = await Promise.all(accounts.map((a) => getCashAccount(a.accountId, from, to)))
        const opening = details.reduce((s, d) => s + d.balanceBefore, 0)
        const merged = details.flatMap((d) => d.transactions.map((t) => ({ ...t, accountId: d.accountId, accountName: d.name, running: 0 })))
        // Running cash, oldest first, then shown newest first.
        merged.sort((a, b) => a.date.localeCompare(b.date) || a.txId - b.txId)
        let run = opening
        for (const t of merged) { if (!t.reversedAt) run += t.amount; t.running = run }
        if (!gone) { setStart(opening); setTxs(merged.reverse()) }
      } catch (e: any) { if (!gone) setError(e?.message ?? String(e)) }
    })()
    return () => { gone = true }
  }, [from, to, reload])

  const all = txs ?? []
  const types = useMemo(() => [...new Set(all.map((t) => t.category))].sort((a, b) => typeLabel(a).localeCompare(typeLabel(b))), [all])
  const accounts = useMemo(() => {
    const m = new Map<string, string>()
    for (const t of all) m.set(String(t.accountId), t.accountName)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [all])
  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    return all.filter((t) =>
      (dir === ALL || (dir === "in" ? t.amount > 0 : t.amount < 0))
      && (type === ALL || t.category === type)
      && (account === ALL || String(t.accountId) === account)
      && (!q || [t.description, typeLabel(t.category), t.accountName, t.createdBy].some((v) => v?.toLowerCase().includes(q))))
  }, [all, dir, type, account, search])
  const pg = usePagination(shown, 10)
  const filtering = !!search || dir !== ALL || type !== ALL || account !== ALL
  const clear = () => { setSearch(""); setDir(ALL); setType(ALL); setAccount(ALL) }

  return (
    <section className="rounded-lg border bg-white">
      <div className="flex flex-wrap items-start justify-between gap-2 border-b px-4 py-3">
        <div>
          <h3 className="text-base font-semibold text-stone-900">Transaction History</h3>
          <p className="text-xs text-stone-500">Every cash movement in the selected period, across all accounts. Started the period with {fmtMoney(start)}.</p>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2 border-b bg-stone-50/60 px-4 py-2">
        <div className="relative min-w-[180px] flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-stone-400" />
          <Input className="h-8 pl-9 bg-white" placeholder="Description, type or account" value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <Select value={dir} onValueChange={(v) => setDir(v as typeof dir)}>
          <SelectTrigger className="h-8 w-36 bg-white"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>In and out</SelectItem>
            <SelectItem value="in">Money in</SelectItem>
            <SelectItem value="out">Money out</SelectItem>
          </SelectContent>
        </Select>
        <Select value={type} onValueChange={setType}>
          <SelectTrigger className="h-8 w-48 bg-white"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All types</SelectItem>
            {types.map((c) => <SelectItem key={c} value={c}>{typeLabel(c)}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={account} onValueChange={setAccount}>
          <SelectTrigger className="h-8 w-40 bg-white"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All accounts</SelectItem>
            {accounts.map(([id, name]) => <SelectItem key={id} value={id}>{name}</SelectItem>)}
          </SelectContent>
        </Select>
        {filtering && <Button variant="ghost" size="sm" className="h-8 text-amber-800" onClick={clear}><X className="h-4 w-4 mr-1" />Clear</Button>}
      </div>

      {error ? <div className="p-4"><LoadError message={error} onRetry={() => setReload((n) => n + 1)} /></div> : !txs ? <div className="p-4"><Loading /></div> : shown.length === 0 ? (
        <p className="px-4 py-8 text-center text-sm text-stone-500">
          {filtering ? "No movement matches these filters." : "No cash movement in this period. Record a sale, an expense or a payment and it appears here."}
        </p>
      ) : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Account</TableHead><TableHead>Description</TableHead>
                <TableHead className="text-right">Money In</TableHead><TableHead className="text-right">Money Out</TableHead><TableHead className="text-right">Running cash</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((t) => {
                const href = sourceLink(t)
                return (
                  <TableRow key={`${t.accountId}-${t.txId}`} className={t.reversedAt ? "opacity-50" : t.category === "Transfer" ? "bg-stone-50" : undefined}>
                    <TableCell className="whitespace-nowrap">{fmtDate(t.date)}</TableCell>
                    <TableCell className="whitespace-nowrap">{typeLabel(t.category)}{t.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                    <TableCell className="whitespace-nowrap text-stone-600">{t.accountName}</TableCell>
                    <TableCell className="max-w-sm whitespace-normal break-words">
                      {href ? <Link className="text-amber-800 hover:underline" href={href}>{t.description ?? typeLabel(t.category)}</Link> : (t.description ?? "—")}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-emerald-700">{t.amount > 0 ? fmtMoney(t.amount) : "—"}</TableCell>
                    <TableCell className="text-right tabular-nums text-rose-600">{t.amount < 0 ? fmtMoney(-t.amount) : "—"}</TableCell>
                    <TableCell className="text-right tabular-nums font-medium">{fmtMoney(t.running)}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
    </section>
  )
}

"use client"

// One cash account: what it holds and every movement of money through it.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams } from "next/navigation"
import { Wallet } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { getCashAccount, type CashAccountDetail, type CashTransaction } from "@/lib/api/livestock"
import { ACCOUNT_TYPE_LABEL } from "@/components/livestock/labels"
import { LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

function sourceLink(t: CashTransaction): string | null {
  if (t.sourceType === "SupplierPayment") return "/livestock-supplier-balances"
  if (t.sourceType === "Purchase" && t.sourceId) return `/livestock-purchases/${t.sourceId}`
  return null
}

export default function LivestockCashAccountPage() {
  const { id } = useParams<{ id: string }>()
  const accountId = Number(id)
  const [a, setA] = useState<CashAccountDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [from, setFrom] = useState(daysAgo(30))
  const [to, setTo] = useState(todayIso())

  const load = useCallback(async () => {
    setError(null)
    try { setA(await getCashAccount(accountId, from, to)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [accountId, from, to])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-cash-accounts", label: "Cash accounts" }
  if (error) return <LivestockPage title="Account" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!a) return <LivestockPage title="Account" back={back}><Loading /></LivestockPage>

  const live = a.transactions.filter((t) => !t.reversedAt)
  const moneyIn = live.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0)
  const moneyOut = -live.filter((t) => t.amount < 0).reduce((s, t) => s + t.amount, 0)
  // Running balance, oldest first, then shown newest first.
  let run = a.balanceBefore
  const withBalance = [...a.transactions].reverse().map((t) => { if (!t.reversedAt) run += t.amount; return { ...t, after: run } }).reverse()

  return (
    <LivestockPage title={a.name} description={`${ACCOUNT_TYPE_LABEL[a.accountType]} · opened ${fmtDate(a.openingDate)} with ${fmtMoney(a.openingBalance)}`} icon={Wallet} back={back}>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <StatCard label="Holds now" value={fmtMoney(a.balance)} tone={a.balance < 0 ? "rose" : "amber"} />
        <StatCard label="At start of period" value={fmtMoney(a.balanceBefore)} />
        <StatCard label="Money in" value={fmtMoney(moneyIn)} tone="emerald" />
        <StatCard label="Money out" value={fmtMoney(moneyOut)} tone="rose" />
      </div>
      <div className="flex items-center gap-2">
        <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <span className="text-sm text-stone-500">to</span>
        <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
      </div>
      <div className="rounded-md border bg-white overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow><TableHead>Date</TableHead><TableHead>What</TableHead><TableHead className="text-right">In</TableHead><TableHead className="text-right">Out</TableHead><TableHead className="text-right">Balance</TableHead></TableRow>
          </TableHeader>
          <TableBody>
            {withBalance.length === 0 && <TableRow><TableCell colSpan={5} className="text-center text-stone-500 py-6">No money moved in these dates.</TableCell></TableRow>}
            {withBalance.map((t) => {
              const href = sourceLink(t)
              return (
                <TableRow key={t.txId} className={t.reversedAt ? "opacity-50" : undefined}>
                  <TableCell className="whitespace-nowrap">{fmtDate(t.date)}</TableCell>
                  <TableCell>
                    {href ? <Link className="text-amber-800 hover:underline" href={href}>{t.description ?? t.category}</Link> : (t.description ?? t.category)}
                    {t.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                  </TableCell>
                  <TableCell className="text-right text-emerald-700">{t.amount > 0 ? fmtMoney(t.amount) : ""}</TableCell>
                  <TableCell className="text-right text-rose-700">{t.amount < 0 ? fmtMoney(-t.amount) : ""}</TableCell>
                  <TableCell className="text-right">{fmtMoney(t.after)}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
    </LivestockPage>
  )
}

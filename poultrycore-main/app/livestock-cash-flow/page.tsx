"use client"

// Cash Flow -- the money the farm had at the start, where money came from
// and went, and what is left, account by account; then the Transaction
// History of every movement (components/livestock/cash-history.tsx).

import { useCallback, useEffect, useState } from "react"
import { Waves } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { getCashFlow, type CashFlow } from "@/lib/api/livestock"
import { CASH_CATEGORY_LABEL, PeriodPicker, firstOfMonth } from "@/components/livestock/money-bits"
import { CashHistory } from "@/components/livestock/cash-history"
import { LivestockPage, LoadError, Loading, StatCard, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockCashFlowPage() {
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [cf, setCf] = useState<CashFlow | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null); setCf(null)
    try { setCf(await getCashFlow(from, to)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage title="Cash flow" description="Where the farm's money came from and went." icon={Waves}>
      <PeriodPicker from={from} to={to} onChange={(a, b) => { setFrom(a); setTo(b) }} />
      {error ? <LoadError message={error} onRetry={load} /> : !cf ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Money at the start" value={fmtMoney(cf.opening + cf.accountsOpened)} hint={cf.accountsOpened ? `${fmtMoney(cf.accountsOpened)} from accounts opened in the period` : undefined} />
            <StatCard label="Money in" value={fmtMoney(cf.totalIn)} tone="emerald" />
            <StatCard label="Money out" value={fmtMoney(cf.totalOut)} tone="rose" />
            <StatCard label="Money at the end" value={fmtMoney(cf.closing)} tone="amber" />
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Money in</CardTitle></CardHeader>
              <CardContent className="text-sm space-y-1">
                {cf.moneyIn.length === 0 ? <p className="text-stone-500">None.</p> : cf.moneyIn.map((m) => (
                  <div key={m.category} className="flex justify-between"><span>{CASH_CATEGORY_LABEL[m.category] ?? m.category}</span><span>{fmtMoney(m.amount)}</span></div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Money out</CardTitle></CardHeader>
              <CardContent className="text-sm space-y-1">
                {cf.moneyOut.length === 0 ? <p className="text-stone-500">None.</p> : cf.moneyOut.map((m) => (
                  <div key={m.category} className="flex justify-between"><span>{CASH_CATEGORY_LABEL[m.category] ?? m.category}</span><span>{fmtMoney(m.amount)}</span></div>
                ))}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">At the end, by account</CardTitle></CardHeader>
              <CardContent className="text-sm space-y-1">
                {cf.accounts.map((a) => <div key={a.accountId} className="flex justify-between"><span>{a.name}</span><span>{fmtMoney(a.closing)}</span></div>)}
              </CardContent>
            </Card>
          </div>
          <p className="text-xs text-stone-500">Money moved between your own accounts is left out: it neither comes in nor goes out of the farm.</p>
          <CashHistory from={from} to={to} />
        </>
      )}
    </LivestockPage>
  )
}

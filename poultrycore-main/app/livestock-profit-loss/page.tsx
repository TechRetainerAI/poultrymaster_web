"use client"

// Profit & Loss -- what the farm (or one group) earned and spent over a
// period, and every group side by side. Built from the records themselves:
// sales, stock used, animals bought, expenses, pay, interest, wear and tear.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { TrendingUp } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { getProfitByGroup, getProfitLoss, listGroups, type GroupProfit, type LivestockGroup, type ProfitLoss } from "@/lib/api/livestock"
import { PeriodPicker, firstOfMonth } from "@/components/livestock/money-bits"
import { LivestockPage, LoadError, Loading, StatCard, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

const ALL = "__all"

function Row({ label, value, strong, indent }: { label: string; value: number; strong?: boolean; indent?: boolean }) {
  if (!strong && !value) return null
  return (
    <div className={`flex justify-between py-1 ${strong ? "font-semibold border-t mt-1 pt-2" : ""} ${indent ? "pl-4 text-stone-600" : ""}`}>
      <span>{label}</span><span>{fmtMoney(value)}</span>
    </div>
  )
}

export default function LivestockProfitLossPage() {
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [groupId, setGroupId] = useState(ALL)
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [pl, setPl] = useState<ProfitLoss | null>(null)
  const [byGroup, setByGroup] = useState<GroupProfit[]>([])
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { listGroups(true).then(setGroups).catch(() => setGroups([])) }, [])
  const load = useCallback(async () => {
    setError(null); setPl(null)
    try {
      const [p, g] = await Promise.all([getProfitLoss(from, to, groupId === ALL ? undefined : Number(groupId)), getProfitByGroup(from, to)])
      setPl(p); setByGroup(g)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to, groupId])
  useEffect(() => { load() }, [load])

  const pg = usePagination(byGroup, 10)
  return (
    <LivestockPage title="Profit & loss" description="What the farm earned and spent." icon={TrendingUp}>
      <div className="flex items-center gap-3 flex-wrap">
        <PeriodPicker from={from} to={to} onChange={(a, b) => { setFrom(a); setTo(b) }} />
        <Select value={groupId} onValueChange={setGroupId}>
          <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>Whole farm</SelectItem>{groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}</SelectContent>
        </Select>
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !pl ? <Loading /> : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <StatCard label="Income" value={fmtMoney(pl.income.total)} tone="emerald" />
            <StatCard label="Costs" value={fmtMoney(pl.costs.total)} tone="rose" />
            <StatCard label={pl.profit >= 0 ? "Profit" : "Loss"} value={fmtMoney(Math.abs(pl.profit))} tone={pl.profit >= 0 ? "amber" : "rose"} />
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Income</CardTitle></CardHeader>
              <CardContent className="text-sm">
                <Row label="Animals sold" value={pl.income.animals} />
                <Row label="Eggs, milk and other produce" value={pl.income.produce} />
                <Row label="Other stock sold" value={pl.income.otherStock} />
                <Row label="Gain on assets sold" value={pl.income.assetGain} />
                <Row label="Total income" value={pl.income.total} strong />
                {pl.producesNotByGroup && <p className="text-xs text-stone-500 mt-2">Eggs and milk sold are counted for the whole farm, not one group.</p>}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Costs</CardTitle></CardHeader>
              <CardContent className="text-sm">
                <Row label="Animals bought" value={pl.costs.animalsBought} />
                <Row label="Feed used" value={pl.costs.feed} />
                <Row label="Medicine and vaccines used" value={pl.costs.medicine} />
                <Row label="Other stock used" value={pl.costs.otherStock} />
                <Row label="Cost of stock sold" value={pl.costs.stockSold} />
                <Row label="Stock lost or damaged" value={pl.costs.stockLost} />
                {pl.costs.expenses.map((e) => <Row key={e.category} label={e.category} value={e.amount} />)}
                <Row label="Staff pay" value={pl.costs.staffPay} />
                <Row label="Loan interest" value={pl.costs.loanInterest} />
                <Row label="Wear and tear on assets" value={pl.costs.depreciation} />
                <Row label="Cash short at counts" value={pl.costs.cashDifferences} />
                <Row label="Loss on assets sold" value={pl.costs.assetLoss} />
                <Row label="Total costs" value={pl.costs.total} strong />
              </CardContent>
            </Card>
          </div>
          {groupId === ALL && byGroup.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">By group</CardTitle></CardHeader>
              <CardContent>
                <Table>
                  <TableHeader><TableRow><TableHead>Group</TableHead><TableHead className="text-right">Animals now</TableHead><TableHead className="text-right">Animals sold</TableHead><TableHead className="text-right">Feed</TableHead><TableHead className="text-right">All costs</TableHead><TableHead className="text-right">Profit</TableHead></TableRow></TableHeader>
                  <TableBody>
                    {pg.pageItems.map((g) => (
                      <TableRow key={g.groupId} className="cursor-pointer hover:bg-amber-50/60" onClick={() => setGroupId(String(g.groupId))}>
                        <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`} onClick={(e) => e.stopPropagation()}>{g.name}</Link> <span className="text-xs text-stone-500">{g.speciesName}</span></TableCell>
                        <TableCell className="text-right">{fmtNum(g.head)}</TableCell>
                        <TableCell className="text-right">{fmtMoney(g.income)}</TableCell>
                        <TableCell className="text-right">{fmtMoney(g.feed)}</TableCell>
                        <TableCell className="text-right">{fmtMoney(g.costs)}</TableCell>
                        <TableCell className={`text-right font-medium ${g.profit < 0 ? "text-rose-700" : "text-emerald-700"}`}>{fmtMoney(g.profit)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...pg.paginationProps} variant="records" />
                <p className="text-xs text-stone-500 mt-2">A group's figure counts its animal sales against the costs recorded for it. Farm-wide costs (pay, interest, wear and tear) and produce sales are in the whole-farm statement only.</p>
              </CardContent>
            </Card>
          )}
        </>
      )}
    </LivestockPage>
  )
}

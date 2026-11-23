"use client"

// Days of Supply -- how long each feed and ingredient lasts at the rate it
// has been used recently, and the day it runs out.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Hourglass } from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { getFeedSupply, type FeedSupply } from "@/lib/api/livestock"
import { CATEGORY_LABEL } from "@/components/livestock/stock-dialogs"
import { EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockFeedSupplyPage() {
  const [rows, setRows] = useState<FeedSupply[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [days, setDays] = useState("14")

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await getFeedSupply(Number(days))) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [days])
  useEffect(() => { load() }, [load])
  const pg = usePagination(rows ?? [], 10)

  return (
    <LivestockPage title="Days of supply" description="How long your feed lasts at the rate you have been using it." icon={Hourglass}>
      <div className="flex items-center gap-2 text-sm text-stone-600">
        Based on use over the last
        <Select value={days} onValueChange={setDays}>
          <SelectTrigger className="w-28"><SelectValue /></SelectTrigger>
          <SelectContent>{["7", "14", "30"].map((d) => <SelectItem key={d} value={d}>{d} days</SelectItem>)}</SelectContent>
        </Select>
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title="No feed in stock yet" />
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Feed</TableHead><TableHead>Kind</TableHead><TableHead className="text-right">In stock</TableHead>
                <TableHead className="text-right">Used per day</TableHead><TableHead className="text-right">Days left</TableHead><TableHead>Runs out</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((r) => {
                const tone = r.daysLeft == null ? "" : r.daysLeft < 3 ? "text-rose-700 font-medium" : r.daysLeft < 7 ? "text-amber-800 font-medium" : ""
                return (
                  <TableRow key={r.itemId}>
                    <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-items/${r.itemId}`}>{r.name}</Link></TableCell>
                    <TableCell>{CATEGORY_LABEL[r.category]}</TableCell>
                    <TableCell className="text-right">{fmtNum(r.stock)} {r.unit}</TableCell>
                    <TableCell className="text-right">{r.usedPerDay > 0 ? `${fmtNum(r.usedPerDay)} ${r.unit}` : "Not used lately"}</TableCell>
                    <TableCell className={`text-right ${tone}`}>{r.daysLeft == null ? "—" : fmtNum(r.daysLeft)}</TableCell>
                    <TableCell className={tone}>{r.runsOutOn ? fmtDate(r.runsOutOn) : "—"}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
    </LivestockPage>
  )
}

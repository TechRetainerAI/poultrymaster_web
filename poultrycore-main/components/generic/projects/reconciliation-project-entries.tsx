"use client"

// 501: Reconciliation -- the account's entries since its last posted count,
// with a Project / contract filter and column. Read only: counts, the system
// balance, differences and posting stay account-level. Filtering never hides a
// company entry from the count itself; it only narrows this list.

import { useEffect, useMemo, useState } from "react"
import { Loader2 } from "lucide-react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useFmt } from "@/lib/currency"
import { categoryLabel } from "@/lib/cash/cash-flow"
import { listCashTransactions, type GenericCashTransaction } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"
import { ProjectFilter } from "./project-filter"
import { ProjectCell, ProjectHead } from "./project-column"
import { useCashShares } from "./use-cash-shares"

export function ReconciliationProjectEntries({ accountId, since, reloadKey }: {
  accountId: number
  /** The last posted count; entries after it are the ones not yet reconciled. */
  since?: string | null
  reloadKey?: unknown
}) {
  const gh = useFmt()
  const [rows, setRows] = useState<GenericCashTransaction[] | null>(null)
  const [filter, setFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const shares = useCashShares(accountId, rows)

  useEffect(() => {
    if (!shares.enabled) return
    let cancelled = false
    setRows(null)
    listCashTransactions({ cashAccountId: accountId })
      .then((r) => { if (!cancelled) setRows(r ?? []) })
      .catch(() => { if (!cancelled) setRows([]) })
    return () => { cancelled = true }
  }, [accountId, reloadKey, shares.enabled])

  const sinceCount = useMemo(() => (rows ?? [])
    .filter((r) => !since || new Date(r.transactionDate) > new Date(since))
    .sort((a, b) => (a.transactionDate < b.transactionDate ? 1 : -1)), [rows, since])
  const shown = useMemo(() => sinceCount.filter((r) => shares.matches(r.genericCashTransactionId, filter)),
    [sinceCount, shares, filter])
  const projectNet = useMemo(() => filter.kind === "all" ? null
    : shown.reduce((t, r) => t + shares.part(r.genericCashTransactionId, r.amount, filter), 0), [shown, shares, filter])

  if (!shares.enabled) return null
  return (
    <Card>
      <CardHeader className="flex flex-row flex-wrap items-start justify-between gap-2 space-y-0 pb-2">
        <div>
          <CardTitle className="text-base">Entries since the last count</CardTitle>
          <CardDescription className="text-xs">
            Filter by project to see which of them belong to it. The count and the system balance always cover every entry.
          </CardDescription>
        </div>
        <ProjectFilter value={filter} onChange={setFilter} className="h-9 w-full sm:w-60" />
      </CardHeader>
      <CardContent className="p-0">
        {rows === null ? (
          <div className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading entries…</div>
        ) : shown.length === 0 ? (
          <p className="p-4 text-sm text-slate-500">{sinceCount.length === 0 ? "Nothing new since the last count." : "No entry since the last count matches this project."}</p>
        ) : (
          <div className="max-h-96 overflow-auto">
            <Table>
              <TableHeader><TableRow>
                <TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Source</TableHead>
                <TableHead className="text-right">Amount</TableHead><ProjectHead /><TableHead>Description</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {shown.map((r) => (
                  <TableRow key={r.genericCashTransactionId}>
                    <TableCell className="whitespace-nowrap">{fmtDateTime(r.transactionDate, r)}</TableCell>
                    <TableCell>{r.transactionType}</TableCell>
                    <TableCell>{categoryLabel(r.sourceType ?? "")}</TableCell>
                    <TableCell className={`text-right tabular-nums ${r.amount < 0 ? "text-rose-600" : "text-green-700"}`}>{gh(r.amount)}</TableCell>
                    <ProjectCell labels={shares.labelsOf(r.genericCashTransactionId)} />
                    <TableCell className="max-w-sm whitespace-normal break-words">{r.description ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        {projectNet != null && shown.length > 0 && (
          <p className="border-t px-4 py-2 text-xs text-slate-600">
            The project&apos;s part of these entries: <b className="tabular-nums">{gh(projectNet)}</b>
          </p>
        )}
      </CardContent>
    </Card>
  )
}

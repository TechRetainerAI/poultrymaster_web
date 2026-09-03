"use client"

/**
 * Cash Account Report — the body, shared by both rails.
 *
 * WHAT THIS REPORT IS
 * -------------------
 * Cash Flow answers "what did the business earn and spend". This answers "where
 * is the money, and which accounts are in trouble" — the ledger side. The two
 * are measured from different things on purpose and are NOT expected to agree;
 * comparing them is what reconciliation is for. Every screen that renders this
 * data today is interactive and unexportable, which is the gap this fills.
 *
 * RAIL-AGNOSTIC ON PURPOSE
 * ------------------------
 * No API import, no rail string, no id-field names. Poultry and Water each fetch
 * their own data and map it onto the structural types in lib/cash/cash-flow —
 * the same arrangement RecordCashAdjustmentDialog uses. A second copy of this
 * file would be a second place for the arithmetic to disagree with itself.
 *
 * Three exports rather than one component, because ReportShell wants the tiles,
 * the PDF definition and the body as separate props.
 */

import { useMemo, useState } from "react"
import Link from "next/link"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { cashAccountVocabulary } from "@/components/cash/cash-account-vocabulary"
import {
  calculatedCashAtHand, cashIdentity, categoryLabel, summariseTransfers,
  type CashAccountPeriodRow, type LedgerEntry, type TransferEntry,
} from "@/lib/cash/cash-flow"
import type { PdfExportOptions } from "@/lib/utils/pdf-export"
import { cn } from "@/lib/utils"

export interface CashAccountReportData {
  rows: CashAccountPeriodRow[]
  /** Ledger rows INSIDE the period only — the detail table's source. */
  entries: LedgerEntry[]
  transfers: TransferEntry[]
  fromDate: string
  toDate: string
}

/** What the totals row asserts, and what the tiles read. */
function periodTotals(rows: CashAccountPeriodRow[]) {
  const opening = rows.reduce((s, r) => s + r.openingBalance, 0)
  const moneyIn = rows.reduce((s, r) => s + r.periodIn, 0)
  const moneyOut = rows.reduce((s, r) => s + r.periodOut, 0)
  const closing = rows.reduce((s, r) => s + r.closingBalance, 0)
  const round2 = (n: number) => Math.round(n * 100) / 100
  return {
    opening: round2(opening),
    moneyIn: round2(moneyIn),
    moneyOut: round2(moneyOut),
    closing: round2(closing),
  }
}

/**
 * The one-line verdict for an account.
 *
 * Worded by account type, because "never been counted" is nonsense for a bank
 * account and "never reconciled against a statement" is nonsense for a cash box.
 * cashAccountVocabulary already owns that choice.
 */
export function accountStatusText(r: CashAccountPeriodRow, fmtMoney: (n: number) => string): string {
  const vocab = cashAccountVocabulary(r.accountType)
  if (Math.abs(r.cacheDrift) >= 0.01) {
    return `Stored balance off by ${fmtMoney(Math.abs(r.cacheDrift))}`
  }
  if (r.lastReconciledAt == null) return vocab.emptyHistory
  if (r.needsAttention && r.attentionReason) return r.attentionReason
  return `Reconciled ${r.daysSinceReconciled ?? 0}d ago`
}

// ---------------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------------

export function CashAccountTiles({
  data, fmtMoney,
}: { data: CashAccountReportData; fmtMoney: (n: number) => string }) {
  const t = periodTotals(data.rows)
  const attention = data.rows.filter((r) => r.needsAttention).length
  const uncleared = data.rows.reduce((s, r) => s + (r.unclearedCount ?? 0), 0)

  return (
    <>
      <SumTile label="Cash at hand" value={fmtMoney(calculatedCashAtHand(data.rows))} accent="indigo" />
      <SumTile label="Money in" value={fmtMoney(t.moneyIn)} accent="green" />
      <SumTile label="Money out" value={fmtMoney(t.moneyOut)} accent="rose" />
      <SumTile label="Accounts" value={`${data.rows.length}`} />
      <SumTile label="Need attention" value={`${attention}`} accent={attention > 0 ? "rose" : undefined} />
      <SumTile label="Uncleared items" value={`${uncleared}`} />
    </>
  )
}

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

/**
 * The accounts table IS the report, so that is what the PDF carries. The ledger
 * below it is supporting detail and is filterable on screen — printing a
 * filtered view as if it were the statement would be misleading.
 */
export function buildCashAccountPdf({
  data, fmtMoney, title, filename,
}: {
  data: CashAccountReportData
  fmtMoney: (n: number) => string
  title: string
  filename: string
}): PdfExportOptions {
  const t = periodTotals(data.rows)
  const identity = cashIdentity({
    openingTotal: t.opening,
    totals: {
      moneyIn: t.moneyIn, moneyOut: t.moneyOut, net: t.moneyIn - t.moneyOut,
      transferVolume: 0, transferCount: 0, entryCount: data.entries.length,
    },
    reportedCash: t.closing,
  })

  return {
    title,
    filename,
    orientation: "landscape",
    summaryCards: [
      { label: "Opening", value: fmtMoney(t.opening), note: "Start of period" },
      { label: "Money in", value: fmtMoney(t.moneyIn), accent: "green" },
      { label: "Money out", value: fmtMoney(t.moneyOut), accent: "rose" },
      { label: "Closing", value: fmtMoney(t.closing), accent: "indigo", note: "End of period" },
      {
        label: "Accounts needing attention",
        value: `${data.rows.filter((r) => r.needsAttention).length}`,
        note: "As of today, not of the period",
      },
    ],
    columns: [
      { header: "Account" }, { header: "Type" },
      { header: "Opening", align: "right" }, { header: "In", align: "right" },
      { header: "Out", align: "right" }, { header: "Closing", align: "right" },
      { header: "Share", align: "right" }, { header: "Status (as of today)" },
    ],
    rows: data.rows.map((r) => [
      r.isActive ? r.accountName : `${r.accountName} (inactive)`,
      r.accountType ?? "—",
      fmtMoney(r.openingBalance),
      r.periodIn ? fmtMoney(r.periodIn) : "—",
      r.periodOut ? fmtMoney(r.periodOut) : "—",
      fmtMoney(r.closingBalance),
      `${r.sharePercent.toFixed(1)}%`,
      accountStatusText(r, fmtMoney),
    ]),
    totalsRow: [
      "All accounts", "",
      fmtMoney(identity.openingTotal), fmtMoney(identity.moneyIn),
      fmtMoney(identity.moneyOut), fmtMoney(identity.reportedCash),
      "100.0%", identity.balances ? "" : "Totals do not balance",
    ],
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

export function CashAccountSections({
  data, fmtMoney, accountHref, reconcileHref, cashFlowHref,
}: {
  data: CashAccountReportData
  fmtMoney: (n: number) => string
  accountHref: (accountId: number) => string
  reconcileHref: string
  cashFlowHref: string
}) {
  const [accountFilter, setAccountFilter] = useState("ALL")
  const t = periodTotals(data.rows)
  const identity = cashIdentity({
    openingTotal: t.opening,
    totals: {
      moneyIn: t.moneyIn, moneyOut: t.moneyOut, net: t.moneyIn - t.moneyOut,
      transferVolume: 0, transferCount: 0, entryCount: data.entries.length,
    },
    reportedCash: t.closing,
  })

  const selectedId = accountFilter === "ALL" ? null : Number(accountFilter)

  /**
   * A running balance across mixed accounts is meaningless — the rows belong to
   * different pots. So it is computed only when one account is selected, and it
   * starts from that account's own opening figure.
   */
  const ledger = useMemo(() => {
    const rows = selectedId == null
      ? data.entries
      : data.entries.filter((e) => e.accountId === selectedId)

    const asc = [...rows].sort((a, b) => {
      const d = (a.transactionDate ?? "").localeCompare(b.transactionDate ?? "")
      return d !== 0 ? d : a.id - b.id
    })

    if (selectedId == null) {
      return asc.reverse().map((e) => ({ ...e, running: null as number | null }))
    }

    let running = data.rows.find((r) => r.accountId === selectedId)?.openingBalance ?? 0
    const withRunning = asc.map((e) => {
      running = Math.round((running + (Number(e.amount) || 0)) * 100) / 100
      return { ...e, running: running as number | null }
    })
    return withRunning.reverse()
  }, [data.entries, data.rows, selectedId])

  const pg = usePagination(ledger)
  const transfers = useMemo(
    () => summariseTransfers(data.transfers, { from: data.fromDate, to: data.toDate }),
    [data.transfers, data.fromDate, data.toDate],
  )

  return (
    <>
      {/* Said once, on every run. "My closing cash does not match Cash Flow" is
          alarming until you know the two are measured from different things. */}
      <p className="mb-3 rounded-md border border-slate-200 bg-slate-50 p-2 text-xs leading-snug text-slate-600">
        These figures come from the cash-account ledger — what each account holds.
        They are <b>not</b> expected to match{" "}
        <Link href={cashFlowHref} className="underline">Cash Flow</Link>, which is built from sales,
        expenses and capital and reads no account at all. Where the two disagree,{" "}
        <Link href={reconcileHref} className="underline">reconciliation</Link> is the answer.
      </p>

      {/* ---- 1. Accounts --------------------------------------------------- */}
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">
        Where the money sits
      </h2>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Account</TableHead>
              <TableHead>Type</TableHead>
              <TableHead className="text-right">Opening</TableHead>
              <TableHead className="text-right">In</TableHead>
              <TableHead className="text-right">Out</TableHead>
              <TableHead className="text-right">Closing</TableHead>
              <TableHead className="text-right">Share</TableHead>
              {/* The status feed has no date parameter, so these describe TODAY
                  whatever period was asked for. Labelled, not quietly re-dated. */}
              <TableHead>Status <span className="font-normal text-slate-400">(as of today)</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={8} className="text-slate-500 text-center p-4">
                  No cash accounts yet.
                </TableCell>
              </TableRow>
            ) : data.rows.map((r) => (
              <TableRow key={r.accountId} className={cn(!r.isActive && "text-slate-500")}>
                <TableCell className="font-medium">
                  <Link href={accountHref(r.accountId)} className="hover:underline">
                    {r.accountName}
                  </Link>
                  {!r.isActive && (
                    <Badge variant="outline" className="ml-2 border-0 bg-slate-100 text-slate-600">
                      inactive
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-slate-600">{r.accountType ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(r.openingBalance)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-emerald-700">
                  {r.periodIn ? fmtMoney(r.periodIn) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-rose-700">
                  {r.periodOut ? fmtMoney(r.periodOut) : "—"}
                </TableCell>
                <TableCell className={cn(
                  "text-right tabular-nums whitespace-nowrap font-medium",
                  r.closingBalance < 0 && "text-rose-700",
                )}>
                  {fmtMoney(r.closingBalance)}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-slate-500">
                  {r.sharePercent.toFixed(1)}%
                </TableCell>
                <TableCell className={cn("text-xs", r.needsAttention ? "text-amber-800" : "text-slate-500")}>
                  {accountStatusText(r, fmtMoney)}
                  {(r.unclearedCount ?? 0) > 0 && (
                    <span className="ml-1.5 text-slate-400">
                      · {r.unclearedCount} uncleared
                    </span>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      {/* The arithmetic, printed. Self-checking: over an all-time range it must
          close, and saying so is what makes the row above defensible. */}
      <div className="mt-2 rounded-lg border border-slate-200 bg-white px-3 py-2">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs tabular-nums text-slate-600">
          <span>Opening <b className="text-slate-900">{fmtMoney(identity.openingTotal)}</b></span>
          <span className="text-emerald-700">+ in <b>{fmtMoney(identity.moneyIn)}</b></span>
          <span className="text-rose-700">− out <b>{fmtMoney(identity.moneyOut)}</b></span>
          <span>= closing <b className="text-slate-900">{fmtMoney(identity.reportedCash)}</b></span>
          {!identity.balances && (
            <span className="text-rose-700">
              — off by <b>{fmtMoney(Math.abs(identity.discrepancy))}</b>
            </span>
          )}
        </div>
      </div>

      {/* ---- 2. Ledger ----------------------------------------------------- */}
      <div className="mt-6 mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600">
          Ledger
        </h2>
        <Select value={accountFilter} onValueChange={setAccountFilter}>
          <SelectTrigger className="h-9 w-[16rem]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All accounts</SelectItem>
            {data.rows.map((r) => (
              <SelectItem key={r.accountId} value={String(r.accountId)}>
                {r.accountName}{r.isActive ? "" : " (inactive)"}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Source</TableHead>
              <TableHead>Description</TableHead>
              <TableHead className="text-right">In</TableHead>
              <TableHead className="text-right">Out</TableHead>
              <TableHead className="text-right">Balance</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {ledger.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="text-slate-500 text-center p-4">
                  Nothing moved through {selectedId == null ? "any account" : "this account"} in this period.
                </TableCell>
              </TableRow>
            ) : pg.pageItems.map((e) => (
              <TableRow key={e.id}>
                <TableCell className="whitespace-nowrap">{(e.transactionDate ?? "").slice(0, 10)}</TableCell>
                <TableCell className="text-slate-600">{e.accountName ?? "—"}</TableCell>
                <TableCell>{categoryLabel(e.sourceType)}</TableCell>
                <TableCell className="max-w-[260px] truncate" title={e.description ?? ""}>
                  {e.description ?? "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-emerald-700">
                  {e.amount > 0 ? fmtMoney(e.amount) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-rose-700">
                  {e.amount < 0 ? fmtMoney(-e.amount) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap font-medium">
                  {e.running == null
                    ? <span className="text-slate-300" title="Pick one account to see a running balance">—</span>
                    : fmtMoney(e.running)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />

      {/* ---- 3. Transfers -------------------------------------------------- */}
      {/* Their own section because Cash Flow excludes them by design, so they are
          invisible in every other report — yet a transfer is exactly what
          explains why one account fell and another rose by the same amount. */}
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-6 mb-2">
        Transfers between your own accounts
      </h2>
      <p className="mb-2 text-xs text-slate-500">
        {transfers.approvedCount} approved moving {fmtMoney(transfers.approvedVolume)}
        {transfers.pendingCount > 0 && `, ${transfers.pendingCount} still pending`}. These are not
        income or spending — the money never left the business — so they are excluded from Cash Flow.
      </p>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>From</TableHead>
              <TableHead>To</TableHead>
              <TableHead className="text-right">Amount</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {transfers.rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="text-slate-500 text-center p-4">
                  No transfers in this period.
                </TableCell>
              </TableRow>
            ) : transfers.rows.map((t) => (
              <TableRow key={t.id}>
                <TableCell className="whitespace-nowrap">{(t.transferDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{t.fromAccountName ?? "—"}</TableCell>
                <TableCell>{t.toAccountName ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(Math.abs(t.amount))}</TableCell>
                <TableCell>
                  <Badge variant="outline" className={cn(
                    "border-0",
                    t.status === "Approved" ? "bg-emerald-100 text-emerald-700"
                    : t.status === "Draft" ? "bg-slate-100 text-slate-700"
                    : "bg-amber-100 text-amber-800",
                  )}>
                    {t.status}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </>
  )
}

"use client"

/**
 * Water Cash Account Report — where the money sits. Mirrors the poultry twin at
 * /poultry/reports/cash-accounts; the body is the same shared component.
 *
 * WHY THE PERIOD FIGURES ARE COMPUTED HERE
 * ----------------------------------------
 * spwatercashreconciliation_getaccountstatus takes no date parameters
 * (222_WaterCashReconciliation.postgres.sql:840) — its ledgerbalance is
 * all-time, and no per-account period opening/in/out exists anywhere on either
 * rail. So the ledger is read once for EVERYTHING up to the period end and
 * split at the period start by cashAccountsForPeriod. One request, not two:
 * the rows before the period and the rows inside it are the same fetch.
 *
 * The drift and reconciliation columns still describe TODAY, because the feed
 * they come from has no notion of a period. The table says so rather than
 * letting "Never reconciled" read as a claim about August.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { ReportShell } from "@/components/reports/report-shell"
import {
  CashAccountSections, CashAccountTiles, buildCashAccountPdf,
  type CashAccountReportData,
} from "@/components/reports/cash-account-report"
import {
  listWaterCashAccounts, getWaterCashAccountCountStatus,
  listWaterCashTransactions, listWaterCashTransfers,
} from "@/lib/api/water"
import {
  cashAccountsForPeriod, withinRange,
  type AccountStatusEntry, type LedgerEntry, type TransferEntry,
} from "@/lib/cash/cash-flow"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

const EMPTY: CashAccountReportData = {
  rows: [], entries: [], transfers: [], fromDate: "", toDate: "",
}

export default function WaterCashAccountReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT = defaultReportRange()
  const [fromDate, setFromDate] = useState(DEFAULT.from)
  const [toDate, setToDate] = useState(DEFAULT.to)
  const [data, setData] = useState<CashAccountReportData>(EMPTY)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setBusy(true); setError(null)
    // allSettled: a missing transfer list degrades one panel, it does not fail
    // the report. Only the account list and the ledger are load-bearing.
    const [accts, status, ledger, xfers] = await Promise.allSettled([
      listWaterCashAccounts(),
      getWaterCashAccountCountStatus(),
      // No fromDate on purpose — everything up to the period end, so the rows
      // before it can be summed into each account's opening balance.
      listWaterCashTransactions({ toDate }),
      listWaterCashTransfers(),
    ])

    if (accts.status === "rejected" && ledger.status === "rejected") {
      setError((accts.reason as any)?.message ?? String(accts.reason))
      setData({ ...EMPTY, fromDate, toDate })
      setBusy(false)
      return
    }

    const accounts = (accts.status === "fulfilled" ? accts.value ?? [] : []).map((a) => ({
      accountId: a.waterCashAccountId,
      accountName: a.accountName,
      accountType: a.accountType,
      isActive: a.isActive,
      openingBalance: Number(a.openingBalance) || 0,
    }))

    const statusRows: AccountStatusEntry[] =
      (status.status === "fulfilled" ? status.value ?? [] : []).map((s) => ({
        accountId: s.waterCashAccountId,
        accountName: s.accountName,
        accountType: s.accountType,
        isActive: s.isActive,
        currentBalance: Number(s.currentBalance) || 0,
        ledgerBalance: Number(s.ledgerBalance) || 0,
        cacheDrift: Number(s.cacheDrift) || 0,
        lastReconciledAt: s.lastReconciledAt ?? null,
        daysSinceReconciled: s.daysSinceReconciled ?? null,
        unclearedCount: Number(s.unclearedCount) || 0,
      }))

    const allEntries: LedgerEntry[] =
      (ledger.status === "fulfilled" ? ledger.value ?? [] : []).map((t) => ({
        id: t.waterCashTransactionId,
        accountId: t.waterCashAccountId,
        accountName: t.accountName ?? null,
        transactionDate: t.transactionDate,
        transactionType: t.transactionType ?? null,
        sourceType: t.sourceType ?? null,
        sourceId: t.sourceId ?? null,
        amount: Number(t.amount) || 0,
        description: t.description ?? null,
      }))

    const transfers: TransferEntry[] =
      (xfers.status === "fulfilled" ? xfers.value ?? [] : []).map((t) => ({
        id: t.waterCashTransferId,
        fromAccountName: t.fromAccountName ?? null,
        toAccountName: t.toAccountName ?? null,
        transferDate: t.transferDate,
        amount: Number(t.amount) || 0,
        status: t.status,
      }))

    setData({
      rows: cashAccountsForPeriod({ accounts, status: statusRows, entries: allEntries, fromDate, toDate }),
      // The detail table shows the PERIOD only; the earlier rows exist purely to
      // establish each account's opening figure.
      entries: allEntries.filter((e) => withinRange(e.transactionDate, fromDate, toDate)),
      transfers,
      fromDate,
      toDate,
    })
    setBusy(false)
  }, [fromDate, toDate])

  useEffect(() => { void load() }, [load])

  const pdf = useMemo(
    () => buildCashAccountPdf({
      data, fmtMoney,
      title: "Water Cash Account Report",
      filename: "water-cash-accounts",
    }),
    [data, fmtMoney],
  )

  return (
    <ReportShell
      title="Cash Account Report"
      description="Where your money sits, what moved through each account, and which accounts need attention."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      // The body is three tables, not the one `pdf` describes, so each
      // carries its own phone rendering inside <CashAccountSections>.
      mobileCards={false}
      pdf={pdf}
      summary={<CashAccountTiles data={data} fmtMoney={fmtMoney} />}
    >
      <CashAccountSections
        data={data}
        fmtMoney={fmtMoney}
        accountHref={(id) => `/water-cash-accounts/${id}`}
        reconcileHref="/water-cash-reconciliation"
        cashFlowHref="/water-cash-flow"
      />
    </ReportShell>
  )
}

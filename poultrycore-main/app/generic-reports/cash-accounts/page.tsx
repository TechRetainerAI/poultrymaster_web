"use client"

// Generic Cash Account Report — where the money sits.
//
// Uses the shared ReportShell + CashAccountSections components that are
// explicitly rail-agnostic. Maps generic API responses onto the structural
// types in lib/cash/cash-flow.

import { useCallback, useEffect, useMemo, useState } from "react"
import { ReportShell } from "@/components/reports/report-shell"
import {
  CashAccountSections, CashAccountTiles, buildCashAccountPdf,
  type CashAccountReportData,
} from "@/components/reports/cash-account-report"
import {
  getCashAccounts, listCashTransactions, getCashTransfers,
  type GenericCashAccount, type GenericCashTransaction, type GenericCashTransfer,
} from "@/lib/api/generic"
import {
  cashAccountsForPeriod, withinRange,
  type AccountStatusEntry, type LedgerEntry, type TransferEntry,
} from "@/lib/cash/cash-flow"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

const EMPTY: CashAccountReportData = {
  rows: [], entries: [], transfers: [], fromDate: "", toDate: "",
}

export default function GenericCashAccountReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT = defaultReportRange()
  const [fromDate, setFromDate] = useState(DEFAULT.from)
  const [toDate, setToDate] = useState(DEFAULT.to)
  const [data, setData] = useState<CashAccountReportData>(EMPTY)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setBusy(true); setError(null)
    const [accts, ledger, xfers] = await Promise.allSettled([
      getCashAccounts(),
      listCashTransactions(),
      getCashTransfers(),
    ])

    if (accts.status === "rejected" && ledger.status === "rejected") {
      setError((accts.reason as any)?.message ?? String(accts.reason))
      setData({ ...EMPTY, fromDate, toDate })
      setBusy(false)
      return
    }

    const accounts = (accts.status === "fulfilled" ? accts.value ?? [] : []).map((a) => ({
      accountId: a.genericCashAccountId,
      accountName: a.accountName,
      accountType: a.accountType ?? "Cash",
      isActive: a.isActive,
      openingBalance: Number(a.openingBalance) || 0,
    }))

    // Build status entries from accounts (generic doesn't have a separate count-status endpoint)
    const statusRows: AccountStatusEntry[] =
      (accts.status === "fulfilled" ? accts.value ?? [] : []).map((a) => ({
        accountId: a.genericCashAccountId,
        accountName: a.accountName,
        accountType: a.accountType ?? "Cash",
        isActive: a.isActive,
        currentBalance: Number(a.currentBalance) || 0,
        ledgerBalance: Number(a.currentBalance) || 0,
        cacheDrift: 0,
        lastReconciledAt: (a as any).lastReconciledAt ?? null,
        daysSinceReconciled: null,
        unclearedCount: 0,
      }))

    const allEntries: LedgerEntry[] =
      (ledger.status === "fulfilled" ? ledger.value ?? [] : []).map((t) => ({
        id: t.genericCashTransactionId,
        accountId: t.genericCashAccountId,
        accountName: t.accountName ?? null,
        transactionDate: t.transactionDate,
        transactionType: t.transactionType ?? null,
        sourceType: t.sourceType ?? null,
        sourceId: null,
        amount: Number(t.amount) || 0,
        description: t.description ?? null,
      }))

    const transfers: TransferEntry[] =
      (xfers.status === "fulfilled" ? xfers.value ?? [] : []).map((t) => ({
        id: t.genericCashTransferId,
        fromAccountName: t.fromAccountName ?? null,
        toAccountName: t.toAccountName ?? null,
        transferDate: t.transferDate,
        amount: Number(t.amount) || 0,
        status: t.status,
      }))

    setData({
      rows: cashAccountsForPeriod({ accounts, status: statusRows, entries: allEntries, fromDate, toDate }),
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
      title: "Cash Account Report",
      filename: "cash-accounts",
    }),
    [data, fmtMoney],
  )

  return (
    <ReportShell
      backHref="/generic-reports"
      title="Cash Account Report"
      description="Where your money sits, what moved through each account, and which accounts need attention."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      mobileCards={false}
      pdf={pdf}
      summary={<CashAccountTiles data={data} fmtMoney={fmtMoney} />}
    >
      <CashAccountSections
        data={data}
        fmtMoney={fmtMoney}
        accountHref={(id) => `/generic-cash/${id}`}
        reconcileHref="/generic-cash-reconciliation"
        cashFlowHref="/generic-cash-flow"
      />
    </ReportShell>
  )
}

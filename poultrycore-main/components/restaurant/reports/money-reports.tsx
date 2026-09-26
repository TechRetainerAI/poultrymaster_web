"use client"

/**
 * Restaurant cash & ledger reports (migrations 323 / 324).
 *
 * The restaurant equivalents of Poultry's and Water's money reports — Cash Flow
 * Detail, Cash Movement, Cash Account Report, Money Movement, Closing Report —
 * plus three the restaurant needs that they lack: Till & Count Variances,
 * Takings by Account and Profit vs Cash.
 *
 * Every one reads the ONE cash ledger (restaurantcashtransactions) or the Cash
 * Flow built on it, so they cannot disagree with each other, with the account
 * balances, or with the Cash Flow page. Transfers, till floats and drops move
 * money between the restaurant's own accounts: they appear on account-level
 * reports and never as money in or out of the business.
 *
 * Each definition plugs into the shared report shell, so every one gets the
 * date presets, PDF preview, CSV and email for free.
 */

import type { ReactNode } from "react"
import { Bar, BarChart, CartesianGrid, Cell, Legend, Line, ComposedChart, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { ToneBadge } from "@/components/reports/report-table"
import type { Fmt, ReportDefinition } from "@/components/reports/report-table"
import { CashAnalysisPanel, CashBreakdownPanel } from "@/components/reports/cash-report-sections"
import { getCashFlow, flowGroupLabel, type CashFlowResponse, type CashFlowRow } from "@/lib/api/cash-flow"
import { cashFlowBuckets, categoryLabel, withRunningBalance } from "@/lib/cash/cash-flow"
import { buildCashFlowAnalysis } from "@/lib/cash/cash-flow-analysis"
import {
  getLedgerPeriod, getLedgerRows, getProfitVsCash, getTakingsByAccount,
  listAllLoanPayments, listClosings, listCounts, listLoans, listOwnerMoney, listShifts, listTransfers,
  ledgerSourceLabel, ACCOUNT_TYPE_LABELS,
  type CashBridgeLine, type CashTransfer, type DailyClosing, type LedgerPeriodRow, type LedgerRowAll,
  type LoanPayment, type OwnerMoneyEntry, type RestaurantLoan, type TakingsByAccountRow,
} from "@/lib/api/restaurant-finance"
import {
  getPayrollReport, getStaffLoanStaffReport, type PayrollReportRow, type StaffLoanStaffRow,
} from "@/lib/api/restaurant-payroll"

const IN_GREEN = "#059669"
const OUT_ROSE = "#e11d48"
const NET_SLATE = "#334155"
const PIE_COLORS = ["#e11d48", "#0ea5e9", "#10b981", "#f59e0b", "#8b5cf6", "#64748b", "#ec4899", "#14b8a6"]

const d10 = (s?: string | null) => (s ?? "").slice(0, 10)
const inRange = (s: string | null | undefined, from: string, to: string) => { const d = d10(s); return d >= from && d <= to }
const sum = <T,>(rows: T[], f: (r: T) => number) => rows.reduce((t, r) => t + (Number(f(r)) || 0), 0)

function card(title: string, hint: string, body: ReactNode) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{title}</CardTitle>
        <CardDescription>{hint}</CardDescription>
      </CardHeader>
      <CardContent>{body}</CardContent>
    </Card>
  )
}

/** Same length period immediately before [from, to]. */
function previousPeriod(from: string, to: string) {
  const f = new Date(`${from}T00:00:00`), t = new Date(`${to}T00:00:00`)
  const days = Math.max(1, Math.round((t.getTime() - f.getTime()) / 86_400_000) + 1)
  const pt = new Date(f.getTime() - 86_400_000)
  const pf = new Date(pt.getTime() - (days - 1) * 86_400_000)
  const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
  return { from: iso(pf), to: iso(pt), days }
}

/** Money in / out / net per day, oldest first, with the closing cash of each day. */
function byDay(rows: CashFlowRow[], opening: number) {
  const map = new Map<string, { date: string; moneyIn: number; moneyOut: number }>()
  for (const r of rows) {
    const d = d10(r.transactionDate)
    const e = map.get(d) ?? { date: d, moneyIn: 0, moneyOut: 0 }
    if (r.amount > 0) e.moneyIn += r.amount; else e.moneyOut += -r.amount
    map.set(d, e)
  }
  let running = opening
  return [...map.values()].sort((a, b) => a.date.localeCompare(b.date)).map((e) => {
    running += e.moneyIn - e.moneyOut
    return { ...e, net: e.moneyIn - e.moneyOut, closing: Math.round(running * 100) / 100 }
  })
}

// ===========================================================================
// Cash Flow Detail — every movement, with the analysis and breakdowns
// ===========================================================================

type FlowRow = CashFlowRow & { running: number }
interface FlowMeta { cur: CashFlowResponse; prev: CashFlowResponse; days: number }

export const cashFlowDetail: ReportDefinition<FlowRow, FlowMeta> = {
  load: async (r) => {
    const p = previousPeriod(r.from, r.to)
    const [cur, prev] = await Promise.all([
      getCashFlow("Restaurant", { fromDate: r.from, toDate: r.to }),
      getCashFlow("Restaurant", { fromDate: p.from, toDate: p.to }),
    ])
    const rows = withRunningBalance(cur.rows, cur.summary.openingCash)
    return { rows, meta: { cur, prev, days: p.days } }
  },
  summary: (r, f) => {
    const s = r.meta?.cur.summary
    if (!s) return []
    return [
      { label: "Opening cash", value: f.money(s.openingCash) },
      { label: "Money in", value: f.money(s.moneyIn) },
      { label: "Money out", value: f.money(s.moneyOut) },
      { label: "Closing cash", value: f.money(s.closingCash) },
      { label: "From trading (in − out)", value: f.money(s.operatingIn - s.operatingOut) },
      { label: "Loans & owner money (net)", value: f.money(s.financingIn - s.financingOut) },
    ]
  },
  panel: (r, f) => {
    const m = r.meta
    if (!m) return null
    const s = m.cur.summary
    const inB = cashFlowBuckets(m.cur.rows, "in")
    const outB = cashFlowBuckets(m.cur.rows, "out")
    const analysis = buildCashFlowAnalysis({
      moneyIn: s.moneyIn, moneyOut: s.moneyOut, netCashFlow: s.netCashFlow,
      operatingIn: s.operatingIn, operatingOut: s.operatingOut, financingIn: s.financingIn, financingOut: s.financingOut,
      cashAtHand: s.closingCash, offLedgerIn: 0, offLedgerOut: 0, transferVolume: s.transferVolume ?? 0,
      movementCount: s.movementCount, daysInPeriod: m.days,
      previousMoneyIn: m.prev.summary.moneyIn, previousMoneyOut: m.prev.summary.moneyOut,
      previousNetCashFlow: m.prev.summary.netCashFlow,
      moneyInByCategory: inB.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
      moneyOutByCategory: outB.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
    }, (n) => f.money(n))
    const days = byDay(m.cur.rows, s.openingCash)
    return (
      <div className="space-y-4">
        {days.length > 0 && card("Cash by day", "Money in and out each day, and the cash held at the end of it.",
          <ResponsiveContainer width="100%" height={260}>
            <ComposedChart data={days}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} tickFormatter={(d) => d.slice(5)} />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip formatter={(v: number) => f.money(v)} />
              <Legend />
              <Bar dataKey="moneyIn" name="Money in" fill={IN_GREEN} />
              <Bar dataKey="moneyOut" name="Money out" fill={OUT_ROSE} />
              <Line dataKey="closing" name="Cash held" stroke={NET_SLATE} strokeWidth={2} dot={false} />
            </ComposedChart>
          </ResponsiveContainer>)}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <CashBreakdownPanel title="Money in by source" total={f.money(s.moneyIn)} accent="green"
            items={inB.map((b) => ({ key: b.key, label: b.label, value: f.money(b.amount), percent: b.percent }))}
            emptyText="Nothing came in." />
          <CashBreakdownPanel title="Money out by category" total={f.money(s.moneyOut)} accent="rose"
            items={outB.map((b) => ({ key: b.key, label: b.label, value: f.money(b.amount), percent: b.percent }))}
            emptyText="Nothing went out." />
        </div>
        <CashAnalysisPanel title={`Analysis (compared with the previous ${m.days} day${m.days === 1 ? "" : "s"})`} items={analysis} />
      </div>
    )
  },
  columns: [
    { key: "date", label: "Date", value: (r) => d10(r.transactionDate) },
    { key: "type", label: "Type", value: (r) => flowGroupLabel(r.flowGroup), secondary: true },
    { key: "cat", label: "Category", value: (r) => categoryLabel(r.category) },
    { key: "acct", label: "Account", value: (r) => r.accountName ?? "—", secondary: true },
    { key: "desc", label: "Description", value: (r) => r.description ?? "", secondary: true },
    { key: "in", label: "In", value: (r, f) => (r.amount > 0 ? f.money(r.amount) : ""), numeric: true },
    { key: "out", label: "Out", value: (r, f) => (r.amount < 0 ? f.money(-r.amount) : ""), numeric: true },
    { key: "run", label: "Running cash", value: (r, f) => f.money(r.running), numeric: true },
  ],
  tableTitle: "Every movement",
  tableHint: "Transfers between your own accounts are left out — they move money, they do not bring it in or send it out.",
  emptyText: "No money moved in this period.",
}

// ===========================================================================
// Cash Movement — the day-by-day summary
// ===========================================================================

type DayRow = ReturnType<typeof byDay>[number]

export const cashMovement: ReportDefinition<DayRow, CashFlowResponse> = {
  load: async (r) => {
    const cur = await getCashFlow("Restaurant", { fromDate: r.from, toDate: r.to })
    return { rows: byDay(cur.rows, cur.summary.openingCash), meta: cur }
  },
  summary: (r, f) => {
    const s = r.meta?.summary
    if (!s) return []
    return [
      { label: "Opening cash", value: f.money(s.openingCash) },
      { label: "Money in", value: f.money(s.moneyIn) },
      { label: "Money out", value: f.money(s.moneyOut) },
      { label: "Net movement", value: f.money(s.netCashFlow) },
      { label: "Closing cash (= all account balances)", value: f.money(s.closingCash) },
    ]
  },
  panel: (r, f) => r.rows.length === 0 ? null : card("Net movement by day", "Green days added cash; red days used it.",
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={r.rows}>
        <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
        <XAxis dataKey="date" tick={{ fontSize: 11 }} tickFormatter={(d) => d.slice(5)} />
        <YAxis tick={{ fontSize: 11 }} />
        <Tooltip formatter={(v: number) => f.money(v)} />
        <Bar dataKey="net" name="Net">
          {r.rows.map((d) => <Cell key={d.date} fill={d.net >= 0 ? IN_GREEN : OUT_ROSE} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>),
  columns: [
    { key: "date", label: "Date", value: (r) => r.date },
    { key: "in", label: "Money in", value: (r, f) => f.money(r.moneyIn), numeric: true },
    { key: "out", label: "Money out", value: (r, f) => f.money(r.moneyOut), numeric: true },
    { key: "net", label: "Net", value: (r, f) => f.money(r.net), numeric: true,
      render: (r, f) => <span className={r.net < 0 ? "text-red-600" : "text-emerald-700"}>{f.money(r.net)}</span> },
    { key: "close", label: "Cash at end of day", value: (r, f) => f.money(r.closing), numeric: true },
  ],
  tableTitle: "Day by day",
  emptyText: "No money moved in this period.",
}

// ===========================================================================
// Cash Account Report — where the money sits
// ===========================================================================

interface AccountsMeta { accounts: LedgerPeriodRow[]; transfers: CashTransfer[] }

function accountStatus(a: LedgerPeriodRow): { text: string; tone: "good" | "warn" | "bad" | "muted" } {
  if (Math.abs(a.currentBalance - a.ledgerBalance) > 0.005) return { text: "Out of sync", tone: "bad" }
  if (a.closingBalance < 0) return { text: "Below zero", tone: "bad" }
  if (a.accountType === "Till") return { text: "Counted at shift close", tone: "muted" }
  if (!a.lastCountedAt) return { text: "Never counted", tone: "warn" }
  const days = Math.floor((Date.now() - new Date(a.lastCountedAt).getTime()) / 86_400_000)
  return days > 30 ? { text: `Counted ${days} days ago`, tone: "warn" } : { text: "Counted recently", tone: "good" }
}

export const cashAccounts: ReportDefinition<LedgerRowAll, AccountsMeta> = {
  load: async (r) => {
    const [accounts, rows, transfers] = await Promise.all([
      getLedgerPeriod(r.from, r.to), getLedgerRows(r.from, r.to), listTransfers(r.from, r.to),
    ])
    return { rows, meta: { accounts: accounts.filter((a) => a.isActive || a.txnCount > 0 || a.closingBalance !== 0), transfers } }
  },
  summary: (r, f) => {
    const a = r.meta?.accounts ?? []
    return [
      { label: "Opening (all accounts)", value: f.money(sum(a, (x) => x.openingBalance)) },
      { label: "Money in", value: f.money(sum(a, (x) => x.moneyIn)) },
      { label: "Money out", value: f.money(sum(a, (x) => x.moneyOut)) },
      { label: "Closing (all accounts)", value: f.money(sum(a, (x) => x.closingBalance)) },
      { label: "Moved between accounts", value: f.money(sum(a, (x) => x.transfersOut)) },
      { label: "Accounts needing attention", value: String(a.filter((x) => ["bad", "warn"].includes(accountStatus(x).tone)).length) },
    ]
  },
  panel: (r, f) => {
    const a = r.meta?.accounts ?? []
    const t = r.meta?.transfers ?? []
    const open = sum(a, (x) => x.openingBalance), inn = sum(a, (x) => x.moneyIn), out = sum(a, (x) => x.moneyOut)
    const tin = sum(a, (x) => x.transfersIn), tout = sum(a, (x) => x.transfersOut), close = sum(a, (x) => x.closingBalance)
    const off = Math.round((open + inn - out + tin - tout - close) * 100) / 100
    return (
      <div className="space-y-4">
        {card("Where the money sits", "Each account's opening, movements and closing for the period. Status is as of today.",
          <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[820px]">
              <thead className="bg-slate-50 border-b"><tr>
                {["Account", "Type", "Opening", "In", "Out", "Transfers in", "Transfers out", "Closing", "Share", "Status"].map((h, i) =>
                  <th key={h} className={`p-2 ${i >= 2 && i <= 8 ? "text-right" : "text-left"}`}>{h}</th>)}
              </tr></thead>
              <tbody>
                {a.map((x) => {
                  const st = accountStatus(x)
                  return (
                    <tr key={x.cashAccountId} className="border-b">
                      <td className="p-2 font-medium">{x.name}{!x.isActive && <span className="ml-1 text-xs text-slate-400">(inactive)</span>}</td>
                      <td className="p-2 text-xs">{ACCOUNT_TYPE_LABELS[x.accountType] ?? x.accountType}</td>
                      <td className="p-2 text-right tabular-nums">{f.money(x.openingBalance)}</td>
                      <td className="p-2 text-right tabular-nums text-emerald-700">{f.money(x.moneyIn)}</td>
                      <td className="p-2 text-right tabular-nums text-rose-700">{f.money(x.moneyOut)}</td>
                      <td className="p-2 text-right tabular-nums">{f.money(x.transfersIn)}</td>
                      <td className="p-2 text-right tabular-nums">{f.money(x.transfersOut)}</td>
                      <td className={`p-2 text-right tabular-nums font-semibold ${x.closingBalance < 0 ? "text-red-600" : ""}`}>{f.money(x.closingBalance)}</td>
                      <td className="p-2 text-right tabular-nums text-xs">{close !== 0 ? f.pct((x.closingBalance / close) * 100) : "—"}</td>
                      <td className="p-2"><ToneBadge text={st.text} tone={st.tone} /></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
            <p className={`mt-2 text-xs ${off === 0 ? "text-slate-500" : "text-red-700"}`}>
              Check: {f.money(open)} opening + {f.money(inn)} in − {f.money(out)} out + {f.money(tin)} transfers in − {f.money(tout)} transfers out
              = {f.money(close)} closing{off !== 0 ? ` — off by ${f.money(off)}` : " ✓"}
            </p>
          </div>)}
        {card("Transfers", "Money moved between your own accounts in the period.",
          t.length === 0 ? <p className="text-sm text-slate-500">No transfers in this period.</p> :
          <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[560px]">
              <thead className="bg-slate-50 border-b"><tr>{["Date", "Number", "From", "To", "Amount", "Status"].map((h) =>
                <th key={h} className={`p-2 ${h === "Amount" ? "text-right" : "text-left"}`}>{h}</th>)}</tr></thead>
              <tbody>{t.map((x) => (
                <tr key={x.transferId} className={`border-b ${x.status === "Reversed" ? "text-slate-400 line-through" : ""}`}>
                  <td className="p-2">{d10(x.transferDate)}</td><td className="p-2">{x.transferNumber}</td>
                  <td className="p-2">{x.fromAccountName}</td><td className="p-2">{x.toAccountName}</td>
                  <td className="p-2 text-right tabular-nums">{f.money(x.amount)}</td><td className="p-2">{x.status}</td>
                </tr>))}</tbody>
            </table>
          </div>)}
      </div>
    )
  },
  columns: [
    { key: "date", label: "Date", value: (r) => d10(r.txnDate) },
    { key: "acct", label: "Account", value: (r) => r.accountName },
    { key: "what", label: "What", value: (r) => ledgerSourceLabel(r.sourceType) + (r.isInternal ? " (internal)" : "") },
    { key: "desc", label: "Description", value: (r) => r.description ?? "", secondary: true },
    { key: "in", label: "In", value: (r, f) => (r.amount > 0 ? f.money(r.amount) : ""), numeric: true },
    { key: "out", label: "Out", value: (r, f) => (r.amount < 0 ? f.money(-r.amount) : ""), numeric: true },
    { key: "bal", label: "Account balance", value: (r, f) => f.money(r.runningBalance), numeric: true },
  ],
  tableTitle: "Ledger — every account",
  tableHint: "Account balance is that account's balance after the row. Internal rows are transfers, till floats and drops.",
  emptyText: "No ledger rows in this period.",
}

// ===========================================================================
// Money Movement — transfers, owner money, loans and repayments
// ===========================================================================

interface MovementRow {
  date: string; kind: string; number: string; detail: string; account: string
  moneyIn: number; moneyOut: number; status: string
}
interface MovementMeta {
  transfers: CashTransfer[]; owner: OwnerMoneyEntry[]; loans: RestaurantLoan[]; repayments: LoanPayment[]
}

export const moneyMovement: ReportDefinition<MovementRow, MovementMeta> = {
  load: async (r) => {
    const [transfers, owner, loans, allRepay] = await Promise.all([
      listTransfers(r.from, r.to), listOwnerMoney(r.from, r.to), listLoans(), listAllLoanPayments(),
    ])
    const repayments = allRepay.filter((p) => inRange(p.paymentDate, r.from, r.to))
    const loansInPeriod = loans.filter((l) => inRange(l.loanDate, r.from, r.to))
    const rows: MovementRow[] = [
      ...transfers.map((t) => ({ date: d10(t.transferDate), kind: "Transfer", number: t.transferNumber ?? "",
        detail: `${t.fromAccountName} → ${t.toAccountName}`, account: "", moneyIn: 0, moneyOut: 0, status: t.status })),
      ...owner.map((o) => ({ date: d10(o.entryDate), kind: o.entryType === "Contribution" ? "Owner contribution" : "Owner drawing",
        number: o.entryNumber ?? "", detail: o.ownerName ?? "", account: o.accountName,
        moneyIn: o.entryType === "Contribution" ? o.amount : 0, moneyOut: o.entryType === "Draw" ? o.amount : 0, status: o.status })),
      ...loansInPeriod.map((l) => ({ date: d10(l.loanDate), kind: "Loan received", number: l.loanNumber ?? "",
        detail: `${l.lenderName} — borrowed ${l.principal.toFixed(2)}`, account: l.receivedAccountName ?? "",
        moneyIn: l.status === "Cancelled" ? 0 : l.amountReceived, moneyOut: 0, status: l.status })),
      ...repayments.map((p) => ({ date: d10(p.paymentDate), kind: "Loan repayment", number: p.loanNumber ?? "",
        detail: `${p.lenderName ?? ""} — principal ${p.principalAmount.toFixed(2)}, interest ${p.interestAmount.toFixed(2)}, fees ${p.feeAmount.toFixed(2)}`,
        account: p.accountName, moneyIn: 0, moneyOut: p.status === "Posted" ? p.totalAmount : 0, status: p.status })),
    ].sort((a, b) => b.date.localeCompare(a.date))
    return { rows, meta: { transfers, owner, loans, repayments } }
  },
  summary: (r, f) => {
    const m = r.meta
    if (!m) return []
    const live = <T extends { status: string }>(x: T[]) => x.filter((y) => y.status === "Posted")
    const put = sum(live(m.owner).filter((o) => o.entryType === "Contribution"), (o) => o.amount)
    const took = sum(live(m.owner).filter((o) => o.entryType === "Draw"), (o) => o.amount)
    const rp = live(m.repayments)
    return [
      { label: "Moved between accounts", value: f.money(sum(live(m.transfers), (t) => t.amount)) },
      { label: "Owner put in / took out", value: `${f.money(put)} / ${f.money(took)}` },
      { label: "Still owed on loans", value: f.money(sum(m.loans.filter((l) => l.status === "Active"), (l) => l.outstandingPrincipal)) },
      { label: "Principal repaid", value: f.money(sum(rp, (p) => p.principalAmount)) },
      { label: "Cost of borrowing (interest + fees)", value: f.money(sum(rp, (p) => p.interestAmount + p.feeAmount)) },
    ]
  },
  panel: (r, f) => {
    const loans = (r.meta?.loans ?? []).filter((l) => l.status !== "Cancelled")
    if (loans.length === 0) return null
    return card("Loans", "Every loan not cancelled, with what is still owed today.",
      <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[720px]">
          <thead className="bg-slate-50 border-b"><tr>{["Loan", "Lender", "Borrowed", "Received", "Repaid", "Still owed", "Interest + fees", "Status"].map((h, i) =>
            <th key={h} className={`p-2 ${i >= 2 && i <= 6 ? "text-right" : "text-left"}`}>{h}</th>)}</tr></thead>
          <tbody>{loans.map((l) => (
            <tr key={l.loanId} className="border-b">
              <td className="p-2">{l.loanNumber}</td><td className="p-2">{l.lenderName}</td>
              <td className="p-2 text-right tabular-nums">{f.money(l.principal)}</td>
              <td className="p-2 text-right tabular-nums">{f.money(l.amountReceived)}</td>
              <td className="p-2 text-right tabular-nums">{f.money(l.principalRepaid)}</td>
              <td className="p-2 text-right tabular-nums font-semibold">{f.money(l.outstandingPrincipal)}</td>
              <td className="p-2 text-right tabular-nums">{f.money(l.interestPaid + l.feesPaid)}</td>
              <td className="p-2"><ToneBadge text={l.isOverdue ? "Overdue" : l.status} tone={l.isOverdue ? "bad" : l.status === "PaidOff" ? "good" : "muted"} /></td>
            </tr>))}</tbody>
        </table>
      </div>)
  },
  columns: [
    { key: "date", label: "Date", value: (r) => r.date },
    { key: "kind", label: "Movement", value: (r) => r.kind },
    { key: "num", label: "Number", value: (r) => r.number, secondary: true },
    { key: "detail", label: "Detail", value: (r) => r.detail, secondary: true },
    { key: "acct", label: "Account", value: (r) => r.account, secondary: true },
    { key: "in", label: "In", value: (r, f) => (r.moneyIn ? f.money(r.moneyIn) : ""), numeric: true },
    { key: "out", label: "Out", value: (r, f) => (r.moneyOut ? f.money(r.moneyOut) : ""), numeric: true },
    { key: "status", label: "Status", value: (r) => r.status,
      render: (r) => <ToneBadge text={r.status} tone={r.status === "Reversed" || r.status === "Cancelled" ? "muted" : "good"} /> },
  ],
  tableTitle: "Transfers, owner money and loans",
  tableHint: "Transfers show no in/out: they move money between your own accounts. Reversed rows carry no amount.",
  emptyText: "No transfers, owner money or loan activity in this period.",
}

// ===========================================================================
// Till & Count Variances — reconciliation history
// ===========================================================================

interface VarianceRow {
  date: string; kind: string; account: string; reference: string
  expected: number; counted: number; difference: number; by: string; note: string
}

export const tillVariances: ReportDefinition<VarianceRow> = {
  load: async (r) => {
    const [shifts, counts] = await Promise.all([listShifts("Closed", r.from, r.to), listCounts()])
    const rows: VarianceRow[] = [
      ...shifts.map((s) => ({ date: d10(s.closedAt ?? s.openedAt), kind: "Till shift", account: s.tillName,
        reference: s.shiftNumber ?? "", expected: s.expectedCash ?? 0, counted: s.countedCash ?? 0,
        difference: s.variance ?? 0, by: s.closedBy ?? "", note: s.closeNotes ?? "" })),
      ...counts.filter((c) => inRange(c.countDate, r.from, r.to) && c.status === "Posted").map((c) => ({
        date: d10(c.countDate), kind: "Account count", account: c.accountName, reference: `Count #${c.countId}`,
        expected: c.systemBalance, counted: c.countedBalance, difference: c.difference, by: c.createdBy ?? "", note: c.notes ?? "" })),
    ].sort((a, b) => b.date.localeCompare(a.date))
    return { rows }
  },
  summary: (r, f) => [
    { label: "Short (total)", value: f.money(-sum(r.rows.filter((x) => x.difference < 0), (x) => x.difference)) },
    { label: "Over (total)", value: f.money(sum(r.rows.filter((x) => x.difference > 0), (x) => x.difference)) },
    { label: "Net over / short", value: f.money(sum(r.rows, (x) => x.difference)) },
    { label: "Counts that balanced", value: `${r.rows.filter((x) => x.difference === 0).length} of ${r.rows.length}` },
  ],
  columns: [
    { key: "date", label: "Date", value: (r) => r.date },
    { key: "kind", label: "Type", value: (r) => r.kind, secondary: true },
    { key: "acct", label: "Till / account", value: (r) => r.account },
    { key: "ref", label: "Reference", value: (r) => r.reference, secondary: true },
    { key: "exp", label: "Expected", value: (r, f) => f.money(r.expected), numeric: true },
    { key: "cnt", label: "Counted", value: (r, f) => f.money(r.counted), numeric: true },
    { key: "diff", label: "Over / short", value: (r, f) => f.money(r.difference), numeric: true,
      render: (r, f) => <span className={r.difference < 0 ? "text-red-600 font-semibold" : r.difference > 0 ? "text-amber-600 font-semibold" : "text-emerald-700"}>{f.money(r.difference)}</span> },
    { key: "by", label: "By", value: (r) => r.by, secondary: true },
    { key: "note", label: "Note", value: (r) => r.note, secondary: true },
  ],
  tableTitle: "Every cash-up and count",
  tableHint: "Differences were posted to the ledger at the time, so they are already in Cash Flow and the P&L (as Cash over / short).",
  emptyText: "No shifts were closed and no accounts counted in this period.",
}

// ===========================================================================
// Closing Report — one row per closed day
// ===========================================================================

export const closingReport: ReportDefinition<DailyClosing> = {
  load: async (r) => ({ rows: await listClosings(366, r.from, r.to) }),
  summary: (r, f) => {
    const closed = r.rows.filter((x) => x.status === "Closed")
    return [
      { label: "Days closed", value: `${closed.length}${r.rows.length > closed.length ? ` (${r.rows.length - closed.length} reopened)` : ""}` },
      { label: "Net sales", value: f.money(sum(closed, (x) => x.netSales)) },
      { label: "Money in / out", value: `${f.money(sum(closed, (x) => x.moneyIn))} / ${f.money(sum(closed, (x) => x.moneyOut))}` },
      { label: "Cash over / short", value: f.money(sum(closed, (x) => x.cashVariance)) },
    ]
  },
  columns: [
    { key: "date", label: "Day", value: (r) => d10(r.closingDate) },
    { key: "status", label: "Status", value: (r) => r.status,
      render: (r) => <ToneBadge text={r.status} tone={r.status === "Closed" ? "good" : "warn"} /> },
    { key: "orders", label: "Orders", value: (r, f) => f.int(r.orderCount), numeric: true, secondary: true },
    { key: "sales", label: "Net sales", value: (r, f) => f.money(r.netSales), numeric: true },
    { key: "tax", label: "Tax", value: (r, f) => f.money(r.taxCollected), numeric: true, secondary: true },
    { key: "in", label: "Money in", value: (r, f) => f.money(r.moneyIn), numeric: true },
    { key: "out", label: "Money out", value: (r, f) => f.money(r.moneyOut), numeric: true },
    { key: "var", label: "Over / short", value: (r, f) => f.money(r.cashVariance), numeric: true },
    { key: "by", label: "Closed by", value: (r) => r.closedBy ?? "", secondary: true },
    { key: "why", label: "Reopen reason", value: (r) => r.reopenReason ?? "", secondary: true },
  ],
  tableTitle: "Closed days",
  tableHint: "Figures are the snapshot taken when the day was closed.",
  emptyText: "No day in this period has been closed. Close days from Money → Daily Closing.",
}

// ===========================================================================
// Takings by Account — where the customers' money landed
// ===========================================================================

export const takingsByAccount: ReportDefinition<TakingsByAccountRow> = {
  load: async (r) => ({ rows: await getTakingsByAccount(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Taken (bills)", value: f.money(sum(r.rows, (x) => x.takings)) },
    { label: "Tips", value: f.money(sum(r.rows, (x) => x.tips)) },
    { label: "Refunded", value: f.money(sum(r.rows, (x) => x.refunds)) },
    { label: "Net received", value: f.money(sum(r.rows, (x) => x.netTotal)) },
  ],
  panel: (r, f) => {
    const byAcct = new Map<string, number>()
    for (const x of r.rows) byAcct.set(x.accountName, (byAcct.get(x.accountName) ?? 0) + x.netTotal)
    const data = [...byAcct.entries()].map(([name, value]) => ({ name, value })).filter((d) => d.value > 0)
    if (data.length === 0) return null
    return card("Share by account", "Gift-card payments are listed as \"No cash moved\" — that value came in when the card was sold.",
      <ResponsiveContainer width="100%" height={240}>
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="name" outerRadius={90} label={(e) => e.name}>
            {data.map((d, i) => <Cell key={d.name} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
          </Pie>
          <Tooltip formatter={(v: number) => f.money(v)} />
        </PieChart>
      </ResponsiveContainer>)
  },
  columns: [
    { key: "acct", label: "Account", value: (r) => r.accountName },
    { key: "type", label: "Type", value: (r) => ACCOUNT_TYPE_LABELS[r.accountType] ?? r.accountType, secondary: true },
    { key: "method", label: "Method", value: (r) => r.paymentMethod },
    { key: "n", label: "Payments", value: (r, f) => f.int(r.paymentCount), numeric: true, secondary: true },
    { key: "take", label: "Taken", value: (r, f) => f.money(r.takings), numeric: true },
    { key: "tips", label: "Tips", value: (r, f) => f.money(r.tips), numeric: true, secondary: true },
    { key: "ref", label: "Refunded", value: (r, f) => f.money(r.refunds), numeric: true },
    { key: "net", label: "Net received", value: (r, f) => f.money(r.netTotal), numeric: true },
  ],
  tableTitle: "Takings by account and method",
  emptyText: "No payments were taken in this period.",
}

// ===========================================================================
// Profit vs Cash — why the cash moved differently from the profit
// ===========================================================================

export const profitVsCash: ReportDefinition<CashBridgeLine> = {
  load: async (r) => ({ rows: await getProfitVsCash(r.from, r.to) }),
  summary: (r, f) => {
    const get = (k: string) => r.rows.find((x) => x.lineKey === k)?.amount ?? 0
    return [
      { label: "Net profit", value: f.money(get("net_profit")) },
      { label: "Net cash flow", value: f.money(get("net_cash")) },
      { label: "Difference to explain", value: f.money(get("net_cash") - get("net_profit")) },
      { label: "Unexplained", value: f.money(get("check")) },
    ]
  },
  panel: (r, f) => {
    if (r.rows.length === 0) return null
    const visible = r.rows.filter((x) => x.kind !== "adjust" || x.amount !== 0)
    return card("From profit to cash", "Start at the profit the P&L reports; each line is a reason cash moved by a different amount.",
      <div>
        {visible.map((x) => (
          <div key={x.lineKey} className={`flex items-start justify-between gap-3 py-2 border-b last:border-0 ${
            x.kind === "start" || x.kind === "result" ? "font-semibold" : ""} ${x.kind === "check" ? "text-xs text-slate-500" : ""}`}>
            <div className="min-w-0">
              <div className="text-sm">{x.label}</div>
              {x.kind === "adjust" && x.explanation && <div className="text-xs text-slate-500">{x.explanation}</div>}
            </div>
            <span className={`tabular-nums text-sm whitespace-nowrap ${x.amount < 0 ? "text-rose-700" : x.kind === "adjust" ? "text-emerald-700" : ""}`}>
              {x.kind === "adjust" && x.amount > 0 ? "+" : ""}{f.money(x.amount)}
            </span>
          </div>
        ))}
      </div>)
  },
  columns: [
    { key: "line", label: "Line", value: (r) => r.label },
    { key: "amt", label: "Amount", value: (r, f) => f.money(r.amount), numeric: true },
    { key: "why", label: "Why", value: (r) => r.explanation ?? "", secondary: true },
  ],
  tableTitle: "Every line of the bridge",
  emptyText: "Nothing happened in this period.",
}

// ===========================================================================
// Payroll — runs PAID in the period, per staff member (migration 326)
// ===========================================================================
// Gross is the wage cost the P&L shows; net is what left the till. The gap is
// staff loan repayments plus other deductions.

export const payrollReport: ReportDefinition<PayrollReportRow> = {
  load: async (r) => ({ rows: await getPayrollReport(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Gross wages (P&L)", value: f.money(sum(r.rows, (x) => x.grossPay)) },
    { label: "Net pay (cash out)", value: f.money(sum(r.rows, (x) => x.netPay)) },
    { label: "Staff loan repayments", value: f.money(sum(r.rows, (x) => x.loanDeductions)) },
    { label: "Staff paid", value: f.int(r.rows.length) },
  ],
  columns: [
    { key: "s", label: "Staff", value: (r) => r.staffName ?? "—" },
    { key: "role", label: "Role", value: (r) => r.staffRole ?? "", secondary: true },
    { key: "runs", label: "Runs", value: (r, f) => f.int(r.runs), numeric: true, secondary: true },
    { key: "basic", label: "Basic", value: (r, f) => f.money(r.basicPay), numeric: true, secondary: true },
    { key: "extra", label: "Allowances, overtime & bonus", value: (r, f) => f.money(r.extras), numeric: true, secondary: true },
    { key: "gross", label: "Gross", value: (r, f) => f.money(r.grossPay), numeric: true },
    { key: "other", label: "Other deductions", value: (r, f) => f.money(r.otherDeductions), numeric: true, secondary: true },
    { key: "loan", label: "Loan repayments", value: (r, f) => f.money(r.loanDeductions), numeric: true },
    { key: "net", label: "Net pay", value: (r, f) => f.money(r.netPay), numeric: true },
  ],
  tableTitle: "Wages paid, by staff member",
  tableHint: "Only payroll runs marked Paid, by pay date.",
  emptyText: "No payroll was paid in this period. Pay staff from Money → Payroll.",
}

// ===========================================================================
// Staff Loans & Advances — what each staff member owes (migration 326)
// ===========================================================================

export const staffLoansReport: ReportDefinition<StaffLoanStaffRow> = {
  load: async (r) => ({ rows: await getStaffLoanStaffReport(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Owed by staff now", value: f.money(sum(r.rows, (x) => x.outstanding)) },
    { label: "Advanced in period", value: f.money(sum(r.rows, (x) => x.disbursedInPeriod)) },
    { label: "Repaid in period", value: f.money(sum(r.rows, (x) => x.repaidCashInPeriod + x.repaidPayrollInPeriod)) },
    { label: "Staff owing", value: f.int(r.rows.filter((x) => x.outstanding > 0).length) },
  ],
  columns: [
    { key: "s", label: "Staff", value: (r) => (r.staffName ?? "—") + (r.staffIsActive ? "" : " (inactive)") },
    { key: "role", label: "Role", value: (r) => r.role ?? "", secondary: true },
    { key: "act", label: "Active loans", value: (r, f) => f.int(r.activeLoans), numeric: true, secondary: true },
    { key: "owed", label: "Owed now", value: (r, f) => f.money(r.outstanding), numeric: true },
    { key: "adv", label: "Advanced", value: (r, f) => f.money(r.disbursedInPeriod), numeric: true },
    { key: "cash", label: "Repaid in cash", value: (r, f) => f.money(r.repaidCashInPeriod), numeric: true, secondary: true },
    { key: "pay", label: "Repaid via payroll", value: (r, f) => f.money(r.repaidPayrollInPeriod), numeric: true, secondary: true },
    { key: "int", label: "Interest", value: (r, f) => f.money(r.interestInPeriod), numeric: true, secondary: true },
    { key: "last", label: "Last repayment", value: (r) => d10(r.lastRepaymentDate) || "—", secondary: true },
  ],
  tableTitle: "Staff loans and advances",
  tableHint: "Owed now is today's balance; the other amounts are for the selected dates.",
  emptyText: "No staff loans or advances yet.",
}

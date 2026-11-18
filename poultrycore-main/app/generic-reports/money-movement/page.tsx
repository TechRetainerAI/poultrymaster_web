"use client"

// Generic Money Movement report.
//
// Four sections on one page: cash transfers, owner money, loans and loan
// repayments. None of this is income or expense — except interest and fees on
// repayments, which are the only part that reaches P&L.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, ArrowLeftRight, ArrowRight, Banknote, Loader2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getCashTransfers, getLoans, getLoanPayments,
  type GenericCashTransfer, type GenericLoan, type GenericLoanPayment,
} from "@/lib/api/generic"
import { getOwnerEntries, type GenericOwnerEntry } from "@/lib/api/generic-money-out"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { ReportPageHeader } from "@/components/reports/report-header"

function monthStart() {
  const n = new Date()
  return new Date(n.getFullYear(), n.getMonth(), 1).toISOString().slice(0, 10)
}
function today() { return new Date().toISOString().slice(0, 10) }

function inRange(iso: string | null | undefined, from: string, to: string) {
  if (!iso) return false
  const d = iso.slice(0, 10)
  return (!from || d >= from) && (!to || d <= to)
}

export default function GenericMoneyMovementPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [from, setFrom] = useState(monthStart())
  const [to, setTo] = useState(today())
  const [loading, setLoading] = useState(true)

  const [transfers, setTransfers] = useState<GenericCashTransfer[]>([])
  const [owner, setOwner] = useState<GenericOwnerEntry[]>([])
  const [loans, setLoans] = useState<GenericLoan[]>([])
  const [repayments, setRepayments] = useState<(GenericLoanPayment & { lenderName?: string })[]>([])

  const load = async () => {
    setLoading(true)
    try {
      const [t, o, l] = await Promise.all([
        getCashTransfers(), getOwnerEntries(), getLoans(),
      ])
      setTransfers(t); setOwner(o); setLoans(l)
      // Fetch all loan payments
      const allPayments: (GenericLoanPayment & { lenderName?: string })[] = []
      for (const loan of l) {
        try {
          const payments = await getLoanPayments(loan.genericLoanId)
          for (const p of payments) allPayments.push({ ...p, lenderName: loan.lenderName })
        } catch {}
      }
      setRepayments(allPayments)
    } catch (e: any) {
      toast({ title: "Could not load the report", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const xf = useMemo(() => transfers.filter((r) => inRange(r.transferDate, from, to)), [transfers, from, to])
  const om = useMemo(() => owner.filter((r) => inRange(r.entryDate, from, to)), [owner, from, to])
  const rp = useMemo(() => repayments.filter((r) => inRange(r.paymentDate, from, to)), [repayments, from, to])

  const xfLive = xf.filter((r) => r.status === "Approved")
  const omLive = om.filter((r) => r.status !== "Reversed")
  const rpLive = rp.filter((r) => !r.isReversed)

  const sum = <T,>(xs: T[], pick: (x: T) => number) => xs.reduce((t, x) => t + pick(x), 0)

  const contributions = sum(omLive.filter((r) => r.entryType === "Contribution"), (r) => r.amount)
  const draws = sum(omLive.filter((r) => r.entryType === "Draw"), (r) => r.amount)
  const liveLoans = loans.filter((l) => l.status !== "Cancelled")

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mx-auto w-full max-w-7xl">
            <Link href="/generic-reports"
                  className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
              <ArrowLeft className="h-3 w-3 mr-1" /> Reports
            </Link>
            <ReportPageHeader
              title="Money Movement"
              description="Transfers between your own accounts, money the owner put in or took out, and borrowed money. None of this is income or expense — except the interest and fees on a repayment."
              period={{ from, to }}
            />

            <Card className="mb-4">
              <CardContent className="flex flex-wrap items-end gap-3 pt-6">
                <div>
                  <Label>From</Label>
                  <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
                </div>
                <div>
                  <Label>To</Label>
                  <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
                </div>
                <Button variant="outline" onClick={load} disabled={loading}>
                  {loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Refresh
                </Button>
              </CardContent>
            </Card>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : (
              <div className="space-y-6">
                {/* ---- 1. cash transfers ---- */}
                <Section
                  icon={ArrowLeftRight}
                  title="Cash transfers"
                  note="Moving money between your own accounts. Never income or spending — the same money is simply in a different box."
                  tiles={[
                    { label: "Moved", value: fmt(sum(xfLive, (r) => r.amount)) },
                    { label: "Transfers", value: String(xfLive.length) },
                    { label: "Cancelled", value: String(xf.filter((r) => r.status === "Cancelled").length) },
                  ]}
                  empty={xf.length === 0 ? "No transfers in this period." : null}
                >
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
                      {xf.map((r) => (
                        <TableRow key={r.genericCashTransferId}>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(r.transferDate, r)}</TableCell>
                          <TableCell>{r.fromAccountName ?? "–"}</TableCell>
                          <TableCell className="flex items-center gap-1">
                            <ArrowRight className="h-3 w-3 text-slate-400" />{r.toAccountName ?? "–"}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            <Struck on={r.status === "Cancelled"}>{fmt(r.amount)}</Struck>
                          </TableCell>
                          <TableCell><StatusBadge status={r.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>

                {/* ---- 2. owner money ---- */}
                <Section
                  icon={Wallet}
                  title="Owner money"
                  note="What the owner put in and took out. A contribution is not revenue and a draw is not an expense — neither touches profit."
                  tiles={[
                    { label: "Contributions", value: fmt(contributions), accent: "emerald" },
                    { label: "Draws", value: fmt(draws), accent: "orange" },
                    { label: "Net funding", value: fmt(contributions - draws),
                      accent: contributions - draws >= 0 ? "emerald" : "rose" },
                  ]}
                  empty={om.length === 0 ? "No owner money in this period." : null}
                >
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Owner</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead>Account</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {om.map((r) => (
                        <TableRow key={r.genericOwnerEntryId}>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(r.entryDate, r)}</TableCell>
                          <TableCell>{r.ownerName ?? "–"}</TableCell>
                          <TableCell>{r.entryType}</TableCell>
                          <TableCell>{r.cashAccountName ?? "–"}</TableCell>
                          <TableCell className="text-right tabular-nums">
                            <Struck on={r.status === "Reversed"}>
                              {r.entryType === "Draw" ? "−" : "+"}{fmt(r.amount)}
                            </Struck>
                          </TableCell>
                          <TableCell><StatusBadge status={r.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>

                {/* ---- 3. loans ---- */}
                <Section
                  icon={Banknote}
                  title="Loans"
                  note="Borrowed money. Receiving it is not income, and the debt is what was borrowed — which can exceed what arrived if the lender withheld a fee."
                  tiles={[
                    { label: "Still owed", value: fmt(sum(liveLoans, (l) => l.outstandingBalance)), accent: "violet" },
                    { label: "Borrowed", value: fmt(sum(liveLoans, (l) => l.originalPrincipal)) },
                    { label: "Received", value: fmt(sum(liveLoans, (l) => l.amountReceived)) },
                    { label: "Principal repaid", value: fmt(sum(liveLoans, (l) => l.totalPrincipalPaid)), accent: "emerald" },
                  ]}
                  empty={loans.length === 0 ? "No loans on record." : null}
                  footnote="Loan totals are as they stand today, not sliced by the period — an outstanding balance is a position, not a flow."
                >
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Lender</TableHead>
                        <TableHead className="text-right">Borrowed</TableHead>
                        <TableHead className="text-right">Received</TableHead>
                        <TableHead className="text-right">Repaid</TableHead>
                        <TableHead className="text-right">Still owed</TableHead>
                        <TableHead className="text-right">Interest</TableHead>
                        <TableHead className="text-right">Fees</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {loans.map((l) => (
                        <TableRow key={l.genericLoanId}>
                          <TableCell className="font-medium">{l.lenderName ?? "–"}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.originalPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.amountReceived)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.totalPrincipalPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">{fmt(l.outstandingBalance)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalInterestPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalFeesPaid)}</TableCell>
                          <TableCell><StatusBadge status={l.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>

                {/* ---- 4. loan repayments ---- */}
                <Section
                  icon={Banknote}
                  title="Loan repayments"
                  note="What left the bank, and what it was for. Only the interest and fee columns are an expense — the principal column is reducing a debt."
                  tiles={[
                    { label: "Total paid", value: fmt(sum(rpLive, (r) => r.totalPayment)) },
                    { label: "Of which principal", value: fmt(sum(rpLive, (r) => r.principalAmount)) },
                    {
                      label: "Cost of borrowing",
                      value: fmt(sum(rpLive, (r) => r.interestAmount + r.feeAmount)),
                      accent: "amber",
                    },
                  ]}
                  empty={rp.length === 0 ? "No repayments in this period." : null}
                >
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Lender</TableHead>
                        <TableHead className="text-right">Principal</TableHead>
                        <TableHead className="text-right">Interest</TableHead>
                        <TableHead className="text-right">Fees</TableHead>
                        <TableHead className="text-right">Total paid</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {rp.map((r) => (
                        <TableRow key={r.genericLoanPaymentId}>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(r.paymentDate, r)}</TableCell>
                          <TableCell>{r.lenderName ?? "–"}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(r.principalAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(r.interestAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(r.feeAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">
                            <Struck on={r.isReversed}>{fmt(r.totalPayment)}</Struck>
                          </TableCell>
                          <TableCell><StatusBadge status={r.isReversed ? "Reversed" : "Posted"} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

function Struck({ on, children }: { on: boolean; children: React.ReactNode }) {
  return on ? <span className="line-through text-slate-400">{children}</span> : <>{children}</>
}

function StatusBadge({ status }: { status: string }) {
  const cls =
    status === "Reversed" || status === "Cancelled" ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
    : status === "Overdue" ? "bg-rose-100 text-rose-800 hover:bg-rose-100"
    : status === "PaidOff" ? "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    : "bg-sky-100 text-sky-800 hover:bg-sky-100"
  return <Badge className={cls}>{status}</Badge>
}

function Section({
  icon: Icon, title, note, tiles, empty, footnote, children,
}: {
  icon: any
  title: string
  note: string
  tiles: { label: string; value: string; accent?: "emerald" | "orange" | "rose" | "amber" | "violet" }[]
  empty: string | null
  footnote?: string
  children: React.ReactNode
}) {
  const colour = (a?: string) => ({
    emerald: "text-emerald-700",
    orange: "text-orange-700",
    rose: "text-rose-600",
    amber: "text-amber-700",
    violet: "text-violet-700",
  }[a ?? ""] ?? "text-slate-900")

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="flex items-start gap-2 mb-1">
          <Icon className="h-5 w-5 text-slate-500 mt-0.5 shrink-0" />
          <div>
            <h2 className="text-lg font-semibold text-slate-900">{title}</h2>
            <p className="text-xs text-slate-500 max-w-3xl">{note}</p>
          </div>
        </div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 my-3">
          {tiles.map((t) => (
            <div key={t.label} className="rounded-md border bg-slate-50 p-3">
              <div className="text-xs uppercase tracking-wide text-slate-500 truncate">{t.label}</div>
              <div className={`text-lg font-bold truncate ${colour(t.accent)}`}>{t.value}</div>
            </div>
          ))}
        </div>
        {empty ? (
          <p className="text-sm text-slate-500 py-4">{empty}</p>
        ) : (
          <div className="overflow-x-auto">{children}</div>
        )}
        {footnote && <p className="text-xs text-slate-400 mt-2">{footnote}</p>}
      </CardContent>
    </Card>
  )
}

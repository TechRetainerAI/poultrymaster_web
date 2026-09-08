"use client"

// Poultry Money Movement report.
//
// The four reports section 33 of the spec asks for, on one page rather than
// four thin ones: cash transfers, owner money, loans and loan repayments. They
// are read together because the questions run together — "where did the money
// go" is rarely answered by only one of them.
//
// WHAT THIS REPORT IS CAREFUL ABOUT
// --------------------------------
// Every section says what its numbers are NOT. Transfers are not income or
// spending, owner money is not revenue or expense, borrowing is not income, and
// only the interest and fee columns of a repayment are a cost. A money report
// that prints the figures without those sentences is how a farm ends up
// counting a 100,000 loan as a good month.
//
// Reversed records are shown but never counted: the totals are what actually
// stands. A reversed row is struck through so it is visibly present and
// visibly not included.

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
  listPoultryCashTransfers, listPoultryOwnerMoney, listPoultryLoans, listPoultryLoanPayments,
  type PoultryCashTransfer, type PoultryOwnerMoney,
  type PoultryLoan, type PoultryLoanPayment,
} from "@/lib/api/poultry-finance"

function monthStart() {
  const n = new Date()
  return new Date(n.getFullYear(), n.getMonth(), 1).toISOString().slice(0, 10)
}
function today() { return new Date().toISOString().slice(0, 10) }

/** Inclusive on both ends, on the date part only. */
function inRange(iso: string | null | undefined, from: string, to: string) {
  if (!iso) return false
  const d = iso.slice(0, 10)
  return (!from || d >= from) && (!to || d <= to)
}

export default function PoultryMoneyReportPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [from, setFrom] = useState(monthStart())
  const [to, setTo] = useState(today())
  const [loading, setLoading] = useState(true)

  const [transfers, setTransfers] = useState<PoultryCashTransfer[]>([])
  const [owner, setOwner] = useState<PoultryOwnerMoney[]>([])
  const [loans, setLoans] = useState<PoultryLoan[]>([])
  const [repayments, setRepayments] = useState<PoultryLoanPayment[]>([])

  const load = async () => {
    setLoading(true)
    try {
      const [t, o, l, p] = await Promise.all([
        listPoultryCashTransfers(), listPoultryOwnerMoney(),
        listPoultryLoans(), listPoultryLoanPayments(),
      ])
      setTransfers(t); setOwner(o); setLoans(l); setRepayments(p)
    } catch (e: any) {
      toast({ title: "Could not load the report", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  // Filtering happens here rather than server-side: these are small lists, and
  // one fetch that the period re-slices beats four round trips per date change.
  const xf = useMemo(
    () => transfers.filter((r) => inRange(r.transferDate, from, to)),
    [transfers, from, to],
  )
  const om = useMemo(
    () => owner.filter((r) => inRange(r.transactionDate, from, to)),
    [owner, from, to],
  )
  const rp = useMemo(
    () => repayments.filter((r) => inRange(r.paymentDate, from, to)),
    [repayments, from, to],
  )

  const xfLive = xf.filter((r) => r.status === "Approved")
  const omLive = om.filter((r) => r.status === "Posted")
  const rpLive = rp.filter((r) => r.status === "Posted")

  const sum = <T,>(xs: T[], pick: (x: T) => number) => xs.reduce((t, x) => t + pick(x), 0)

  const contributions = sum(omLive.filter((r) => r.transactionType === "Contribution"), (r) => r.amount)
  const draws = sum(omLive.filter((r) => r.transactionType === "Draw"), (r) => r.amount)
  const liveLoans = loans.filter((l) => l.status !== "Cancelled")

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mx-auto w-full max-w-7xl">
            <Link href="/poultry/reports"
                  className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
              <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
            </Link>
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Wallet className="h-6 w-6 text-violet-600" /> Money Movement
            </h1>
            <p className="text-sm text-slate-500 mb-4 max-w-3xl">
              Transfers between the farm's own accounts, money the owner put in or took out, and
              borrowed money. <strong>None of this is income or expense</strong> — except the
              interest and fees on a repayment, which are the only part that reaches the profit and
              loss.
            </p>

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
                {/* ---- 1. cash transfers ---------------------------------- */}
                <Section
                  icon={ArrowLeftRight}
                  title="Cash transfers"
                  note="Moving money between the farm's own accounts. Never company-wide money in or money out — the same money is simply in a different box."
                  tiles={[
                    { label: "Moved", value: fmt(sum(xfLive, (r) => r.amount)) },
                    { label: "Transfers", value: String(xfLive.length) },
                    { label: "Reversed", value: String(xf.filter((r) => r.status === "Reversed").length) },
                  ]}
                  empty={xf.length === 0 ? "No transfers in this period." : null}
                >
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Transfer #</TableHead>
                        <TableHead>From</TableHead>
                        <TableHead>To</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {xf.map((r) => (
                        <TableRow key={r.poultryCashTransferId}>
                          <TableCell className="whitespace-nowrap">{new Date(r.transferDate).toLocaleDateString()}</TableCell>
                          <TableCell className="font-medium">{r.transferNumber ?? `#${r.poultryCashTransferId}`}</TableCell>
                          <TableCell>{r.fromAccountName ?? "–"}</TableCell>
                          <TableCell className="flex items-center gap-1">
                            <ArrowRight className="h-3 w-3 text-slate-400" />{r.toAccountName ?? "–"}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            <Struck on={r.status === "Reversed"}>{fmt(r.amount)}</Struck>
                          </TableCell>
                          <TableCell><StatusBadge status={r.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>

                {/* ---- 2. owner money ------------------------------------- */}
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
                        <TableHead>Number</TableHead>
                        <TableHead>Owner</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead>Account</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {om.map((r) => (
                        <TableRow key={r.poultryOwnerMoneyId}>
                          <TableCell className="whitespace-nowrap">{new Date(r.transactionDate).toLocaleDateString()}</TableCell>
                          <TableCell className="font-medium">{r.transactionNumber ?? `#${r.poultryOwnerMoneyId}`}</TableCell>
                          <TableCell>{r.ownerName ?? "–"}</TableCell>
                          <TableCell>{r.transactionType}</TableCell>
                          <TableCell>{r.accountName ?? "–"}</TableCell>
                          <TableCell className="text-right tabular-nums">
                            <Struck on={r.status === "Reversed"}>
                              {r.transactionType === "Draw" ? "−" : "+"}{fmt(r.amount)}
                            </Struck>
                          </TableCell>
                          <TableCell><StatusBadge status={r.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>

                {/* ---- 3. loans ------------------------------------------- */}
                <Section
                  icon={Banknote}
                  title="Loans"
                  note="Borrowed money. Receiving it is not income, and the debt is what was borrowed — which can exceed what arrived if the lender withheld a fee."
                  tiles={[
                    { label: "Still owed", value: fmt(sum(liveLoans, (l) => l.outstandingPrincipal)), accent: "violet" },
                    { label: "Borrowed", value: fmt(sum(liveLoans, (l) => l.originalPrincipal)) },
                    { label: "Received", value: fmt(sum(liveLoans, (l) => l.amountReceived)) },
                    { label: "Principal repaid", value: fmt(sum(liveLoans, (l) => l.totalPrincipalRepaid)), accent: "emerald" },
                  ]}
                  empty={loans.length === 0 ? "No loans on record." : null}
                  footnote="Loan totals are as they stand today, not sliced by the period — an outstanding balance is a position, not a flow."
                >
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Loan #</TableHead>
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
                        <TableRow key={l.poultryLoanId}>
                          <TableCell className="font-medium">{l.loanNumber ?? `#${l.poultryLoanId}`}</TableCell>
                          <TableCell>{l.lenderName}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.originalPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.amountReceived)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.totalPrincipalRepaid)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">{fmt(l.outstandingPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalInterestPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalFeesPaid)}</TableCell>
                          <TableCell><StatusBadge status={l.isOverdue ? "Overdue" : l.status} /></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Section>

                {/* ---- 4. loan repayments --------------------------------- */}
                <Section
                  icon={Banknote}
                  title="Loan repayments"
                  note="What left the bank, and what it was for. Only the interest and fee columns are an expense — the principal column is the farm reducing a debt."
                  tiles={[
                    { label: "Total paid", value: fmt(sum(rpLive, (r) => r.totalAmount)) },
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
                        <TableHead>Payment #</TableHead>
                        <TableHead>Lender</TableHead>
                        <TableHead className="text-right">Principal</TableHead>
                        <TableHead className="text-right">Interest</TableHead>
                        <TableHead className="text-right">Fees</TableHead>
                        <TableHead className="text-right">Total paid</TableHead>
                        <TableHead>Account</TableHead>
                        <TableHead>Status</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {rp.map((r) => (
                        <TableRow key={r.poultryLoanPaymentId}>
                          <TableCell className="whitespace-nowrap">{new Date(r.paymentDate).toLocaleDateString()}</TableCell>
                          <TableCell className="font-medium">{r.paymentNumber ?? `#${r.poultryLoanPaymentId}`}</TableCell>
                          <TableCell>{r.lenderName ?? "–"}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(r.principalAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(r.interestAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(r.feeAmount)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">
                            <Struck on={r.status === "Reversed"}>{fmt(r.totalAmount)}</Struck>
                          </TableCell>
                          <TableCell>{r.accountName ?? "–"}</TableCell>
                          <TableCell><StatusBadge status={r.status} /></TableCell>
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
            {/* The sentence that stops the number being misread. */}
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

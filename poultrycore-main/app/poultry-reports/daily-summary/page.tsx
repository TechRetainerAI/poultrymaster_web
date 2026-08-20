"use client"

/**
 * Daily Business Summary (poultry).
 *
 * Poultry counterpart of app/water-reports/daily-summary/page.tsx: one day's
 * income, production, expenses, purchases, losses and cash position on a single
 * read-only sheet. Everything is assembled client-side from the existing list
 * endpoints — no new backend SP.
 *
 * PDF export goes through window.print() against a print-friendly layout; the
 * sidebar and header are dropped with `print:hidden`.
 */

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, Printer, ArrowLeft } from "lucide-react"
import Link from "next/link"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listPoultryDailyClosings, listPoultryRawMaterialPurchases, listPoultryLossRecords,
} from "@/lib/api/poultry-inventory"
import { listPoultryDriverReturns } from "@/lib/api/poultry-distribution"
import { getExpenses } from "@/lib/api/expense"
import { useFmt, useFarmSettingsStore } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }

type Summary = {
  eggsProduced: number
  eggsDamaged: number
  productionCost: number
  mortality: number
  feedUsed: number
  rawMaterialPurchase: number
  expenses: number
  expensesByCategory: Record<string, number>
  losses: number
  closingStatus: string | null
  cashCounted: number | null
  cashDifference: number | null
  income: {
    total: number
    cash: number
    moMo: number
    bank: number
    creditSales: number
    customerCollections: number
    eggsSold: number
    driverShortages: number
    /** Which source the income block came from — drives the footnote. */
    source: "closing" | "returns" | "none"
  }
}

export default function PoultryDailyBusinessSummaryPage() {
  const fmtMoney = useFmt()
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const farmName = useAuthStore((s) => s.activeFarmName)
  const farmSettings = useFarmSettingsStore((s) => s.settings)
  const logout = useLogout()
  const { toast } = useToast()

  const [date, setDate] = useState(isoDate(new Date()))
  const [busy, setBusy] = useState(false)
  const [summary, setSummary] = useState<Summary | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, date])

  async function load() {
    setBusy(true)
    try {
      const onDate = (d?: string | null) => d?.startsWith(date) ?? false

      const [closings, expenseRes, purchases, losses, returns] = await Promise.all([
        listPoultryDailyClosings({ fromDate: date, toDate: date }).catch(() => []),
        getExpenses().catch(() => ({ success: false, data: [] as any[] })),
        listPoultryRawMaterialPurchases({ fromDate: date, toDate: date }).catch(() => []),
        listPoultryLossRecords({ fromDate: date, toDate: date }).catch(() => []),
        listPoultryDriverReturns({ fromDate: date, toDate: date }).catch(() => []),
      ])

      const closing = (closings ?? []).find((c: any) => (c.closingDate ?? "").startsWith(date))

      // getExpenses has no date filter, so narrow here. Only approved-equivalent
      // rows count; poultry expenses have no status column, so all rows on the
      // day are included.
      const allExpenses = (expenseRes as any)?.data ?? []
      const dayExpenses = allExpenses.filter((e: any) => onDate(e.expenseDate))
      const expensesTotal = dayExpenses.reduce((s: number, e: any) => s + (e.amount ?? 0), 0)
      const expensesByCategory: Record<string, number> = {}
      for (const e of dayExpenses) {
        const k = (e.category || "Uncategorised") as string
        expensesByCategory[k] = (expensesByCategory[k] ?? 0) + (e.amount ?? 0)
      }

      const rawMaterialPurchase = (purchases ?? [])
        .filter((p: any) => onDate(p.purchaseDate))
        .reduce((s: number, p: any) => s + ((p.totalCost ?? ((p.quantity ?? 0) * (p.unitCost ?? 0))) ?? 0), 0)

      const lossesTotal = (losses ?? []).reduce((s: number, l: any) => s + (l.estimatedValue ?? 0), 0)

      // Income: the day's closing is authoritative — it already merges storefront
      // and delivery-run sales without double counting. With no closing yet, fall
      // back to the day's driver returns; a storefront-only day reads 0 until closed.
      const dayReturns = (returns ?? []).filter(
        (r: any) => onDate(r.returnDate) && (r.status === "Approved" || r.status === "Draft"),
      )
      const income = closing
        ? {
            total: closing.totalIncome ?? 0,
            cash: closing.cashCollected ?? Math.max(0, closing.cashAtHand ?? 0),
            moMo: closing.moMoCollected ?? closing.moMoBalance ?? 0,
            bank: closing.bankCollected ?? closing.bankBalance ?? 0,
            creditSales: closing.creditSales ?? 0,
            customerCollections: closing.customerCollections ?? 0,
            eggsSold: closing.eggsSold ?? 0,
            driverShortages: 0,
            source: "closing" as const,
          }
        : dayReturns.length
          ? {
              total: dayReturns.reduce((s: number, r: any) => s + (r.cashCollected ?? 0) + (r.moMoCollected ?? 0) + (r.bankCollected ?? 0) + (r.creditSalesAmount ?? 0), 0),
              cash: dayReturns.reduce((s: number, r: any) => s + (r.cashCollected ?? 0), 0),
              moMo: dayReturns.reduce((s: number, r: any) => s + (r.moMoCollected ?? 0), 0),
              bank: dayReturns.reduce((s: number, r: any) => s + (r.bankCollected ?? 0), 0),
              creditSales: dayReturns.reduce((s: number, r: any) => s + (r.creditSalesAmount ?? 0), 0),
              customerCollections: 0,
              eggsSold: dayReturns.reduce((s: number, r: any) => s + (r.cratesSold ?? r.quantitySold ?? 0), 0),
              driverShortages: dayReturns.reduce((s: number, r: any) => s + (r.shortageAmount ?? 0), 0),
              source: "returns" as const,
            }
          : {
              total: 0, cash: 0, moMo: 0, bank: 0, creditSales: 0,
              customerCollections: 0, eggsSold: 0, driverShortages: 0, source: "none" as const,
            }

      setSummary({
        eggsProduced: closing?.quantityProduced ?? 0,
        eggsDamaged: closing?.quantityDamaged ?? 0,
        productionCost: closing?.totalProductionCost ?? 0,
        mortality: closing?.mortality ?? 0,
        feedUsed: closing?.feedUsedQty ?? 0,
        rawMaterialPurchase,
        expenses: expensesTotal,
        expensesByCategory,
        losses: lossesTotal,
        closingStatus: closing?.status ?? null,
        cashCounted: closing?.actualCashCounted ?? null,
        cashDifference: closing?.cashDifference ?? null,
        income,
      })
    } catch (e: any) {
      toast({ title: "Could not load daily summary", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setBusy(false) }
  }

  return (
    <div className="flex min-h-screen bg-slate-50 print:bg-white">
      <div className="print:hidden"><DashboardSidebar onLogout={logout} /></div>
      <div className="flex-1 flex flex-col min-w-0">
        <div className="print:hidden"><DashboardHeader /></div>

        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 print:p-0 min-w-0">
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap print:hidden">
            <Button asChild variant="outline" size="sm">
              <Link href="/poultry/reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
            </Button>
            <Button onClick={() => window.print()} size="sm" className="gap-1">
              <Printer className="h-4 w-4" /> Export PDF
            </Button>
          </div>

          <div className="bg-white rounded-xl border border-slate-200 p-4 sm:p-6 print:border-0 print:p-0">
            <header className="mb-4 border-b pb-4 print:pb-3">
              <h1 className="text-2xl font-semibold text-slate-900">Daily Business Summary</h1>
              <div className="text-sm text-slate-500 mt-1">
                <div><span className="font-medium">Company:</span> {farmName ?? "—"}</div>
                <div><span className="font-medium">Date:</span> {date}</div>
                <div><span className="font-medium">Currency:</span> {farmSettings?.currencyCode ?? "GHS"} ({farmSettings?.currencySymbol ?? "GHC"})</div>
                <div><span className="font-medium">Generated:</span> {new Date().toLocaleString()}</div>
              </div>
            </header>

            <div className="print:hidden mb-4 flex items-end gap-2 flex-wrap">
              <div>
                <Label className="text-xs">Date</Label>
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="w-44" />
              </div>
              <Button variant="outline" size="sm" onClick={load} disabled={busy}>Refresh</Button>
            </div>

            {busy ? (
              <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : !summary ? (
              <p className="text-slate-500 text-sm">No data for this date.</p>
            ) : (
              <>
                <section className="mb-4">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Income</h2>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 print:gap-2">
                    <SumCard label="Total income" value={fmtMoney(summary.income.total)} accent="green" />
                    <SumCard label="Cash" value={fmtMoney(summary.income.cash)} />
                    <SumCard label="MoMo" value={fmtMoney(summary.income.moMo)} />
                    <SumCard label="Bank" value={fmtMoney(summary.income.bank)} />
                    <SumCard label="Credit sales" value={fmtMoney(summary.income.creditSales)} />
                    <SumCard label="Customer collections" value={fmtMoney(summary.income.customerCollections)} />
                    <SumCard label="Eggs sold" value={summary.income.eggsSold.toLocaleString()} />
                    <SumCard label="Driver shortages" value={fmtMoney(summary.income.driverShortages)} accent={summary.income.driverShortages ? "rose" : undefined} />
                  </div>
                  <p className="text-xs text-slate-500 mt-2">
                    {summary.income.source === "closing"
                      ? "Income figures are taken from the day's closing (storefront + delivery sales combined)."
                      : summary.income.source === "returns"
                        ? "No closing for this day yet — income is computed from the day's driver returns. Create the closing for the full picture."
                        : "No driver returns or closing recorded for this date."}
                  </p>
                </section>

                <section className="mb-4">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Production</h2>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 print:gap-2">
                    <SumCard label="Eggs produced" value={summary.eggsProduced.toLocaleString()} />
                    <SumCard label="Damaged / broken" value={summary.eggsDamaged.toLocaleString()} accent={summary.eggsDamaged ? "rose" : undefined} />
                    <SumCard label="Production cost" value={fmtMoney(summary.productionCost)} />
                    <SumCard label="Mortality" value={summary.mortality.toLocaleString()} accent={summary.mortality ? "rose" : undefined} />
                  </div>
                </section>

                <section className="mb-4">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Costs &amp; position</h2>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 print:gap-2">
                    <SumCard label="Feed used" value={summary.feedUsed.toLocaleString()} />
                    <SumCard label="Raw material purchases" value={fmtMoney(summary.rawMaterialPurchase)} />
                    <SumCard label="Expenses" value={fmtMoney(summary.expenses)} />
                    <SumCard label="Loss value" value={fmtMoney(summary.losses)} accent={summary.losses ? "rose" : undefined} />
                  </div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-3 print:gap-2">
                    <SumCard label="Closing status" value={summary.closingStatus ?? "Not closed"} />
                    <SumCard label="Cash counted" value={summary.cashCounted == null ? "—" : fmtMoney(summary.cashCounted)} />
                    <SumCard
                      label="Cash variance"
                      value={summary.cashDifference == null ? "—" : `${summary.cashDifference > 0 ? "+" : ""}${fmtMoney(summary.cashDifference)}`}
                      accent={summary.cashDifference == null || summary.cashDifference === 0 ? undefined : summary.cashDifference < 0 ? "rose" : "green"}
                    />
                  </div>
                </section>

                <section className="mb-4">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Expense breakdown</h2>
                  {Object.keys(summary.expensesByCategory).length === 0 ? (
                    <p className="text-sm text-slate-500">No expenses on this date.</p>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Category</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {Object.entries(summary.expensesByCategory)
                          .sort(([, a], [, b]) => b - a)
                          .map(([cat, amt]) => (
                            <TableRow key={cat}>
                              <TableCell>{cat}</TableCell>
                              <TableCell className="text-right tabular-nums">{fmtMoney(amt)}</TableCell>
                            </TableRow>
                          ))}
                      </TableBody>
                    </Table>
                  )}
                </section>

                <footer className="text-xs text-slate-500 pt-3 border-t print:pt-2">
                  Production, mortality and cash figures come from the day&apos;s closing for {date}; expenses,
                  purchases and losses are read from their own records. Production and cash read as zero until
                  the day is closed.
                </footer>
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

function SumCard({ label, value, accent }: { label: string; value: string; accent?: "rose" | "green" }) {
  const accentClass = accent === "rose" ? "text-rose-700" : accent === "green" ? "text-emerald-700" : ""
  return (
    <Card className="print:border print:shadow-none">
      <CardContent className="p-4 print:p-3">
        <div className="text-xs uppercase tracking-wider text-slate-500">{label}</div>
        <div className={`text-lg sm:text-xl font-semibold tabular-nums mt-1 ${accentClass}`}>{value}</div>
      </CardContent>
    </Card>
  )
}

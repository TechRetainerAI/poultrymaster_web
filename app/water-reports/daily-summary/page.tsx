"use client"

/**
 * Daily Business Summary report (Prompt 2 §16.1).
 *
 * Aggregates today's (or a selected day's) sales, payments, expenses,
 * production, raw material purchases, losses and cash position into a single
 * read-only report. Data is pulled by client-side from existing list endpoints
 * (no new backend SP needed — keeps surface area down).
 *
 * PDF export uses the browser's print pipeline via window.print() against a
 * print-friendly layout. The header / sidebar are excluded with the
 * `print:hidden` Tailwind class.
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
  listWaterProductionBatches, listWaterExpenses, listWaterDailyClosings,
  listWaterProductionLosses, listWaterRawMaterialPurchases, listWaterDriverReturns,
} from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { useFarmSettingsStore } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }

type Summary = {
  productionGoodBags: number
  productionCost: number
  rawMaterialPurchase: number
  expenses: number
  expensesByCategory: Record<string, number>
  losses: number
  closingStatus: string | null
  // Income block — sourced from the day's closing when present (authoritative,
  // already de-dups delivery-run sales), else computed from driver returns.
  income: {
    total: number
    cash: number
    moMo: number
    bank: number
    creditSales: number
    customerCollections: number
    bagsSold: number
    driverShortages: number
    /** where the income figures came from, for the footnote */
    source: "closing" | "returns" | "none"
  }
}

export default function DailyBusinessSummaryPage() {
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
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, date])

  async function load() {
    setBusy(true)
    try {
      const onDate = (d?: string | null) => d?.startsWith(date) ?? false

      const [batches, expenses, closings, losses, purchases, returns] = await Promise.all([
        listWaterProductionBatches().catch(() => []),
        listWaterExpenses().catch(() => []),
        listWaterDailyClosings().catch(() => []),
        listWaterProductionLosses({ fromDate: date, toDate: date }).catch(() => []),
        listWaterRawMaterialPurchases().catch(() => []),
        listWaterDriverReturns({ fromDate: date, toDate: date }).catch(() => []),
      ])

      const day = batches.filter((b: any) => onDate(b.productionDate) && b.status === "Approved")
      const productionGoodBags = day.reduce((s: number, b: any) => s + ((b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))) ?? 0), 0)
      const productionCost = day.reduce((s: number, b: any) => s + ((b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0))) ?? 0), 0)

      const dayExpenses = expenses.filter((e: any) => onDate(e.expenseDate) && (e.status === "Approved"))
      const expensesTotal = dayExpenses.reduce((s: number, e: any) => s + (e.amount ?? 0), 0)
      const expensesByCategory: Record<string, number> = {}
      for (const e of dayExpenses) {
        const k = (e.categoryName ?? "Uncategorised") as string
        expensesByCategory[k] = (expensesByCategory[k] ?? 0) + (e.amount ?? 0)
      }

      const rawMatPurchase = purchases.filter((p: any) => (p.purchaseDate ?? "").startsWith(date))
        .reduce((s: number, p: any) => s + ((p.totalCost ?? ((p.quantity ?? 0) * (p.unitCost ?? 0))) ?? 0), 0)

      const lossesTotal = (losses ?? []).reduce((s: number, l: any) => s + (l.totalValue ?? 0), 0)

      const closing = closings.find((c: any) => (c.closingDate ?? "").startsWith(date))

      // Income: prefer the day's closing (authoritative — it already merges
      // storefront + delivery-run/driver sales without double counting). When no
      // closing exists yet, fall back to the day's driver returns (clean money
      // split); storefront-only days without a closing will read 0 until closed.
      const dayReturns = (returns ?? []).filter(
        (r: any) => onDate(r.returnDate) && (r.status === "Approved" || r.status === "Draft"),
      )
      const income = closing
        ? {
            total: closing.totalIncome ?? 0,
            cash: Math.max(0, (closing.cashAtHand ?? 0)), // best-effort cash figure
            moMo: closing.moMoBalance ?? 0,
            bank: closing.bankBalance ?? 0,
            creditSales: closing.creditSales ?? 0,
            customerCollections: closing.customerCollections ?? 0,
            bagsSold: closing.bagsSold ?? 0,
            driverShortages: closing.driverShortagesTotal ?? closing.driverShortages ?? 0,
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
              bagsSold: dayReturns.reduce((s: number, r: any) => s + (r.bagsSold ?? 0), 0),
              driverShortages: dayReturns.reduce((s: number, r: any) => s + (r.shortageAmount ?? 0), 0),
              source: "returns" as const,
            }
          : {
              total: 0, cash: 0, moMo: 0, bank: 0, creditSales: 0,
              customerCollections: 0, bagsSold: 0, driverShortages: 0, source: "none" as const,
            }

      setSummary({
        productionGoodBags,
        productionCost,
        rawMaterialPurchase: rawMatPurchase,
        expenses: expensesTotal,
        expensesByCategory,
        losses: lossesTotal,
        closingStatus: closing?.status ?? null,
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
          {/* Header — visible on screen only. */}
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap print:hidden">
            <Button asChild variant="outline" size="sm">
              <Link href="/water-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
            </Button>
            <Button onClick={() => window.print()} size="sm" className="gap-1">
              <Printer className="h-4 w-4" /> Export PDF
            </Button>
          </div>

          {/* Print + screen header */}
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
                {/* Income */}
                <section className="mb-4">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Income</h2>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 print:gap-2">
                    <SumCard label="Total income" value={fmtMoney(summary.income.total)} accent="green" />
                    <SumCard label="Cash" value={fmtMoney(summary.income.cash)} />
                    <SumCard label="MoMo" value={fmtMoney(summary.income.moMo)} />
                    <SumCard label="Bank" value={fmtMoney(summary.income.bank)} />
                    <SumCard label="Credit sales" value={fmtMoney(summary.income.creditSales)} />
                    <SumCard label="Customer collections" value={fmtMoney(summary.income.customerCollections)} />
                    <SumCard label="Bags sold" value={summary.income.bagsSold.toLocaleString()} />
                    <SumCard label="Driver shortages" value={fmtMoney(summary.income.driverShortages)} accent={summary.income.driverShortages ? "rose" : undefined} />
                  </div>
                  <p className="text-xs text-slate-500 mt-2">
                    {summary.income.source === "closing"
                      ? "Income figures are taken from the day's closing (storefront + delivery sales combined)."
                      : summary.income.source === "returns"
                        ? "No closing for this day yet — income is computed from the day's driver returns. Create the closing for the full picture."
                        : "No sales, driver returns, or closing recorded for this date."}
                  </p>
                </section>

                {/* Summary cards */}
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4 print:gap-2">
                  <SumCard label="Good bags produced" value={summary.productionGoodBags.toLocaleString()} />
                  <SumCard label="Production cost" value={fmtMoney(summary.productionCost)} />
                  <SumCard label="Raw material purchases" value={fmtMoney(summary.rawMaterialPurchase)} />
                  <SumCard label="Approved expenses" value={fmtMoney(summary.expenses)} />
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4 print:gap-2">
                  <SumCard label="Loss value" value={fmtMoney(summary.losses)} accent="rose" />
                  <SumCard label="Closing status" value={summary.closingStatus ?? "Not closed"} />
                </div>

                {/* Expense breakdown */}
                <section className="mb-4">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">Expense breakdown</h2>
                  {Object.keys(summary.expensesByCategory).length === 0 ? (
                    <p className="text-sm text-slate-500">No approved expenses on this date.</p>
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
                  Generated from approved production, expense, loss and closing rows for {date}. Cash totals require a closing for the day.
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

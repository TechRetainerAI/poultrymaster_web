"use client"

// Water Closing by Category (migration 463) -- the sibling of
// /water-reports/closing-report, which lists each day's closing. This one
// totals a whole PERIOD into categories, like Poultry's /poultry-closing-report.
// Every figure comes from the server function that owns it, so Financial agrees
// with Profit & Loss and Cash agrees with Cash Flow for the same dates.

import { useEffect, useState } from "react"
import { ReportShell } from "@/components/reports/report-shell"
import { getWaterClosingByCategory } from "@/lib/api/water-closing-report"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

type Row = { label: string; key: string; money?: boolean; pct?: boolean }
const SECTIONS: { title: string; color: string; note?: string; rows: Row[] }[] = [
  { title: "Financial", color: "bg-blue-600", note: "Same figures as Profit & Loss for these dates.", rows: [
    { label: "Total revenue", key: "TotalRevenue", money: true },
    { label: "Storefront sales", key: "StorefrontSales", money: true },
    { label: "Delivery collections", key: "DeliveryCollections", money: true },
    { label: "Raw materials", key: "RawMaterialsCost", money: true },
    { label: "Production cost", key: "ProductionCost", money: true },
    { label: "Gross profit", key: "GrossProfit", money: true },
    { label: "Operating expenses", key: "OperatingExpenses", money: true },
    { label: "Losses", key: "TotalLosses", money: true },
    { label: "Net profit / loss", key: "NetProfit", money: true },
    { label: "Net margin", key: "NetMarginPct", pct: true },
    { label: "Owed by customers (today)", key: "OwedByCustomers", money: true },
    { label: "Overdue from customers (today)", key: "OverdueFromCustomers", money: true },
    { label: "Owed to suppliers (today)", key: "OwedToSuppliers", money: true },
  ]},
  { title: "Production", color: "bg-emerald-600", rows: [
    { label: "Approved production batches", key: "ProductionBatches" },
    { label: "Bags produced", key: "BagsProduced" },
    { label: "Bags damaged in production", key: "BagsDamagedInProduction" },
    { label: "Good bags", key: "GoodBags" },
    { label: "Rejected sachets", key: "RejectedSachets" },
    { label: "Water used (litres, estimated)", key: "WaterUsedLitres" },
    { label: "Good bags per day", key: "AvgBagsPerDay" },
    { label: "Cost per good bag", key: "CostPerGoodBag", money: true },
  ]},
  { title: "Inventory", color: "bg-indigo-600", rows: [
    { label: "Opening stock (bags)", key: "OpeningStockBags" },
    { label: "Closing stock (bags)", key: "ClosingStockBags" },
    { label: "Bags sold", key: "BagsSold" },
    { label: "Raw material purchases", key: "RawMaterialPurchases" },
    { label: "Raw materials purchased (value)", key: "RawMaterialsPurchasedValue", money: true },
    { label: "Raw materials used (qty)", key: "RawMaterialsConsumedQty" },
    { label: "Raw materials used (value)", key: "RawMaterialsConsumedValue", money: true },
  ]},
  { title: "Losses", color: "bg-red-600", rows: [
    { label: "Production losses", key: "ProductionLosses", money: true },
    { label: "Driver cash shortages", key: "DriverShortages", money: true },
  ]},
  { title: "Cash", color: "bg-amber-600", note: "Same figures as Cash Flow for these dates.", rows: [
    { label: "Opening cash", key: "OpeningCash", money: true },
    { label: "Money in", key: "MoneyIn", money: true },
    { label: "Money out", key: "MoneyOut", money: true },
    { label: "Net cash flow", key: "NetCashFlow", money: true },
    { label: "Closing cash", key: "ClosingCash", money: true },
    { label: "Customer payments received", key: "CustomerPaymentsReceived", money: true },
  ]},
  { title: "Delivery", color: "bg-sky-600", rows: [
    { label: "Approved delivery runs", key: "DeliveryRuns" },
    { label: "Bags loaded", key: "BagsLoaded" },
    { label: "Bags sold on delivery", key: "BagsSoldOnDelivery" },
    { label: "Bags returned", key: "BagsReturned" },
    { label: "Bags damaged on delivery", key: "BagsDamagedOnDelivery" },
    { label: "Driver collections", key: "DriverCollections", money: true },
    { label: "Delivery credit sales", key: "DeliveryCreditSales", money: true },
    { label: "Delivery expenses", key: "DeliveryExpenses", money: true },
  ]},
  { title: "Staff", color: "bg-purple-600", rows: [
    { label: "Payroll runs", key: "PayrollRuns" },
    { label: "Payroll (gross)", key: "PayrollGross", money: true },
    { label: "Payroll paid out", key: "PayrollPaidOut", money: true },
    { label: "Held for staff (today)", key: "HeldForStaff", money: true },
  ]},
]

export default function WaterClosingByCategoryPage() {
  const gh = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [data, setData] = useState<Record<string, unknown> | null>(null)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try { setData(await getWaterClosingByCategory(fromDate, toDate)) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const show = (r: Row) => {
    const v = data?.[r.key]
    if (v == null) return "—"
    const n = Number(v)
    if (!Number.isFinite(n)) return String(v)
    if (r.money) return gh(n)
    if (r.pct) return `${n.toFixed(1)}%`
    return n.toLocaleString()
  }

  return (
    <ReportShell
      title="Closing by Category"
      description="Period totals grouped into financial, production, inventory, losses, cash, delivery and staff."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      // The sections are already one column on a phone; keep them rather than
      // the generic scorecards the shell would build from the PDF rows.
      mobileCards={false}
      pdf={{
        title: "Closing by Category",
        filename: "water-closing-by-category",
        columns: [{ header: "Category" }, { header: "Item" }, { header: "Value", align: "right" }],
        rows: data ? SECTIONS.flatMap((s) => s.rows.map((r) => [s.title, r.label, show(r)])) : [],
      }}
    >
      {data && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {SECTIONS.map((s) => (
            <div key={s.title} className="overflow-hidden rounded-lg border bg-white">
              <div className={`${s.color} px-4 py-2 font-semibold text-white`}>{s.title}</div>
              {s.note && <p className="px-4 pt-2 text-[11px] text-slate-500">{s.note}</p>}
              <table className="w-full text-sm">
                <tbody>
                  {s.rows.map((r) => (
                    <tr key={r.key} className="border-b last:border-0">
                      <td className="px-4 py-2 text-slate-600">{r.label}</td>
                      <td className="px-4 py-2 text-right font-medium tabular-nums">{show(r)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))}
        </div>
      )}
    </ReportShell>
  )
}

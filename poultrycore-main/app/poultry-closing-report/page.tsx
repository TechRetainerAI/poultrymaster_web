"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getPoultryClosingReport } from "@/lib/api/poultry-inventory"

type Row = { label: string; key: string; money?: boolean }
const SECTIONS: { title: string; color: string; rows: Row[] }[] = [
  { title: "Financial Summary", color: "bg-blue-600", rows: [
    { label: "Total Sales / Income", key: "TotalSales", money: true },
    { label: "Total Expenses", key: "TotalExpenses", money: true },
    { label: "Total Raw Material Purchases", key: "TotalRawMaterialPurchases", money: true },
    { label: "Total Feed Cost", key: "TotalFeedCost", money: true },
    { label: "Total Medication Cost", key: "TotalMedicationCost", money: true },
    { label: "Total Cost of Production", key: "TotalCostOfProduction", money: true },
    { label: "Net Profit / Loss", key: "NetProfitLoss", money: true },
    { label: "Amount Owed by Customers", key: "TotalOwedByCustomers", money: true },
  ]},
  { title: "Production Summary", color: "bg-emerald-600", rows: [
    { label: "Total Eggs Produced", key: "TotalEggsProduced" },
    { label: "Total Good Eggs", key: "TotalGoodEggs" },
    { label: "Total Broken Eggs", key: "TotalBrokenEggs" },
    { label: "Total Production Records", key: "TotalProductionRecords" },
    { label: "Average Eggs / Day", key: "AvgEggsPerDay" },
    { label: "Average Eggs / Record", key: "AvgEggsPerRecord" },
    { label: "Total Feed (kg)", key: "TotalFeedKg" },
    { label: "Total Feed Consumed", key: "TotalFeedConsumed" },
    { label: "Total Medication Consumed", key: "TotalMedicationConsumed" },
    { label: "Avg Production Cost / Egg", key: "AvgProductionCostPerEgg", money: true },
  ]},
  { title: "Inventory Summary", color: "bg-indigo-600", rows: [
    { label: "Opening Egg Stock", key: "OpeningEggStock" },
    { label: "Closing Egg Stock", key: "ClosingEggStock" },
    { label: "Eggs Sold", key: "EggsSold" },
    { label: "Raw Materials Purchased (value)", key: "RawMaterialsPurchased", money: true },
    { label: "Raw Materials Consumed (qty)", key: "RawMaterialsConsumed" },
  ]},
  { title: "Birds", color: "bg-purple-600", rows: [
    { label: "Placed Birds (overall)", key: "PlacedBirds" },
    { label: "Birds Left", key: "BirdsLeft" },
    { label: "Birds Lost", key: "BirdsLost" },
    { label: "Mortality Count", key: "MortalityCount" },
    { label: "Mortality Rate %", key: "MortalityRatePct" },
    { label: "Birds Purchased (inventory)", key: "BirdsPurchased" },
    { label: "Birds Sold (inventory)", key: "BirdsSold" },
  ]},
  { title: "Losses", color: "bg-red-600", rows: [
    { label: "Production Loss (qty)", key: "ProductionLossQty" },
    { label: "Approved Loss Value", key: "ApprovedLossValue", money: true },
    { label: "Broken Eggs", key: "BrokenEggsTotal" },
  ]},
  { title: "Cash & Delivery", color: "bg-amber-600", rows: [
    { label: "Cash Sales Collected", key: "CashSalesCollected", money: true },
    { label: "Cash Adjustments (net)", key: "CashAdjustmentsNet", money: true },
    { label: "Estimated Cash Inflows", key: "EstimatedCashInflows", money: true },
    { label: "Eggs Loaded for Delivery", key: "EggsLoadedForDelivery" },
    { label: "Eggs Returned", key: "EggsReturned" },
    { label: "Driver Collections", key: "DriverCollections", money: true },
    { label: "Delivery Expenses", key: "DeliveryExpenses", money: true },
  ]},
]

// Default to a wide window (3 years back) so the report shows existing data on
// open instead of an empty current-month view; the user can narrow it.
function defaultFrom() { const d = new Date(); return `${d.getFullYear() - 3}-01-01` }

export default function PoultryClosingReportPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(new Date().toISOString().split("T")[0])
  const [data, setData] = useState<Record<string, any> | null>(null)
  const [loading, setLoading] = useState(false)

  async function run() {
    setLoading(true)
    try { setData(await getPoultryClosingReport(fromDate, toDate)) }
    catch (e: any) { toast({ title: "Could not load report", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void run()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  const fmt = (r: Row) => {
    const v = data?.[r.key]
    if (v == null) return "—"
    return r.money ? gh(Number(v)) : Number(v).toLocaleString()
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div><h1 className="text-2xl font-bold">Closing Report</h1><p className="text-sm text-slate-500">Period-end summary of production, money, inventory and losses.</p></div>
          <Card><CardContent className="p-4 flex flex-wrap items-end gap-3">
            <div><label className="text-xs text-slate-500 block mb-1">From</label><Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} className="w-40" /></div>
            <div><label className="text-xs text-slate-500 block mb-1">To</label><Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} className="w-40" /></div>
            <Button onClick={run} disabled={loading}>{loading ? <Loader2 className="w-4 h-4 animate-spin" /> : "Run report"}</Button>
          </CardContent></Card>

          {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : data && (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {SECTIONS.map((s) => (
                <Card key={s.title} className="overflow-hidden">
                  <div className={`${s.color} text-white px-4 py-2 font-semibold`}>{s.title}</div>
                  <CardContent className="p-0">
                    <table className="w-full text-sm">
                      <tbody>
                        {s.rows.map((r) => (
                          <tr key={r.key} className="border-b last:border-0">
                            <td className="px-4 py-2 text-slate-600">{r.label}</td>
                            <td className="px-4 py-2 text-right font-medium">{fmt(r)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

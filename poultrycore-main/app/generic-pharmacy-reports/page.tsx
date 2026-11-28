"use client"

// Pharmacy -> Pharmacy reports (migration 515). One report, four views, from
// spgenericpharmacy_report:
//   Sales & profit   - what each medicine sold in the period, revenue, cost and profit
//   Slow-moving      - stock that has not sold in the period (money tied up on the shelf)
//   Expiry           - expired and soon-expiring stock, linked to Batches & expiry
//   Controlled drugs - stock and sales of medicines marked as controlled

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Download, Loader2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { PharmacyShell } from "@/components/generic/pharmacy/pharmacy-shell"
import { ClassBadge, ExpiryBadge } from "@/components/generic/pharmacy/badges"
import { getMedicines, getPharmacyReport, getPharmacySettings, type Medicine, type PharmacyReportRow } from "@/lib/api/generic-pharmacy"
import { describeQty, sellUnits } from "@/lib/generic/pharmacy"

type View = "sales" | "slow" | "expiry" | "controlled"
const iso = (d: Date) => d.toISOString().slice(0, 10)

export default function PharmacyReportsPage() {
  const { toast } = useToast()
  const fmt = useFmt()
  const [from, setFrom] = useState(() => iso(new Date(Date.now() - 30 * 86_400_000)))
  const [to, setTo] = useState(() => iso(new Date()))
  const [days, setDays] = useState(90)
  const [rows, setRows] = useState<PharmacyReportRow[]>([])
  const [meds, setMeds] = useState<Medicine[]>([])
  const [loading, setLoading] = useState(true)
  const [view, setView] = useState<View>("sales")

  useEffect(() => {
    getPharmacySettings().then((s) => setDays(s.expiryWarningDays || 90)).catch(() => {})
    getMedicines().then(setMeds).catch(() => {})
  }, [])

  useEffect(() => {
    if (!from || !to) return
    setLoading(true)
    getPharmacyReport(from, to, days)
      .then(setRows)
      .catch((e) => toast({ title: "Could not load the report", description: e?.message, variant: "destructive" }))
      .finally(() => setLoading(false))
  }, [from, to, days]) // eslint-disable-line react-hooks/exhaustive-deps

  const unitsOf = (r: PharmacyReportRow) => {
    const m = meds.find((x) => x.genericProductId === r.genericProductId)
    return m ? sellUnits(m) : [{ unit: r.baseUnit, factor: 1, price: 0 }]
  }

  const shown = useMemo(() => {
    if (view === "sales") return rows.filter((r) => r.qtySold > 0).sort((a, b) => b.revenue - a.revenue)
    if (view === "slow") return rows.filter((r) => r.currentStock > 0 && r.qtySold === 0).sort((a, b) => b.stockValue - a.stockValue)
    if (view === "expiry") return rows.filter((r) => r.expiredQty > 0 || r.expiringQty > 0).sort((a, b) => b.expiredQty - a.expiredQty || String(a.nearestExpiry).localeCompare(String(b.nearestExpiry)))
    return rows.filter((r) => r.isControlled)
  }, [rows, view])

  const sum = (k: keyof PharmacyReportRow) => shown.reduce((s, r) => s + (Number(r[k]) || 0), 0)

  const exportCsv = () => {
    const head = ["Medicine", "Generic name", "Class", "Base unit", "Qty sold", "Revenue", "Cost", "Profit", "Last sold", "In stock", "Stock value", "Expired qty", `Expiring in ${days} days`, "Nearest expiry"]
    const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`
    const lines = shown.map((r) => [r.productName, r.genericName, r.medicineClass, r.baseUnit, r.qtySold, r.revenue, r.cost, r.profit,
      r.lastSoldAt ? String(r.lastSoldAt).slice(0, 10) : "", r.currentStock, r.stockValue, r.expiredQty, r.expiringQty, r.nearestExpiry ?? ""].map(esc).join(","))
    const blob = new Blob([[head.map(esc).join(","), ...lines].join("\n")], { type: "text/csv" })
    const a = document.createElement("a")
    a.href = URL.createObjectURL(blob)
    a.download = `pharmacy-${view}-${from}-to-${to}.csv`
    a.click()
    URL.revokeObjectURL(a.href)
  }

  return (
    <PharmacyShell title="Pharmacy reports" subtitle="Sales and profit per medicine, slow-moving stock, expiry and controlled drugs" wide
      actions={<Button variant="outline" onClick={exportCsv} disabled={shown.length === 0}><Download className="h-4 w-4 mr-1" /> Export CSV</Button>}>
      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap items-end gap-2">
            <div><Label className="text-xs">From</Label><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
            <div><Label className="text-xs">To</Label><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
            <Tabs value={view} onValueChange={(v) => setView(v as View)}>
              <TabsList>
                <TabsTrigger value="sales">Sales &amp; profit</TabsTrigger>
                <TabsTrigger value="slow">Slow-moving</TabsTrigger>
                <TabsTrigger value="expiry">Expiry</TabsTrigger>
                <TabsTrigger value="controlled">Controlled drugs</TabsTrigger>
              </TabsList>
            </Tabs>
          </div>
          <p className="text-xs text-slate-500">
            {view === "sales" && "Approved sales in the period. Cost uses each product's cost price."}
            {view === "slow" && "Medicines in stock that did not sell at all in the period, biggest stock value first."}
            {view === "expiry" && <>Stock in expired batches, and stock expiring within {days} days. Write expired stock off in <Link className="text-emerald-700 underline" href="/generic-batches?view=expired">Batches &amp; expiry</Link>.</>}
            {view === "controlled" && "Medicines marked “Controlled drug” in Medicines."}
          </p>

          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
          ) : shown.length === 0 ? (
            <p className="py-10 text-center text-sm text-slate-500">Nothing to show for this period.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Medicine</TableHead>
                    {(view === "sales" || view === "controlled") && <><TableHead className="text-right">Sold</TableHead><TableHead className="text-right">Revenue</TableHead><TableHead className="text-right">Cost</TableHead><TableHead className="text-right">Profit</TableHead></>}
                    {view === "slow" && <TableHead>Last sold</TableHead>}
                    <TableHead className="text-right">In stock</TableHead>
                    {view !== "sales" && <TableHead className="text-right">Stock value</TableHead>}
                    {view === "expiry" && <><TableHead className="text-right">Expired</TableHead><TableHead className="text-right">Expiring soon</TableHead><TableHead>Next expiry</TableHead></>}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {shown.map((r) => {
                    const u = unitsOf(r)
                    return (
                      <TableRow key={r.genericProductId}>
                        <TableCell>
                          <div className="font-medium">{r.productName}</div>
                          <div className="flex items-center gap-1 text-xs text-slate-500">{r.genericName}{r.isMedicine && <ClassBadge cls={r.medicineClass} />}</div>
                        </TableCell>
                        {(view === "sales" || view === "controlled") && <>
                          <TableCell className="text-right whitespace-nowrap">{describeQty(r.qtySold, u)}</TableCell>
                          <TableCell className="text-right">{fmt(r.revenue)}</TableCell>
                          <TableCell className="text-right">{fmt(r.cost)}</TableCell>
                          <TableCell className={`text-right font-medium ${r.profit < 0 ? "text-rose-600" : ""}`}>{fmt(r.profit)}</TableCell>
                        </>}
                        {view === "slow" && <TableCell className="whitespace-nowrap">{r.lastSoldAt ? String(r.lastSoldAt).slice(0, 10) : "Never"}</TableCell>}
                        <TableCell className="text-right whitespace-nowrap">{describeQty(r.currentStock, u)}</TableCell>
                        {view !== "sales" && <TableCell className="text-right">{fmt(r.stockValue)}</TableCell>}
                        {view === "expiry" && <>
                          <TableCell className="text-right whitespace-nowrap text-rose-600">{r.expiredQty > 0 ? describeQty(r.expiredQty, u) : "—"}</TableCell>
                          <TableCell className="text-right whitespace-nowrap text-amber-700">{r.expiringQty > 0 ? describeQty(r.expiringQty, u) : "—"}</TableCell>
                          <TableCell><ExpiryBadge date={r.nearestExpiry} days={days} /></TableCell>
                        </>}
                      </TableRow>
                    )
                  })}
                </TableBody>
                {(view === "sales" || view === "controlled" || view === "slow") && (
                  <TableFooter>
                    <TableRow>
                      <TableCell className="font-semibold">Total</TableCell>
                      {(view === "sales" || view === "controlled") && <>
                        <TableCell />
                        <TableCell className="text-right font-semibold">{fmt(sum("revenue"))}</TableCell>
                        <TableCell className="text-right font-semibold">{fmt(sum("cost"))}</TableCell>
                        <TableCell className="text-right font-semibold">{fmt(sum("profit"))}</TableCell>
                      </>}
                      {view === "slow" && <TableCell />}
                      <TableCell />
                      {view !== "sales" && <TableCell className="text-right font-semibold">{fmt(sum("stockValue"))}</TableCell>}
                    </TableRow>
                  </TableFooter>
                )}
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </PharmacyShell>
  )
}

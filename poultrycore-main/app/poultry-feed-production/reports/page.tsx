"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, ArrowLeft, Factory, Wheat } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listFeedProductionBatches, getFeedIngredientUsageReport,
  type FeedProductionBatch, type FeedIngredientUsageRow,
} from "@/lib/api/poultry-feed-production"

export default function FeedProductionReportsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()

  const [fromDate, setFromDate] = useState("")
  const [toDate, setToDate] = useState("")
  const [loading, setLoading] = useState(true)
  const [batches, setBatches] = useState<FeedProductionBatch[]>([])
  const [usage, setUsage] = useState<FeedIngredientUsageRow[]>([])

  async function load() {
    setLoading(true)
    try {
      const opts = { fromDate: fromDate || undefined, toDate: toDate || undefined }
      const [b, u] = await Promise.all([
        listFeedProductionBatches({ ...opts, status: "Posted" }),
        getFeedIngredientUsageReport(opts),
      ])
      setBatches(b)
      setUsage(u)
    } catch (e: any) {
      toast({ title: "Failed to load reports", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const totals = useMemo(() => ({
    batches: batches.length,
    quantity: batches.reduce((s, b) => s + b.quantityProduced, 0),
    ingredientCost: batches.reduce((s, b) => s + b.totalIngredientCost, 0),
    additionalCost: batches.reduce((s, b) => s + b.totalAdditionalCost, 0),
    total: batches.reduce((s, b) => s + b.totalProductionCost, 0),
  }), [batches])
  const usageTotalCost = useMemo(() => usage.reduce((s, u) => s + u.totalCost, 0), [usage])

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center gap-2 flex-wrap">
            <Button variant="ghost" size="sm" onClick={() => router.push("/poultry/reports")}><ArrowLeft className="w-4 h-4 mr-1" /> Back</Button>
            <h1 className="text-2xl font-bold">Feed Production Reports</h1>
          </div>

          <Card><CardContent className="p-4">
            <div className="flex flex-wrap items-end gap-3">
              <div><label className="text-xs text-slate-500">From</label><Input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} /></div>
              <div><label className="text-xs text-slate-500">To</label><Input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} /></div>
              <Button onClick={() => void load()} disabled={loading}>{loading ? <Loader2 className="w-4 h-4 animate-spin" /> : "Apply"}</Button>
            </div>
          </CardContent></Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : (
            <Tabs defaultValue="production" className="gap-4">
              <TabsList className="self-start">
                <TabsTrigger value="production"><Factory className="w-4 h-4 mr-1" /> Feed Production</TabsTrigger>
                <TabsTrigger value="ingredients"><Wheat className="w-4 h-4 mr-1" /> Ingredient Usage</TabsTrigger>
              </TabsList>

              <TabsContent value="production">
                <Card><CardContent className="p-4">
                  <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
                    <Mini label="Batches" value={totals.batches.toLocaleString()} />
                    <Mini label="Qty produced" value={totals.quantity.toLocaleString()} />
                    <Mini label="Ingredient cost" value={gh(totals.ingredientCost)} />
                    <Mini label="Additional cost" value={gh(totals.additionalCost)} />
                    <Mini label="Total cost" value={gh(totals.total)} />
                  </div>
                  <div className="overflow-x-auto">
                    <Table className="min-w-[820px]">
                      <TableHeader><TableRow>
                        <TableHead>Batch #</TableHead><TableHead>Date</TableHead><TableHead>Finished Feed</TableHead>
                        <TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Ingredient</TableHead>
                        <TableHead className="text-right">Additional</TableHead><TableHead className="text-right">Total</TableHead><TableHead className="text-right">Cost/Unit</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {batches.length === 0 ? (
                          <TableRow><TableCell colSpan={8} className="text-center text-slate-400 py-8">No posted batches in this range.</TableCell></TableRow>
                        ) : batches.map((b) => (
                          <TableRow key={b.poultryFeedProductionBatchId} className="cursor-pointer" onClick={() => router.push(`/poultry-feed-production/${b.poultryFeedProductionBatchId}`)}>
                            <TableCell className="font-medium">{b.batchNumber}</TableCell>
                            <TableCell>{b.productionDate ? new Date(b.productionDate).toLocaleDateString() : "—"}</TableCell>
                            <TableCell>{b.finishedFeedItemName ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{b.quantityProduced.toLocaleString()}{b.outputUnit ? ` ${b.outputUnit}` : ""}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(b.totalIngredientCost)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(b.totalAdditionalCost)}</TableCell>
                            <TableCell className="text-right tabular-nums font-medium">{gh(b.totalProductionCost)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(b.costPerOutputUnit)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent></Card>
              </TabsContent>

              <TabsContent value="ingredients">
                <Card><CardContent className="p-4">
                  <div className="mb-3 text-sm text-slate-500">Total ingredient cost across posted batches: <span className="font-semibold text-slate-800">{gh(usageTotalCost)}</span></div>
                  <div className="overflow-x-auto">
                    <Table className="min-w-[760px]">
                      <TableHeader><TableRow>
                        <TableHead>Ingredient</TableHead>
                        <TableHead className="text-right">Total used</TableHead>
                        <TableHead className="text-right">From inventory</TableHead>
                        <TableHead className="text-right">Bought</TableHead>
                        <TableHead className="text-right">Cost</TableHead>
                        <TableHead className="text-right">Batches</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {usage.length === 0 ? (
                          <TableRow><TableCell colSpan={6} className="text-center text-slate-400 py-8">No ingredient usage in this range.</TableCell></TableRow>
                        ) : usage.map((u) => (
                          <TableRow key={u.ingredientItemId}>
                            <TableCell className="font-medium">{u.ingredientName}</TableCell>
                            <TableCell className="text-right tabular-nums">{u.totalQuantityUsed.toLocaleString()}{u.unitOfMeasure ? ` ${u.unitOfMeasure}` : ""}</TableCell>
                            <TableCell className="text-right tabular-nums">{u.fromInventoryQuantity.toLocaleString()}</TableCell>
                            <TableCell className="text-right tabular-nums">{u.purchasedQuantity.toLocaleString()}</TableCell>
                            <TableCell className="text-right tabular-nums font-medium">{gh(u.totalCost)}</TableCell>
                            <TableCell className="text-right tabular-nums">{u.batchCount}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent></Card>
              </TabsContent>
            </Tabs>
          )}
        </main>
      </div>
    </div>
  )
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-3 bg-white rounded-lg border border-slate-200">
      <div className="text-xs text-slate-500 uppercase tracking-wide">{label}</div>
      <div className="mt-0.5 text-lg font-bold tabular-nums text-slate-900">{value}</div>
    </div>
  )
}

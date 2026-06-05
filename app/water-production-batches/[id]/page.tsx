"use client"

/**
 * Production Batch Details — read-only view (prompt #3).
 *
 * Reachable from the Production Batches list via the Eye / "View" action on
 * Draft and Approved rows alike. Shows every field the user can think to ask
 * for (batch number, shift, machine, product, output counts, raw materials
 * expected vs actual, all cost fields, totals, related stock txns, expenses,
 * and loss records).
 *
 * Loading strategy: parallel `Promise.all` of getById + 4 detail endpoints,
 * each in a per-call try/catch so a missing piece (e.g. no losses) doesn't
 * blank the whole page. Server-derived numbers (goodBags, allInCost,
 * costPerBag) come straight from the batch — no client-side math.
 */

import { useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  ArrowLeft, Loader2, Factory, Boxes, Receipt, TrendingDown, FileText,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getWaterProductionBatch, listWaterProductionBatchMaterials,
  listWaterProductionBatchLinkedExpenses, listWaterProductionBatchLinkedLosses,
  listWaterProductionBatchLinkedStockTxns,
  type WaterProductionBatch, type WaterProductionMaterialUsageRow,
  type WaterProductionLoss, type WaterProductionLinkedExpense,
  type WaterProductionLinkedStockTxn,
} from "@/lib/api/water"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-green-100 text-green-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

export default function WaterProductionBatchDetailsPage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()

  const batchId = Number(params?.id)

  const [batch, setBatch] = useState<WaterProductionBatch | null>(null)
  const [materials, setMaterials] = useState<WaterProductionMaterialUsageRow[]>([])
  const [losses, setLosses] = useState<WaterProductionLoss[]>([])
  const [expenses, setExpenses] = useState<WaterProductionLinkedExpense[]>([])
  const [stockTxns, setStockTxns] = useState<WaterProductionLinkedStockTxn[]>([])
  const [busy, setBusy] = useState(true)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") { router.replace("/dashboard"); return }
    if (!batchId || Number.isNaN(batchId)) { router.replace("/water-production-batches"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, batchId])

  async function load() {
    setBusy(true)
    try {
      // Each sub-call has its own catch — losing one shouldn't blank the page.
      const [b, mats, lossRows, expRows, txnRows] = await Promise.all([
        getWaterProductionBatch(batchId).catch((e) => { toast({ title: "Could not load batch", description: e?.message ?? String(e), variant: "destructive" }); return null }),
        listWaterProductionBatchMaterials(batchId).catch(() => []),
        listWaterProductionBatchLinkedLosses(batchId).catch(() => []),
        listWaterProductionBatchLinkedExpenses(batchId).catch(() => []),
        listWaterProductionBatchLinkedStockTxns(batchId).catch(() => []),
      ])
      setBatch(b)
      setMaterials(mats)
      setLosses(lossRows)
      setExpenses(expRows)
      setStockTxns(txnRows)
    } finally { setBusy(false) }
  }

  const totalSachets    = batch ? batch.bagsProduced * batch.sachetsPerBag : 0
  const goodBags        = batch?.goodBags ?? (batch ? batch.bagsProduced - (batch.damagedBags ?? 0) : 0)
  const allInCost       = batch?.allInCost ?? ((batch?.totalProductionCost ?? 0) + (batch?.rawMaterialCost ?? 0))
  const costPerBag      = batch?.costPerBag ?? 0
  const efficiency      = batch?.productionEfficiencyPercent ?? 0

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0 space-y-4">
          <div className="flex items-start justify-between flex-wrap gap-2">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                <Factory className="h-5 w-5 text-sky-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-semibold text-slate-900 break-words">
                  {batch?.batchNumber ?? `Batch #${batchId}`}
                </h1>
                <p className="text-xs sm:text-sm text-slate-500">
                  {batch?.productionDate ? `Produced ${batch.productionDate.split("T")[0]}` : "—"}
                  {batch?.shift && ` · ${batch.shift}`}
                  {batch?.productName && ` · ${batch.productName}`}
                </p>
              </div>
            </div>
            <Button asChild variant="outline" className="gap-2">
              <Link href="/water-production-batches">
                <ArrowLeft className="h-4 w-4" /> Back to batches
              </Link>
            </Button>
          </div>


          {busy ? (
            <div className="text-slate-500 flex items-center gap-2 p-6">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading details…
            </div>
          ) : !batch ? (
            <Card><CardContent className="p-6 text-slate-500">Batch not found.</CardContent></Card>
          ) : (
            <>
              {/* Status banner */}
              <div className="flex flex-wrap items-center gap-2">
                <Badge className={STATUS_COLORS[batch.status] ?? ""}>{batch.status}</Badge>
                {batch.machineScope === "AllMachines" && (
                  <Badge className="bg-violet-100 text-violet-800">All Machines / Combined</Badge>
                )}
                {batch.approvedBy && (
                  <span className="text-xs text-slate-500">
                    Approved by <span className="font-medium">{batch.approvedBy}</span>
                    {batch.approvedAt && ` · ${batch.approvedAt.split("T")[0]}`}
                  </span>
                )}
                {batch.createdBy && (
                  <span className="text-xs text-slate-500">
                    Created by <span className="font-medium">{batch.createdBy}</span>
                    {batch.createdAt && ` · ${batch.createdAt.split("T")[0]}`}
                  </span>
                )}
              </div>

              {/* Summary cards */}
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                <SumCard label="Produced bags" value={batch.bagsProduced.toLocaleString()} />
                <SumCard label="Good bags" value={goodBags.toLocaleString()} accent="green" />
                <SumCard label="Damaged bags" value={String(batch.damagedBags ?? 0)} accent={batch.damagedBags ? "amber" : undefined} />
                <SumCard label="Rejected sachets" value={String(batch.rejectedSachets ?? 0)} accent={batch.rejectedSachets ? "amber" : undefined} />
              </div>
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                <SumCard label="Total cost" value={gh(allInCost)} accent="indigo" />
                <SumCard label="Cost per (good) bag" value={gh(costPerBag)} />
                <SumCard label="Total sachets" value={totalSachets.toLocaleString()} />
                <SumCard label="Efficiency" value={`${efficiency.toFixed(1)}%`} />
              </div>

              {/* Batch information */}
              <Section title="Batch information" color="indigo">
                <FieldList items={[
                  ["Batch number", batch.batchNumber ?? "—"],
                  ["Production date", batch.productionDate ? batch.productionDate.split("T")[0] : "—"],
                  ["Shift", batch.shift ?? "—"],
                  ["Machine", batch.machineScope === "AllMachines" ? "All Machines / Combined" : (batch.machineName ?? "—")],
                  ["Borehole", batch.boreholeName ?? "—"],
                  ["Product", batch.productName ?? "—"],
                  ["Sachets per bag", String(batch.sachetsPerBag)],
                  ["Status", batch.status],
                ]} />
              </Section>

              {/* Costs */}
              <Section title="Costs" color="green">
                <FieldList items={[
                  ["Electricity", gh(batch.electricityCost ?? 0)],
                  ["Fuel", gh(batch.fuelCost ?? 0)],
                  ["Labor", gh(batch.laborCost ?? 0)],
                  ["Other", gh(batch.otherProductionCost ?? 0)],
                  ["Raw materials & supplies", gh(batch.rawMaterialCost ?? 0)],
                  ["Total cost", gh(allInCost), "font-semibold text-emerald-700"],
                ]} />
              </Section>

              {/* Raw materials used */}
              <Section title="Raw materials & supplies used" color="amber">
                {materials.length === 0 ? (
                  <p className="text-sm text-slate-500">No raw materials &amp; supplies recorded for this batch.</p>
                ) : (
                  <>
                    <div className="hidden lg:block overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Material</TableHead>
                            <TableHead>Unit</TableHead>
                            <TableHead className="text-right">Expected</TableHead>
                            <TableHead className="text-right">Actual</TableHead>
                            <TableHead className="text-right">Variance</TableHead>
                            <TableHead className="text-right">Unit cost</TableHead>
                            <TableHead className="text-right">Cost</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {materials.map((m) => (
                            <TableRow key={m.waterRawMaterialUsageId}>
                              <TableCell>{m.itemName ?? "—"}</TableCell>
                              <TableCell className="text-slate-500">{m.unitOfMeasure ?? "—"}</TableCell>
                              <TableCell className="text-right tabular-nums">{(m.expectedQuantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                              <TableCell className="text-right tabular-nums">{m.quantityUsed.toLocaleString(undefined, { maximumFractionDigits: 3 })}</TableCell>
                              <TableCell className={`text-right tabular-nums ${Math.abs(m.variance) > 0 ? "text-amber-700" : ""}`}>
                                {m.variance.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                              </TableCell>
                              <TableCell className="text-right tabular-nums">{m.unitCost ? gh(m.unitCost) : "—"}</TableCell>
                              <TableCell className="text-right tabular-nums">{m.totalCost ? gh(m.totalCost) : "—"}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                    <div className="lg:hidden space-y-2">
                      {materials.map((m) => (
                        <div key={m.waterRawMaterialUsageId} className="rounded-md border border-slate-200 bg-white p-3 space-y-1 text-sm">
                          <div className="font-medium text-slate-900">{m.itemName ?? "—"}</div>
                          <div className="grid grid-cols-2 gap-2 text-xs">
                            <div><span className="text-slate-500">Expected:</span> {(m.expectedQuantityUsed ?? 0).toLocaleString(undefined, { maximumFractionDigits: 3 })} {m.unitOfMeasure ?? ""}</div>
                            <div><span className="text-slate-500">Actual:</span> {m.quantityUsed.toLocaleString(undefined, { maximumFractionDigits: 3 })} {m.unitOfMeasure ?? ""}</div>
                            <div><span className="text-slate-500">Variance:</span> <span className={Math.abs(m.variance) > 0 ? "text-amber-700" : ""}>{m.variance.toLocaleString(undefined, { maximumFractionDigits: 3 })}</span></div>
                            <div className="text-right"><span className="text-slate-500">Cost:</span> <span className="font-semibold">{m.totalCost ? gh(m.totalCost) : "—"}</span></div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </>
                )}
              </Section>

              {/* Linked records — only render when populated to keep the page short. */}
              <Section title="Related inventory transactions" color="sky" icon={Boxes}>
                {stockTxns.length === 0 ? (
                  <p className="text-sm text-slate-500">None yet — batch is not Approved or stock impact has been reversed.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Product</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="text-right">Quantity</TableHead>
                          <TableHead className="text-right">Unit cost</TableHead>
                          <TableHead>Note</TableHead>
                          <TableHead>Date</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {stockTxns.map((t) => (
                          <TableRow key={t.waterStockTransactionId}>
                            <TableCell>{t.productName ?? `#${t.waterProductId}`}</TableCell>
                            <TableCell>{t.txnType ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{t.quantity.toLocaleString()}</TableCell>
                            <TableCell className="text-right tabular-nums">{t.unitCost != null ? gh(t.unitCost) : "—"}</TableCell>
                            <TableCell className="text-slate-600">{t.note ?? "—"}</TableCell>
                            <TableCell className="whitespace-nowrap">{t.createdAt.split("T")[0]}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </Section>

              <Section title="Related expense records" color="purple" icon={Receipt}>
                {expenses.length === 0 ? (
                  <p className="text-sm text-slate-500">No production-linked expenses for this batch.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Category</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead>Payment</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead>Date</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {expenses.map((e) => (
                          <TableRow key={e.waterExpenseId}>
                            <TableCell>{e.categoryName ?? "—"}</TableCell>
                            <TableCell className="max-w-[260px] truncate">{e.description ?? "—"}</TableCell>
                            <TableCell>
                              {e.paymentMethod ?? "—"}
                              {e.cashAccountName ? ` · ${e.cashAccountName}` : ""}
                            </TableCell>
                            <TableCell className="text-right tabular-nums whitespace-nowrap">{gh(e.amount)}</TableCell>
                            <TableCell>{e.status ?? "—"}</TableCell>
                            <TableCell className="whitespace-nowrap">{e.expenseDate?.split("T")[0]}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </Section>

              <Section title="Related loss records" color="rose" icon={TrendingDown}>
                {losses.length === 0 ? (
                  <p className="text-sm text-slate-500">No damage / rejected loss records for this batch.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Loss type</TableHead>
                          <TableHead className="text-right">Bags</TableHead>
                          <TableHead className="text-right">Sachets</TableHead>
                          <TableHead className="text-right">Bags value</TableHead>
                          <TableHead className="text-right">Sachets value</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {losses.map((l) => (
                          <TableRow key={l.waterProductionLossId}>
                            <TableCell className="whitespace-nowrap">{l.lossDate.split("T")[0]}</TableCell>
                            <TableCell>{l.lossType}</TableCell>
                            <TableCell className="text-right tabular-nums">{l.bagsLost.toLocaleString()}</TableCell>
                            <TableCell className="text-right tabular-nums">{l.sachetsLost.toLocaleString()}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(l.bagsLossValue)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(l.sachetsLossValue)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">{gh(l.totalValue)}</TableCell>
                            <TableCell>{l.status}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </Section>

              {batch.notes && (
                <Section title="Notes" color="slate" icon={FileText}>
                  <p className="text-sm text-slate-700 whitespace-pre-wrap">{batch.notes}</p>
                </Section>
              )}
            </>
          )}
        </main>
      </div>
    </div>
  )
}

// -----------------------------------------------------------------------------
// Small presentational helpers — kept inline because the details view is the
// only place that needs this exact shape.
// -----------------------------------------------------------------------------

function SumCard({ label, value, accent }: { label: string; value: string; accent?: "green" | "amber" | "indigo" }) {
  const valueClass =
    accent === "green"  ? "text-emerald-700" :
    accent === "amber"  ? "text-amber-700"   :
    accent === "indigo" ? "text-indigo-700"  : ""
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs uppercase tracking-wider text-slate-500">{label}</div>
        <div className={`text-lg sm:text-xl font-semibold tabular-nums mt-1 ${valueClass}`}>{value}</div>
      </CardContent>
    </Card>
  )
}

const SECTION_COLORS: Record<string, string> = {
  indigo: "bg-indigo-600",
  green:  "bg-green-600",
  amber:  "bg-amber-600",
  sky:    "bg-sky-600",
  purple: "bg-purple-600",
  rose:   "bg-rose-600",
  slate:  "bg-slate-600",
}

function Section({ title, color, icon: Icon, children }: {
  title: string
  color: keyof typeof SECTION_COLORS
  icon?: any
  children: React.ReactNode
}) {
  return (
    <div className="rounded-xl border border-slate-200 overflow-hidden bg-white">
      <div className={`${SECTION_COLORS[color]} px-4 py-2 text-sm font-semibold text-white flex items-center gap-2`}>
        {Icon && <Icon className="h-4 w-4" />} {title}
      </div>
      <div className="p-4">{children}</div>
    </div>
  )
}

function FieldList({ items }: { items: Array<[string, string, string?]> }) {
  return (
    <dl className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 text-sm">
      {items.map(([label, value, valueClass], i) => (
        <div key={i} className="min-w-0">
          <dt className="text-xs text-slate-500">{label}</dt>
          <dd className={`font-medium break-words ${valueClass ?? ""}`}>{value}</dd>
        </div>
      ))}
    </dl>
  )
}

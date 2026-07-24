"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Loader2, ArrowLeft, Undo2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { usePermissions } from "@/hooks/use-permissions"
import { FeedProductionBatchForm } from "@/components/feed-production/batch-form"
import { getFeedProductionBatch, reverseFeedProductionBatch, getFeedProductionTraceability, type FeedProductionBatch, type FeedTraceabilityRow } from "@/lib/api/poultry-feed-production"

const SOURCE_LABELS: Record<string, string> = {
  FromInventory: "From inventory",
  BoughtDuringProduction: "Bought during production",
  MixedSource: "Mixed source",
}

export default function FeedProductionBatchDetailPage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const canManage = usePermissions().featureAccess.canManageFeedProduction
  const id = Number(params?.id)

  const [loading, setLoading] = useState(true)
  const [batch, setBatch] = useState<FeedProductionBatch | null>(null)
  const [reverseOpen, setReverseOpen] = useState(false)
  const [reason, setReason] = useState("")
  const [reversing, setReversing] = useState(false)

  async function load() {
    setLoading(true)
    try {
      setBatch(await getFeedProductionBatch(id))
    } catch (e: any) {
      toast({ title: "Failed to load batch", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void load() }, [id]) // eslint-disable-line react-hooks/exhaustive-deps

  async function doReverse() {
    setReversing(true)
    try {
      await reverseFeedProductionBatch(id, reason || undefined)
      toast({ title: "Batch reversed", description: "Ingredient stock restored, produced feed removed, cash reversed." })
      setReverseOpen(false)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Failed to reverse batch", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6">
          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : !batch ? (
            <div className="p-8 text-slate-500">Batch not found.</div>
          ) : batch.status === "Draft" ? (
            <FeedProductionBatchForm existing={batch} />
          ) : (
            <ReadOnlyDetail batch={batch} gh={gh} onBack={() => router.push("/poultry-feed-production")} onReverse={batch.status === "Posted" && canManage ? () => setReverseOpen(true) : undefined} />
          )}
        </main>
      </div>

      <Dialog open={reverseOpen} onOpenChange={(v) => { if (!reversing) setReverseOpen(v) }}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Reverse this batch?</DialogTitle></DialogHeader>
          <p className="text-sm text-slate-600">This restores the ingredients consumed from inventory, removes the produced feed from stock, and reverses any cash posted. Blocked if any produced feed has already been used.</p>
          <div className="space-y-1">
            <label className="text-xs text-slate-500">Reason (optional)</label>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Why is this being reversed?" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setReverseOpen(false)} disabled={reversing}>Cancel</Button>
            <Button variant="destructive" onClick={() => void doReverse()} disabled={reversing}>
              {reversing ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Reversing…</> : <><Undo2 className="w-4 h-4 mr-1" /> Reverse Batch</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function ReadOnlyDetail({ batch, gh, onBack, onReverse }: { batch: FeedProductionBatch; gh: (n: number) => string; onBack: () => void; onReverse?: () => void }) {
  const [trace, setTrace] = useState<FeedTraceabilityRow[]>([])
  useEffect(() => {
    getFeedProductionTraceability(batch.poultryFeedProductionBatchId).then(setTrace).catch(() => setTrace([]))
  }, [batch.poultryFeedProductionBatchId])
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <Button variant="ghost" size="sm" onClick={onBack}><ArrowLeft className="w-4 h-4 mr-1" /> Back</Button>
        <h1 className="text-2xl font-bold">Batch {batch.batchNumber}</h1>
        <Badge variant={batch.status === "Posted" ? "default" : "outline"} className={cn(batch.status === "Posted" && "bg-emerald-600 hover:bg-emerald-600")}>{batch.status}</Badge>
        {onReverse && <Button variant="outline" size="sm" className="ml-auto" onClick={onReverse}><Undo2 className="w-4 h-4 mr-1" /> Reverse</Button>}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
        <Card><CardContent className="p-4 space-y-1.5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Output</div>
          <Line label="Finished feed" value={batch.finishedFeedItemName ?? "—"} />
          <Line label="Quantity" value={`${batch.quantityProduced.toLocaleString()}${batch.outputUnit ? ` ${batch.outputUnit}` : ""}`} />
          <Line label="Formula" value={batch.formulaName ?? "—"} />
          <Line label="Date" value={batch.productionDate ? new Date(batch.productionDate).toLocaleDateString() : "—"} />
        </CardContent></Card>
        <Card><CardContent className="p-4 space-y-1.5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Cost</div>
          <Line label="Ingredient cost" value={gh(batch.totalIngredientCost)} />
          <Line label="Additional cost" value={gh(batch.totalAdditionalCost)} />
          <Line label="Total production cost" value={gh(batch.totalProductionCost)} bold />
          <Line label="Cost per unit" value={gh(batch.costPerOutputUnit)} bold />
        </CardContent></Card>
        <Card><CardContent className="p-4 space-y-1.5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">Audit</div>
          <Line label="Created by" value={batch.createdBy ?? "—"} />
          <Line label="Posted" value={batch.postedAt ? new Date(batch.postedAt).toLocaleString() : "—"} />
          {batch.status === "Reversed" && <>
            <Line label="Reversed" value={batch.reversedAt ? new Date(batch.reversedAt).toLocaleString() : "—"} />
            <Line label="Reason" value={batch.reversalReason ?? "—"} />
          </>}
        </CardContent></Card>
      </div>

      <Card><CardContent className="p-4">
        <div className="text-sm font-semibold mb-2">Ingredient breakdown</div>
        <div className="overflow-x-auto">
          <Table className="min-w-[720px]">
            <TableHeader><TableRow>
              <TableHead>Ingredient</TableHead><TableHead>Source</TableHead>
              <TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Unit cost</TableHead>
              <TableHead className="text-right">Total</TableHead><TableHead>Supplier</TableHead><TableHead>Payment</TableHead>
            </TableRow></TableHeader>
            <TableBody>
              {(batch.lines ?? []).map((l) => (
                <TableRow key={l.poultryFeedProductionBatchLineId}>
                  <TableCell>{l.ingredientName}</TableCell>
                  <TableCell>{SOURCE_LABELS[l.sourceType] ?? l.sourceType}</TableCell>
                  <TableCell className="text-right tabular-nums">{l.quantityUsed.toLocaleString()}{l.unitOfMeasure ? ` ${l.unitOfMeasure}` : ""}</TableCell>
                  <TableCell className="text-right tabular-nums">{gh(l.unitCost)}</TableCell>
                  <TableCell className="text-right tabular-nums">{gh(l.totalCost)}</TableCell>
                  <TableCell>{l.supplierName ?? "—"}</TableCell>
                  <TableCell>{l.paymentStatus ?? "—"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </CardContent></Card>

      {(batch.additionalCosts ?? []).length > 0 && (
        <Card><CardContent className="p-4">
          <div className="text-sm font-semibold mb-2">Additional production costs</div>
          <div className="overflow-x-auto">
            <Table className="min-w-[560px]">
              <TableHeader><TableRow>
                <TableHead>Type</TableHead><TableHead className="text-right">Amount</TableHead>
                <TableHead>Payment</TableHead><TableHead>Payee</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {(batch.additionalCosts ?? []).map((c) => (
                  <TableRow key={c.poultryFeedProductionAdditionalCostId}>
                    <TableCell>{c.costType}</TableCell>
                    <TableCell className="text-right tabular-nums">{gh(c.amount)}</TableCell>
                    <TableCell>{c.paymentStatus ?? "—"}</TableCell>
                    <TableCell>{c.payeeName ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent></Card>
      )}

      {trace.length > 0 && (
        <Card><CardContent className="p-4">
          <div className="text-sm font-semibold mb-2">Where this feed was used (traceability)</div>
          <div className="overflow-x-auto">
            <Table className="min-w-[560px]">
              <TableHeader><TableRow>
                <TableHead>Used date</TableHead><TableHead>Production record</TableHead>
                <TableHead className="text-right">Qty used</TableHead><TableHead className="text-right">Unit cost</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {trace.map((t) => (
                  <TableRow key={t.poultryRawMaterialUsageId}>
                    <TableCell>{t.usedDate ? new Date(t.usedDate).toLocaleDateString() : "—"}</TableCell>
                    <TableCell>{t.productionRecordId ? `Record #${t.productionRecordId}` : "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">{t.quantityDrawn.toLocaleString()}</TableCell>
                    <TableCell className="text-right tabular-nums">{gh(t.unitCostAtDraw)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent></Card>
      )}
    </div>
  )
}

function Line({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className={cn("flex justify-between text-sm gap-4", bold && "font-semibold text-slate-900")}>
      <span className={cn("shrink-0", !bold && "text-slate-600")}>{label}</span>
      <span className="tabular-nums text-right truncate">{value}</span>
    </div>
  )
}

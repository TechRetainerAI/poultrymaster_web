"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useToast } from "@/hooks/use-toast"
import { ArrowLeft, Scale, RotateCcw } from "lucide-react"
import { getUserContext } from "@/lib/utils/user-context"
import {
  getBatchProductionRecord,
  reverseBatchProduction,
  batchNameLabel,
  batchScopeLabel,
  BATCH_STATUS_LABELS,
  type ProductionBatchRecord,
} from "@/lib/api/production-batch"

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="font-medium">{value}</div>
    </div>
  )
}

export default function BatchProductionDetailPage() {
  const router = useRouter()
  const params = useParams()
  const id = Number(params?.id)
  const { toast } = useToast()
  const [batch, setBatch] = useState<ProductionBatchRecord | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)

  async function load() {
    const { farmId } = getUserContext()
    setLoading(true)
    const res = await getBatchProductionRecord(id, farmId)
    if (res.success && res.data) setBatch(res.data)
    else toast({ title: "Could not load record", description: res.message, variant: "destructive" })
    setLoading(false)
  }

  useEffect(() => {
    if (Number.isFinite(id)) load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id])

  async function handleReverse() {
    if (!batch) return
    if (!confirm("Reverse this posted batch? The generated flock records, inventory and bird changes will be undone.")) return
    const { userId, farmId } = getUserContext()
    setBusy(true)
    const res = await reverseBatchProduction(batch.id, farmId, userId)
    setBusy(false)
    if (res.success) {
      toast({ title: "Batch reversed" })
      load()
    } else {
      toast({ title: "Reverse failed", description: res.message, variant: "destructive" })
    }
  }

  const handleLogout = () => {
    localStorage.clear()
    router.push("/login")
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-[1200px] mx-auto">
            <div className="flex items-center justify-between mb-4 gap-3 flex-wrap">
              <div className="flex items-center gap-3">
                <Button variant="ghost" size="sm" onClick={() => router.push("/batch-production-records")}>
                  <ArrowLeft className="h-4 w-4 mr-1" /> Back
                </Button>
                {batch && (
                  <div>
                    <h1 className="text-xl font-semibold">{batchNameLabel(batch)}</h1>
                    <p className="text-sm text-muted-foreground">{batchScopeLabel(batch)}</p>
                  </div>
                )}
              </div>
              {batch && (
                <div className="flex items-center gap-2">
                  <Badge variant="outline">{BATCH_STATUS_LABELS[batch.status]}</Badge>
                  {["PendingAllocation", "Allocated"].includes(batch.status) && (
                    <Button size="sm" onClick={() => router.push(`/batch-production-records/${batch.id}/allocate`)}>
                      <Scale className="h-4 w-4 mr-1" /> Allocation
                    </Button>
                  )}
                  {batch.status === "Posted" && (
                    <Button size="sm" variant="destructive" onClick={handleReverse} disabled={busy}>
                      <RotateCcw className="h-4 w-4 mr-1" /> Reverse
                    </Button>
                  )}
                </div>
              )}
            </div>

            {loading && <div className="text-sm text-muted-foreground py-16 text-center">Loading…</div>}

            {!loading && batch && (
              <div className="space-y-4">
                <Card>
                  <CardHeader><CardTitle className="text-base">Batch totals</CardTitle></CardHeader>
                  <CardContent className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-6 gap-4">
                    <Field label="Date" value={new Date(batch.productionDate).toLocaleDateString()} />
                    <Field label="Age" value={batch.batchSelectionType === "SpecificBatch" ? batch.ageDisplay || "—" : "N/A"} />
                    <Field label="1st Pick" value={batch.firstPickTotal} />
                    <Field label="2nd Pick" value={batch.secondPickTotal} />
                    <Field label="3rd Pick" value={batch.thirdPickTotal} />
                    <Field label="4th Pick" value={batch.fourthPickTotal} />
                    <Field label="Broken" value={batch.brokenEggs ?? 0} />
                    <Field label="Meaty" value={batch.meatyEggs ?? 0} />
                    <Field label="Soft" value={batch.softEggs ?? 0} />
                    <Field label="Lost" value={batch.lostEggs ?? 0} />
                    <Field label="Total Eggs" value={batch.totalEggs} />
                    <Field label="Deaths" value={batch.deaths} />
                    <Field label="Feed (kg)" value={batch.feedKg ?? 0} />
                    <Field label="Birds Left" value={batch.birdsLeft ?? "—"} />
                    <Field label="Feed Cost" value={(batch.totalFeedCost ?? 0).toFixed(2)} />
                    <Field label="Med Cost" value={(batch.totalMedicationCost ?? 0).toFixed(2)} />
                    <Field label="Total Cost" value={(batch.totalCostOfProduction ?? 0).toFixed(2)} />
                  </CardContent>
                </Card>

                {(batch.feeds.length > 0 || batch.medications.length > 0) && (
                  <Card>
                    <CardHeader><CardTitle className="text-base">Feed & medication lines</CardTitle></CardHeader>
                    <CardContent className="grid gap-1 text-sm">
                      {batch.feeds.map((f) => (
                        <div key={`f-${f.itemId}`} className="flex justify-between border-b py-1">
                          <span>{f.itemName || `Item ${f.itemId}`} (feed)</span>
                          <span>{f.qty} @ {(f.unitCost ?? 0).toFixed(2)} = {(f.totalCost ?? 0).toFixed(2)}</span>
                        </div>
                      ))}
                      {batch.medications.map((m) => (
                        <div key={`m-${m.itemId}`} className="flex justify-between border-b py-1">
                          <span>{m.itemName || `Item ${m.itemId}`} (med)</span>
                          <span>{m.qty} @ {(m.unitCost ?? 0).toFixed(2)} = {(m.totalCost ?? 0).toFixed(2)}</span>
                        </div>
                      ))}
                    </CardContent>
                  </Card>
                )}

                {batch.allocations.length > 0 && (
                  <Card>
                    <CardHeader><CardTitle className="text-base">Allocation ({batch.allocations.length} flocks)</CardTitle></CardHeader>
                    <CardContent className="overflow-x-auto">
                      <Table className="min-w-[720px]">
                        <TableHeader>
                          <TableRow>
                            <TableHead>Flock</TableHead>
                            <TableHead className="text-right">1st</TableHead>
                            <TableHead className="text-right">2nd</TableHead>
                            <TableHead className="text-right">3rd</TableHead>
                            <TableHead className="text-right">4th</TableHead>
                            <TableHead className="text-right">Broken</TableHead>
                            <TableHead className="text-right">Total</TableHead>
                            <TableHead className="text-right">Deaths</TableHead>
                            <TableHead className="text-right">Egg %</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {batch.allocations.map((a) => (
                            <TableRow key={a.id ?? a.flockId}>
                              <TableCell className="font-medium">{a.flockName || `Flock ${a.flockId}`}</TableCell>
                              <TableCell className="text-right">{a.firstPickEggs}</TableCell>
                              <TableCell className="text-right">{a.secondPickEggs}</TableCell>
                              <TableCell className="text-right">{a.thirdPickEggs}</TableCell>
                              <TableCell className="text-right">{a.fourthPickEggs}</TableCell>
                              <TableCell className="text-right">{a.brokenEggs ?? 0}</TableCell>
                              <TableCell className="text-right font-medium">{a.totalEggs}</TableCell>
                              <TableCell className="text-right">{a.deaths}</TableCell>
                              <TableCell className="text-right text-muted-foreground">{(a.eggPercentage ?? 0).toFixed(1)}%</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </CardContent>
                  </Card>
                )}

                {batch.notes && (
                  <Card>
                    <CardHeader><CardTitle className="text-base">Notes</CardTitle></CardHeader>
                    <CardContent className="text-sm whitespace-pre-wrap">{batch.notes}</CardContent>
                  </Card>
                )}
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

"use client"

import React, { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, ArrowLeft, Layers, Pencil, ExternalLink } from "lucide-react"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getWaterDailyProduction, WATER_DAILY_PRODUCTION_STATUS_LABELS, waterMachineScopeLabel,
  type WaterDailyProduction,
} from "@/lib/api/water"

const STATUS_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  PendingAllocation: "bg-amber-100 text-amber-800",
  Allocated: "bg-blue-100 text-blue-700",
  Posted: "bg-emerald-100 text-emerald-700",
  Reversed: "bg-purple-100 text-purple-700",
  Cancelled: "bg-red-100 text-red-700",
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <div className="text-xs text-slate-500">{label}</div>
      <div className="text-sm font-medium text-slate-900 tabular-nums">{value}</div>
    </div>
  )
}

export default function WaterDailyProductionDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [d, setD] = useState<WaterDailyProduction | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    ;(async () => {
      try { setD(await getWaterDailyProduction(id)) }
      catch (e: any) {
        toast({ title: "Failed to load the record", description: e?.message ?? String(e), variant: "destructive" })
        router.replace("/water-daily-production")
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  if (loading || !d) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="p-6 flex items-center gap-2 text-slate-500">
            <Loader2 className="w-4 h-4 animate-spin" /> Loading…
          </main>
        </div>
      </div>
    )
  }

  const canAllocate = ["PendingAllocation", "Allocated", "Reversed"].includes(d.status)
  const canEdit = !["Posted", "Cancelled"].includes(d.status)

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0 space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => router.push("/water-daily-production")}>
              <ArrowLeft className="w-4 h-4 mr-1" /> Back
            </Button>
            <h1 className="text-xl sm:text-2xl font-semibold text-slate-900">
              {d.productionNumber || `Batch #${d.waterDailyProductionId}`}
            </h1>
            <Badge variant="outline" className={cn("border-0", STATUS_BADGE[d.status])}>
              {WATER_DAILY_PRODUCTION_STATUS_LABELS[d.status] ?? d.status}
            </Badge>
            <div className="ml-auto flex gap-2">
              {canEdit && (
                <Button variant="outline" size="sm" asChild>
                  <Link href={`/water-daily-production/${id}/edit`}><Pencil className="w-4 h-4 mr-1" /> Edit</Link>
                </Button>
              )}
              {canAllocate && (
                <Button size="sm" asChild>
                  <Link href={`/water-daily-production/${id}/allocate`}><Layers className="w-4 h-4 mr-1" /> Allocation</Link>
                </Button>
              )}
            </div>
          </div>

          <Card>
            <CardContent className="p-4 grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-6 gap-4">
              <Field label="Date" value={(d.productionDate || "").slice(0, 10)} />
              <Field label="Shift" value={d.shift} />
              <Field label="Product" value={d.productName ?? "—"} />
              <Field label="Borehole" value={d.boreholeName ?? "—"} />
              <Field label="Machines" value={waterMachineScopeLabel(d)} />
              <Field label="Posting version" value={d.postingVersion} />
              <Field label="Bags produced" value={(d.bagsProduced || 0).toLocaleString()} />
              <Field label="Sachets per bag" value={d.sachetsPerBag} />
              <Field label="Loose sachets" value={(d.looseSachetsProduced || 0).toLocaleString()} />
              <Field label="Rejected" value={(d.rejectedSachets || 0).toLocaleString()} />
              <Field label="Damaged bags" value={(d.damagedBags || 0).toLocaleString()} />
              <Field label="Good bags" value={(d.goodBags || 0).toLocaleString()} />
              <Field label="Packaging rolls" value={(d.packagingRollsUsed || 0).toLocaleString()} />
              <Field label="Water used (L)" value={d.estimatedWaterUsedLitres?.toLocaleString() ?? "—"} />
              <Field label="Production cost" value={gh(d.totalProductionCost || 0)} />
              <Field label="Material cost" value={gh(d.rawMaterialCost || 0)} />
              <Field label="All-in cost" value={gh(d.allInCost || 0)} />
              <Field label="Cost / good bag" value={gh(d.costPerBag || 0)} />
            </CardContent>
          </Card>

          {(d.materials?.length ?? 0) > 0 && (
            <Card>
              <CardContent className="p-0">
                <div className="p-3 text-sm font-semibold text-slate-700">Raw materials used (day total)</div>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Material</TableHead>
                      <TableHead className="text-right">Used</TableHead>
                      <TableHead className="text-right">Expected</TableHead>
                      <TableHead className="text-right">Variance</TableHead>
                      <TableHead className="text-right">Cost</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {d.materials.map((m) => {
                      const variance = m.expectedQuantityUsed != null ? m.quantityUsed - m.expectedQuantityUsed : null
                      return (
                        <TableRow key={m.waterDailyProductionMaterialId ?? m.waterRawMaterialItemId}>
                          <TableCell>{m.itemName}{m.unitOfMeasure ? ` (${m.unitOfMeasure})` : ""}</TableCell>
                          <TableCell className="text-right tabular-nums">{m.quantityUsed.toLocaleString()}</TableCell>
                          <TableCell className="text-right tabular-nums">{m.expectedQuantityUsed?.toLocaleString() ?? "—"}</TableCell>
                          <TableCell className={cn("text-right tabular-nums", variance != null && variance > 0 && "text-amber-700")}>
                            {variance == null ? "—" : variance > 0 ? `+${variance.toFixed(3)}` : variance.toFixed(3)}
                          </TableCell>
                          <TableCell className="text-right tabular-nums">{gh(m.totalCost ?? 0)}</TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}

          {(d.allocations?.length ?? 0) > 0 && (
            <Card>
              <CardContent className="p-0">
                <div className="p-3 text-sm font-semibold text-slate-700">
                  Allocation — {d.allocations.length} machine{d.allocations.length === 1 ? "" : "s"}
                </div>
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Machine</TableHead>
                        <TableHead className="text-right">Bags</TableHead>
                        <TableHead className="text-right">Rejected</TableHead>
                        <TableHead className="text-right">Damaged</TableHead>
                        <TableHead className="text-right">Prod. cost</TableHead>
                        <TableHead className="text-right">Material cost</TableHead>
                        <TableHead>Production</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {d.allocations.map((a) => (
                        <TableRow key={a.waterDailyProductionAllocationId ?? a.waterMachineId}>
                          <TableCell className="font-medium">{a.machineName}</TableCell>
                          <TableCell className="text-right tabular-nums">{a.bagsProduced.toLocaleString()}</TableCell>
                          <TableCell className="text-right tabular-nums">{a.rejectedSachets.toLocaleString()}</TableCell>
                          <TableCell className="text-right tabular-nums">{a.damagedBags.toLocaleString()}</TableCell>
                          <TableCell className="text-right tabular-nums">{gh(a.totalProductionCost ?? 0)}</TableCell>
                          <TableCell className="text-right tabular-nums">{gh(a.rawMaterialCost ?? 0)}</TableCell>
                          <TableCell className="text-xs">
                            {a.generatedWaterProductionBatchId ? (
                              <Link href={`/water-production-batches/${a.generatedWaterProductionBatchId}`}
                                    className="text-sky-600 hover:underline inline-flex items-center gap-1">
                                {a.generatedBatchNumber} <ExternalLink className="w-3 h-3" />
                              </Link>
                            ) : a.generatedBatchNumber ? (
                              <span className="text-slate-400 line-through">{a.generatedBatchNumber}</span>
                            ) : <span className="text-slate-400">—</span>}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </CardContent>
            </Card>
          )}

          {(d.postings?.length ?? 0) > 0 && (
            <Card>
              <CardContent className="p-0">
                <div className="p-3 text-sm font-semibold text-slate-700">Posting history</div>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Version</TableHead>
                      <TableHead>Production</TableHead>
                      <TableHead>Posted</TableHead>
                      <TableHead>Reversed</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {d.postings.map((p) => (
                      <TableRow key={p.waterDailyProductionPostingId}>
                        <TableCell>v{p.postingVersion}</TableCell>
                        <TableCell className="font-mono text-xs">{p.batchNumber}</TableCell>
                        <TableCell className="text-xs text-slate-600">{p.postedAt?.slice(0, 19).replace("T", " ") ?? "—"}</TableCell>
                        <TableCell className="text-xs text-slate-600">
                          {p.reversedAt ? p.reversedAt.slice(0, 19).replace("T", " ") : <span className="text-emerald-600">live</span>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}

          {d.notes && (
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500 mb-1">Notes</div>
              <div className="text-sm whitespace-pre-wrap text-slate-800">{d.notes}</div>
            </CardContent></Card>
          )}
        </main>
      </div>
    </div>
  )
}

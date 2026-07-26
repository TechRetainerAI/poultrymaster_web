"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Plus, Loader2, Eye, Pencil, Trash2, FlaskConical, Factory, BarChart3 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { usePermissions } from "@/hooks/use-permissions"
import {
  listFeedProductionBatches, deleteFeedProductionBatch,
  type FeedProductionBatch, type FeedProductionStatus,
} from "@/lib/api/poultry-feed-production"

const STATUS_BADGE: Record<FeedProductionStatus, { variant: "secondary" | "outline" | "default"; className?: string }> = {
  Draft: { variant: "secondary" },
  Posted: { variant: "default", className: "bg-emerald-600 hover:bg-emerald-600" },
  Reversed: { variant: "outline", className: "text-slate-500" },
}

export default function PoultryFeedProductionPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const { featureAccess } = usePermissions()
  const canManage = featureAccess.canManageFeedProduction
  const showCost = featureAccess.canViewFeedProductionCost

  const [loading, setLoading] = useState(true)
  const [batches, setBatches] = useState<FeedProductionBatch[]>([])
  const [search, setSearch] = useState("")
  const [statusFilter, setStatusFilter] = useState<"all" | FeedProductionStatus>("all")
  const [deleteTarget, setDeleteTarget] = useState<FeedProductionBatch | null>(null)

  async function load() {
    setLoading(true)
    try {
      setBatches(await listFeedProductionBatches())
    } catch (e: any) {
      toast({ title: "Failed to load feed production batches", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void load() }, [])

  const filtered = useMemo(() => {
    let rows = filterByDateAndSearch(batches, { search, searchKeys: ["batchNumber", "finishedFeedItemName", "formulaName"] })
    if (statusFilter !== "all") rows = rows.filter((b) => b.status === statusFilter)
    return rows
  }, [batches, search, statusFilter])

  const stats = useMemo(() => {
    const posted = batches.filter((b) => b.status === "Posted")
    return {
      count: batches.length,
      producedValue: posted.reduce((s, b) => s + b.totalProductionCost, 0),
      drafts: batches.filter((b) => b.status === "Draft").length,
    }
  }, [batches])

  async function doDelete() {
    if (!deleteTarget) return
    try {
      await deleteFeedProductionBatch(deleteTarget.poultryFeedProductionBatchId)
      toast({ title: "Batch deleted" })
      setDeleteTarget(null)
      await load()
    } catch (e: any) {
      toast({ title: "Failed to delete", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h1 className="text-2xl font-bold">Feed Production</h1>
              <p className="text-sm text-slate-500">Produce finished feed from ingredients — with full costing, inventory and cash impact.</p>
            </div>
            <div className="flex flex-wrap items-center gap-2 self-start sm:ml-auto">
              {showCost && <Button variant="outline" onClick={() => router.push("/poultry-feed-production/reports")}><BarChart3 className="w-4 h-4 mr-1" /> Reports</Button>}
              <Button variant="outline" onClick={() => router.push("/poultry-feed-formulas")}><FlaskConical className="w-4 h-4 mr-1" /> Feed Formulas</Button>
              {canManage && <Button onClick={() => router.push("/poultry-feed-production/new")}><Plus className="w-4 h-4 mr-1" /> New Batch</Button>}
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : (
            <>
              <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
                <Stat icon={<Factory className="w-4 h-4 text-blue-600" />} label="Batches" value={stats.count.toLocaleString()} />
                <Stat icon={<Factory className="w-4 h-4 text-amber-600" />} label="Drafts" value={stats.drafts.toLocaleString()} />
                {showCost && <Stat icon={<Factory className="w-4 h-4 text-emerald-600" />} label="Produced value (posted)" value={gh(stats.producedValue)} />}
              </div>

              <Card><CardContent className="p-4">
                <div className="mb-3"><ListFilters search={search} setSearch={setSearch} searchPlaceholder="Search batch, feed or formula" extras={
                  <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as any)}>
                    <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All statuses</SelectItem>
                      <SelectItem value="Draft">Draft</SelectItem>
                      <SelectItem value="Posted">Posted</SelectItem>
                      <SelectItem value="Reversed">Reversed</SelectItem>
                    </SelectContent>
                  </Select>
                } /></div>

                <div className="overflow-x-auto">
                  <Table className="min-w-[900px]">
                    <TableHeader>
                      <TableRow>
                        <TableHead>Batch #</TableHead>
                        <TableHead>Date</TableHead>
                        <TableHead>Finished Feed</TableHead>
                        <TableHead className="text-right">Qty</TableHead>
                        {showCost && <>
                          <TableHead className="text-right">Ingredient Cost</TableHead>
                          <TableHead className="text-right">Add. Cost</TableHead>
                          <TableHead className="text-right">Total Cost</TableHead>
                          <TableHead className="text-right">Cost/Unit</TableHead>
                        </>}
                        <TableHead className="text-center">Status</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filtered.length === 0 ? (
                        <TableRow><TableCell colSpan={showCost ? 10 : 6} className="text-center text-slate-400 py-8">No feed production batches yet.</TableCell></TableRow>
                      ) : filtered.map((b) => {
                        const badge = STATUS_BADGE[b.status]
                        return (
                          <TableRow key={b.poultryFeedProductionBatchId} className="cursor-pointer" onClick={() => router.push(`/poultry-feed-production/${b.poultryFeedProductionBatchId}`)}>
                            <TableCell className="font-medium">{b.batchNumber}</TableCell>
                            <TableCell>{b.productionDate ? new Date(b.productionDate).toLocaleDateString() : "—"}</TableCell>
                            <TableCell>{b.finishedFeedItemName ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{b.quantityProduced.toLocaleString()}{b.outputUnit ? ` ${b.outputUnit}` : ""}</TableCell>
                            {showCost && <>
                              <TableCell className="text-right tabular-nums">{gh(b.totalIngredientCost)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(b.totalAdditionalCost)}</TableCell>
                              <TableCell className="text-right tabular-nums font-medium">{gh(b.totalProductionCost)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(b.costPerOutputUnit)}</TableCell>
                            </>}
                            <TableCell className="text-center"><Badge variant={badge.variant} className={badge.className}>{b.status}</Badge></TableCell>
                            <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                              <div className="flex justify-end gap-1">
                                <Button variant="ghost" size="sm" onClick={() => router.push(`/poultry-feed-production/${b.poultryFeedProductionBatchId}`)}><Eye className="w-4 h-4" /></Button>
                                {(b.status === "Draft" || b.status === "Reversed") && canManage && <>
                                  <Button variant="ghost" size="sm" onClick={() => router.push(`/poultry-feed-production/${b.poultryFeedProductionBatchId}`)}><Pencil className="w-4 h-4" /></Button>
                                  <Button variant="ghost" size="sm" onClick={() => setDeleteTarget(b)}><Trash2 className="w-4 h-4 text-red-600" /></Button>
                                </>}
                              </div>
                            </TableCell>
                          </TableRow>
                        )
                      })}
                    </TableBody>
                  </Table>
                </div>
              </CardContent></Card>
            </>
          )}
        </main>
      </div>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
        onConfirm={() => void doDelete()}
        title="Delete batch?"
        description={deleteTarget ? `Batch ${deleteTarget.batchNumber} will be permanently removed.` : ""}
      />
    </div>
  )
}

function Stat({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
      <div className="flex items-center gap-1.5 text-xs font-medium text-slate-500 uppercase tracking-wide">{icon} {label}</div>
      <div className="mt-1 text-2xl font-bold text-slate-900 tabular-nums">{value}</div>
    </div>
  )
}

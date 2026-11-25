"use client"

// "Project / Contract" box for a transaction that is already saved (a sale,
// purchase, expense, owner entry ...). Shows which projects it belongs to,
// lets an authorised user move or split it, and shows every earlier change.
// Moving a transaction never creates, edits or re-posts it -- the company's
// books do not change, only which project the amount is reported under.

import { useCallback, useEffect, useState } from "react"
import { Briefcase, History, Pencil, Split } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { usePermissions } from "@/hooks/use-permissions"
import {
  getAllocations, reassignDocument, setSplit, type AllocationView, type CostClass, type ProjectSplit,
} from "@/lib/api/generic-projects"
import { ProjectPicker, GENERAL_LABEL } from "./project-picker"
import { ProjectSplitEditor } from "./project-split-editor"

export interface AssignableLine {
  lineId: number
  description: string
  quantity?: number | null
  amount: number
  unit?: string | null
}

type DocType = "Sale" | "Purchase" | "Expense" | "OwnerEntry" | "Loan" | "PayrollRun" | "CapitalAsset" | "CustomerPayment" | "SupplierPayment"

export function ProjectAssignmentCard({
  documentType, documentId, lines, amount, title = "Project / Contract", note,
}: {
  documentType: DocType
  documentId: number
  /** Sales and purchases: their lines, so each can be split on its own. */
  lines?: AssignableLine[]
  /** Non-line documents: the amount, for splitting by amount. */
  amount?: number
  title?: string
  note?: string
}) {
  const { enabled } = useProjectsEnabled()
  const { can } = usePermissions() as any
  const { toast } = useToast()
  const [view, setView] = useState<AllocationView | null>(null)
  const [moveOpen, setMoveOpen] = useState(false)
  const [target, setTarget] = useState<number | null>(null)
  const [reason, setReason] = useState("")
  const [splitLine, setSplitLine] = useState<AssignableLine | null>(null)
  const [splitDoc, setSplitDoc] = useState(false)
  const [showHistory, setShowHistory] = useState(false)
  const isLineDoc = documentType === "Sale" || documentType === "Purchase"
  const sourceType = documentType === "Sale" ? "SaleLine" : documentType === "Purchase" ? "PurchaseLine" : documentType

  const canChange = typeof can === "function" ? (can("generic.project-allocations.edit") || can("generic.project-allocations.create")) : true

  const load = useCallback(async () => {
    try { setView(await getAllocations(documentType, documentId)) } catch { setView(null) }
  }, [documentType, documentId])

  useEffect(() => { void load() }, [load])

  // Nothing to show for a company that never used projects.
  if (!enabled && (!view || view.history.length === 0)) return null

  const activeFor = (lineId: number | null) => view?.active.filter((a) => (a.lineId ?? null) === lineId) ?? []
  const describe = (rows: AllocationView["active"]) =>
    rows.length === 0 ? GENERAL_LABEL
      : rows.map((r) => (r.share >= 0.999999 ? r.projectLabel : `${r.projectLabel} (${Math.round(r.share * 1000) / 10}%)`)).join(", ")

  const move = async () => {
    try {
      setView(await reassignDocument(documentType, documentId, target, reason || undefined))
      toast({ title: "Project changed", description: "Only the project attribution changed. The transaction and its cash are untouched." })
      setMoveOpen(false)
      setReason("")
    } catch (e: any) {
      toast({ title: "Could not change the project", description: e?.message, variant: "destructive" })
    }
  }

  const saveSplit = async (lineId: number | null, splits: ProjectSplit[]) => {
    try {
      setView(await setSplit(sourceType, documentId, lineId, splits, reason || "Split changed"))
      toast({ title: "Split saved" })
    } catch (e: any) {
      toast({ title: "Could not save the split", description: e?.message, variant: "destructive" })
      throw e
    }
  }

  const current = isLineDoc ? view?.active ?? [] : activeFor(null)
  const projectIds = [...new Set(current.map((a) => a.projectId))]

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="flex items-center gap-2 text-base"><Briefcase className="h-4 w-4" /> {title}</CardTitle>
        <div className="flex gap-2">
          {(view?.history.length ?? 0) > 0 && (
            <Button variant="ghost" size="sm" onClick={() => setShowHistory((v) => !v)}><History className="mr-1 h-4 w-4" />History</Button>
          )}
          {enabled && canChange && (
            <Button variant="outline" size="sm" onClick={() => { setTarget(projectIds.length === 1 ? projectIds[0] : null); setMoveOpen(true) }}>
              <Pencil className="mr-1 h-4 w-4" /> Change
            </Button>
          )}
          {enabled && canChange && !isLineDoc && (amount ?? 0) > 0 && (
            <Button variant="outline" size="sm" onClick={() => setSplitDoc(true)}><Split className="mr-1 h-4 w-4" /> Split</Button>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">
        {!isLineDoc && <p className="text-slate-800">{describe(activeFor(null))}</p>}
        {isLineDoc && lines && lines.map((l) => (
          <div key={l.lineId} className="flex items-center justify-between gap-3 rounded border border-slate-100 px-3 py-2">
            <div className="min-w-0">
              <div className="truncate font-medium text-slate-800">{l.description}</div>
              <div className="truncate text-xs text-slate-500">{describe(activeFor(l.lineId))}</div>
            </div>
            {enabled && canChange && (
              <Button variant="ghost" size="sm" onClick={() => setSplitLine(l)}><Split className="mr-1 h-4 w-4" />Split</Button>
            )}
          </div>
        ))}
        {note && <p className="text-xs text-slate-500">{note}</p>}
        {showHistory && view && (
          <div className="mt-2 max-h-56 overflow-auto rounded border border-slate-100">
            <table className="w-full text-xs">
              <thead className="bg-slate-50 text-slate-500"><tr><th className="p-2 text-left">When</th><th className="p-2 text-left">Project</th><th className="p-2 text-right">Share</th><th className="p-2 text-left">Status</th><th className="p-2 text-left">Why</th></tr></thead>
              <tbody>
                {view.history.map((h, i) => (
                  <tr key={i} className="border-t border-slate-100">
                    <td className="p-2">{new Date(h.createdAt).toLocaleString()}<div className="text-slate-400">{h.createdBy}</div></td>
                    <td className="p-2">{h.projectLabel}{h.lineId ? <span className="text-slate-400"> · line {h.lineId}</span> : null}</td>
                    <td className="p-2 text-right">{Math.round(h.share * 1000) / 10}%</td>
                    <td className="p-2">{h.status === "Active" ? "Current" : `Replaced ${h.supersededAt ? new Date(h.supersededAt).toLocaleDateString() : ""}`}</td>
                    <td className="p-2">{h.supersededReason ?? h.reason ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>

      <Dialog open={moveOpen} onOpenChange={setMoveOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Change project</DialogTitle>
            <DialogDescription>
              Moves the whole {documentType === "OwnerEntry" ? "owner entry" : documentType.toLowerCase()} to another project (or to General company activity).
              Nothing is re-posted: company totals and cash stay exactly as they are. The change is kept in the history.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1"><Label>Belongs to</Label><ProjectPicker value={target} onChange={setTarget} /></div>
            <div className="space-y-1"><Label>Why (kept in the history)</Label>
              <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. recorded against the wrong contract" /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setMoveOpen(false)}>Cancel</Button>
            <Button onClick={move}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {splitLine && (
        <ProjectSplitEditor open={!!splitLine} onOpenChange={(v) => !v && setSplitLine(null)}
          title={`Split: ${splitLine.description}`} wholeQuantity={splitLine.quantity} wholeAmount={splitLine.amount} unit={splitLine.unit}
          initial={activeFor(splitLine.lineId).map((a) => ({ projectId: a.projectId, share: a.share, costClass: a.costClass }))}
          onSave={(s) => saveSplit(splitLine.lineId, s)} />
      )}
      {splitDoc && (
        <ProjectSplitEditor open={splitDoc} onOpenChange={setSplitDoc} title="Split between projects"
          wholeAmount={amount ?? 0} showCostClass={documentType === "Expense"}
          initialCostClass={(activeFor(null)[0]?.costClass as CostClass) ?? "Direct"}
          initial={activeFor(null).map((a) => ({ projectId: a.projectId, share: a.share, costClass: a.costClass }))}
          onSave={(s) => saveSplit(null, s)} />
      )}
    </Card>
  )
}

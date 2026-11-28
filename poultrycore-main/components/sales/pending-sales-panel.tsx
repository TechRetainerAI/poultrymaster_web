"use client"

// =============================================================================
// Poultry sales sent for approval (migration 527), shown as rows at the top of
// the Sales page's Recent Sales table.
//
// A sale recorded by someone who may not approve sales is not posted: it waits,
// exactly as it was entered. Nothing about it -- stock, eggs, cash, customer
// balance, reports -- exists until it is approved, so these rows never feed the
// table's totals, export, Pay, Reverse or Invoice.
//
//   Approve   posts it as an ordinary sale (as the person who entered it)
//   Reject    with a reason; the person can edit it and send it again
//   Edit      opens the sale form on it (whoever entered it, or an approver)
//   Withdraw  the person who entered it changed their mind
// =============================================================================

import { useState } from "react"
import { Check, Loader2, Pencil, Undo2, X, ShieldCheck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import { cn } from "@/lib/utils"
import {
  approvePendingSale, rejectPendingSale, withdrawPendingSale, setSaleApproval,
  type PendingSale, type SaleApprovalInfo,
} from "@/lib/api/sale"

/** Read a field of the stored request whichever case the server wrote it in. */
export function pendingField(p: PendingSale, key: string): any {
  const b = p.payload ?? {}
  return b[key] ?? b[key.charAt(0).toUpperCase() + key.slice(1)]
}

export function PendingStatusBadge({ row }: { row: PendingSale }) {
  return (
    <div className="max-w-[220px] whitespace-normal">
      {row.status === "Rejected" ? (
        <Badge variant="outline" className="border-red-300 bg-red-50 text-red-700">Rejected</Badge>
      ) : row.status === "Withdrawn" ? (
        <Badge variant="outline" className="border-slate-300 text-slate-500">Withdrawn</Badge>
      ) : row.status === "Approved" ? (
        <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-800">Approved · {row.postedSaleLabel ?? `S${row.postedSaleId}`}</Badge>
      ) : (
        <Badge variant="outline" className="border-amber-300 bg-amber-50 text-amber-800">
          {row.status === "Approving" ? "Being approved…" : "Waiting approval"}
        </Badge>
      )}
      {row.status === "Rejected" && row.rejectionReason && (
        <div className="mt-1 text-xs text-red-700 no-underline">“{row.rejectionReason}”{row.decidedByName ? ` · ${row.decidedByName}` : ""}</div>
      )}
      {(row.status === "Waiting" || row.status === "Approving") && row.lastError && (
        <div className="mt-1 text-xs text-red-700">Last approval failed: {row.lastError}</div>
      )}
      {row.submittedByName && <div className="mt-0.5 text-xs text-slate-500">by {row.submittedByName}</div>}
    </div>
  )
}

/** Approve / Reject / Edit / Withdraw for one waiting sale. */
export function PendingSaleActions({ row, info, onEdit, onChanged, labelled = false }: {
  row: PendingSale
  info: SaleApprovalInfo | null
  onEdit: (row: PendingSale) => void
  /** Something changed; `posted` = a sale was approved, so the sales list changed too. */
  onChanged: (posted: boolean) => void
  /** Full-width labelled buttons (mobile cards) instead of the compact row. */
  labelled?: boolean
}) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [rejecting, setRejecting] = useState(false)
  const [reason, setReason] = useState("")
  const me = getUserContext().userId
  const isApprover = !!info?.isApprover
  const open = row.status === "Waiting" || row.status === "Rejected"
  const mayChange = open && (row.submittedBy === me || isApprover)

  const run = async (fn: () => Promise<void>) => {
    setBusy(true)
    try { await fn() } finally { setBusy(false) }
  }

  const approve = () => run(async () => {
    try {
      const res = await approvePendingSale(getUserContext().farmId, row.pendingSaleId)
      toast({ title: `Sale ${res.saleLabel} posted`, description: "Approved. Stock, cash and the customer's balance are updated." })
      onChanged(true)
    } catch (e: any) {
      toast({ title: "Not approved", description: e?.message ?? "The sale could not be posted.", variant: "destructive" })
      onChanged(false)
    }
  })

  const reject = () => run(async () => {
    try {
      await rejectPendingSale(getUserContext().farmId, row.pendingSaleId, reason.trim())
      toast({ title: "Sale rejected", description: "The person who entered it can see why, change it and send it again." })
      setRejecting(false)
      setReason("")
      onChanged(false)
    } catch (e: any) {
      toast({ title: "Not rejected", description: e?.message ?? "Try again.", variant: "destructive" })
    }
  })

  const withdraw = () => {
    if (!window.confirm(`Withdraw waiting sale W${row.pendingSaleId}? It will not be posted.`)) return
    void run(async () => {
      try {
        await withdrawPendingSale(getUserContext().farmId, row.pendingSaleId)
        toast({ title: "Sale withdrawn" })
        onChanged(false)
      } catch (e: any) {
        toast({ title: "Not withdrawn", description: e?.message ?? "Try again.", variant: "destructive" })
      }
    })
  }

  const size = labelled ? "h-10 w-full" : "h-8"
  return (
    <>
      <div className={cn(labelled ? "grid grid-cols-2 gap-2" : "flex items-center gap-1.5")}>
        {isApprover && row.status === "Waiting" && (
          <>
            <Button size="sm" className={cn(size, "gap-1 bg-emerald-600 hover:bg-emerald-700")} disabled={busy} onClick={approve}>
              {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />} Approve
            </Button>
            <Button size="sm" variant="outline" className={cn(size, "gap-1 border-red-200 text-red-600 hover:bg-red-50")} disabled={busy}
              onClick={() => { setRejecting(true); setReason("") }}>
              <X className="h-3.5 w-3.5" /> Reject
            </Button>
          </>
        )}
        {mayChange && (
          <>
            <Button size="sm" variant="outline" className={cn(size, "gap-1")} disabled={busy} onClick={() => onEdit(row)}>
              <Pencil className="h-3.5 w-3.5" /> {row.status === "Rejected" ? "Edit & resend" : "Edit"}
            </Button>
            <Button size="sm" variant="ghost" className={cn(size, "gap-1 text-slate-600")} disabled={busy} onClick={withdraw}>
              <Undo2 className="h-3.5 w-3.5" /> Withdraw
            </Button>
          </>
        )}
      </div>

      <Dialog open={rejecting} onOpenChange={(o) => { if (!o) setRejecting(false) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reject waiting sale W{row.pendingSaleId}</DialogTitle>
            <DialogDescription>
              It will not be posted. {row.submittedByName ?? "The person who entered it"} sees your reason and can change it and send it again.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor={`reject-reason-${row.pendingSaleId}`}>Reason</Label>
            <Textarea id={`reject-reason-${row.pendingSaleId}`} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. Price is wrong, should be 45 per crate" rows={3} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejecting(false)}>Cancel</Button>
            <Button className="bg-red-600 hover:bg-red-700" disabled={!reason.trim() || busy} onClick={reject}>
              {busy ? "Rejecting…" : "Reject sale"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}

/** The owner's switch: "Sales by staff need approval". */
export function SaleApprovalSwitch({ info, onInfoChanged }: {
  info: SaleApprovalInfo | null
  onInfoChanged: (info: SaleApprovalInfo) => void
}) {
  const { toast } = useToast()
  const [saving, setSaving] = useState(false)
  if (!info?.isOwner) return null

  const toggle = async (on: boolean) => {
    setSaving(true)
    try {
      onInfoChanged(await setSaleApproval(getUserContext().farmId, on))
      toast({
        title: on ? "Sales by staff now need approval" : "Sales post straight away",
        description: on
          ? "Staff who cannot approve sales send them for approval first. They show at the top of Recent Sales."
          : "Sales already waiting stay until they are approved, rejected or withdrawn.",
      })
    } catch (e: any) {
      toast({ title: "Setting not changed", description: e?.message ?? "Try again.", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-3 rounded-lg border px-3 py-2 w-fit">
        <ShieldCheck className="h-4 w-4 text-slate-500" />
        <Label htmlFor="sales-need-approval" className="text-sm">Sales by staff need approval</Label>
        <Switch id="sales-need-approval" checked={!!info.needApproval} disabled={saving} onCheckedChange={toggle} />
      </div>
      {info.needApproval && !info.active && (
        <p className="text-xs text-slate-500">Staff page access is not set up yet, so sales still post straight away.</p>
      )}
    </div>
  )
}

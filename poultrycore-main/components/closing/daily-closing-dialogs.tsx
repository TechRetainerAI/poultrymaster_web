"use client"

// Dialogs for the Daily Closing page (migration 333): Close Business Day,
// Reopen Day (reason required), and the closing policy.

import { useEffect, useState } from "react"
import { AlertTriangle, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import type { ClosingCheck, ClosingPolicy, PolicyLevel } from "@/lib/api/poultry-daily-closing"
import { formatLongDate } from "@/lib/closing/daily-closing"

export function CloseDayDialog({
  open, onOpenChange, businessDate, warnings, busy, onConfirm,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  businessDate: string
  warnings: ClosingCheck[]
  busy: boolean
  onConfirm: (notes: string) => void
}) {
  const [notes, setNotes] = useState("")
  useEffect(() => { if (open) setNotes("") }, [open])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Close {formatLongDate(businessDate)}?</DialogTitle>
          <DialogDescription>
            This records the day as checked and stores its figures as they are now. Later corrections stay possible
            and will show as changes against this closing.
          </DialogDescription>
        </DialogHeader>
        {warnings.length > 0 && (
          <div className="rounded-md border border-amber-200 bg-amber-50 p-3">
            <p className="mb-1 flex items-center gap-1.5 text-sm font-medium text-amber-900">
              <AlertTriangle className="h-4 w-4" /> Closing with {warnings.length} warning{warnings.length === 1 ? "" : "s"}
            </p>
            <ul className="list-disc space-y-0.5 pl-5 text-sm text-amber-900">
              {warnings.map((w) => <li key={w.key}>{w.title}</li>)}
            </ul>
          </div>
        )}
        <div className="space-y-1.5">
          <Label htmlFor="close-notes">Notes (optional)</Label>
          <Textarea id="close-notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={2}
            placeholder="e.g. Feed order placed for tomorrow" />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>Cancel</Button>
          <Button onClick={() => onConfirm(notes)} disabled={busy} className="bg-emerald-600 text-white hover:bg-emerald-700">
            {busy && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Close Business Day
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export function ReasonDialog({
  open, onOpenChange, title, description, confirmLabel, busy, onConfirm, destructive,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  title: string
  description: string
  confirmLabel: string
  busy: boolean
  onConfirm: (reason: string) => void
  destructive?: boolean
}) {
  const [reason, setReason] = useState("")
  useEffect(() => { if (open) setReason("") }, [open])
  const ok = reason.trim().length > 0

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="reason-text">Reason <span className="text-red-500">*</span></Label>
          <Textarea id="reason-text" value={reason} onChange={(e) => setReason(e.target.value)} rows={3} autoFocus />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>Cancel</Button>
          <Button
            onClick={() => onConfirm(reason.trim())}
            disabled={busy || !ok}
            variant={destructive ? "destructive" : "default"}
          >
            {busy && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

const LEVEL_ROWS: { key: keyof ClosingPolicy; label: string }[] = [
  { key: "missingProduction", label: "Missing flock production" },
  { key: "unpostedProduction", label: "Unposted batch production" },
  { key: "impossibleBirdCounts", label: "Impossible bird counts" },
  { key: "pendingDriverReturns", label: "Pending driver returns" },
  { key: "negativeStock", label: "Negative stock" },
  { key: "cashDifference", label: "Cash count difference" },
]

export function ClosingPolicyDialog({
  open, onOpenChange, policy, busy, onSave,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  policy: ClosingPolicy | null
  busy: boolean
  onSave: (p: ClosingPolicy) => void
}) {
  const [draft, setDraft] = useState<ClosingPolicy | null>(policy)
  useEffect(() => { if (open) setDraft(policy) }, [open, policy])
  if (!draft) return null
  const setNum = (k: "cashDifferenceTolerance" | "lowFeedDays" | "unusualMortalityPct", v: string) =>
    setDraft({ ...draft, [k]: v === "" ? 0 : Math.max(0, Number(v)) })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Closing policy</DialogTitle>
          <DialogDescription>
            Choose which checks stop a day from being closed. Anything set to Warning is shown but never blocks.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          {LEVEL_ROWS.map((r) => (
            <div key={r.key} className="flex items-center justify-between gap-3">
              <Label className="text-sm font-normal">{r.label}</Label>
              <Select value={draft[r.key] as string} onValueChange={(v) => setDraft({ ...draft, [r.key]: v as PolicyLevel })}>
                <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Blocking">Blocking</SelectItem>
                  <SelectItem value="Warning">Warning</SelectItem>
                </SelectContent>
              </Select>
            </div>
          ))}
        </div>
        <div className="grid grid-cols-1 gap-3 border-t border-slate-100 pt-3 sm:grid-cols-3">
          <div className="space-y-1">
            <Label htmlFor="pol-tol" className="text-xs">Cash difference tolerance</Label>
            <Input id="pol-tol" type="number" min={0} step="0.01" value={draft.cashDifferenceTolerance}
              onChange={(e) => setNum("cashDifferenceTolerance", e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="pol-feed" className="text-xs">Low feed below (days)</Label>
            <Input id="pol-feed" type="number" min={0} step="0.5" value={draft.lowFeedDays}
              onChange={(e) => setNum("lowFeedDays", e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="pol-mort" className="text-xs">Unusual mortality above (%)</Label>
            <Input id="pol-mort" type="number" min={0} step="0.1" value={draft.unusualMortalityPct}
              onChange={(e) => setNum("unusualMortalityPct", e.target.value)} />
          </div>
        </div>
        <div className="flex items-center justify-between gap-3">
          <Label htmlFor="pol-count" className="text-sm font-normal">Warn when no cash count is posted for the day</Label>
          <Switch id="pol-count" checked={draft.requireCashCount}
            onCheckedChange={(v) => setDraft({ ...draft, requireCashCount: v })} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>Cancel</Button>
          <Button onClick={() => onSave(draft)} disabled={busy}>
            {busy && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save policy
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

"use client"

// Reverse Flock Batch (migration 507). A batch is never deleted: the reversal
// keeps a numbered record (PBR-00001) with who, when, why, the flocks removed
// and what happened to the money; the batch then leaves the active list and
// shows under "Reversed batches".
//
// The SERVER's preview decides everything: the flocks it was divided into (a
// flock with records blocks it -- make it inactive instead), and each amount
// paid (refunded, or kept by the supplier as credit).

import { useEffect, useMemo, useRef, useState } from "react"
import { AlertTriangle, CheckCircle2, Loader2, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { PURCHASE_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { getUserContext } from "@/lib/utils/user-context"
import {
  getFlockBatchReversalPreview, reverseFlockBatch,
  type BatchMoneyAction, type FlockBatchReversalPreview,
} from "@/lib/api/flock-batch"

interface Props {
  open: boolean
  batchId: number | null
  onOpenChange: (open: boolean) => void
  onReversed: (summary: { reversalNumber?: string; refunded: number; creditCreated: number; flocksRemoved: number }) => void
}

function newKey(): string {
  try { return crypto.randomUUID() } catch { return `rev-${Date.now()}-${Math.random().toString(36).slice(2)}` }
}

function Figure({ label, value, tone }: { label: string; value: string; tone?: "warn" }) {
  return (
    <div className="rounded-md border border-slate-200 bg-white p-2.5">
      <p className="text-[11px] leading-tight text-slate-500">{label}</p>
      <p className={cn("text-base font-semibold tabular-nums leading-snug", tone === "warn" && "text-amber-700")}>{value}</p>
    </div>
  )
}

export function ReverseBatchDialog({ open, batchId, onOpenChange, onReversed }: Props) {
  const money = useFmt()
  const [preview, setPreview] = useState<FlockBatchReversalPreview | null>(null)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [handling, setHandling] = useState<Record<string, BatchMoneyAction>>({})
  const [confirmFlocks, setConfirmFlocks] = useState(false)
  const [reasonCode, setReasonCode] = useState("")
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [stale, setStale] = useState(false)
  const idemKey = useRef(newKey())

  const load = async (keep = false) => {
    if (!batchId) return
    const { farmId } = getUserContext()
    if (!farmId) { setLoadError("We could not confirm your farm. Please sign in again."); return }
    setLoading(true); setLoadError(null)
    const res = await getFlockBatchReversalPreview(batchId, farmId)
    setLoading(false)
    if (!res.success || !res.data) { setLoadError(res.message ?? "Could not load the batch."); return }
    setPreview(res.data)
    if (!keep) { setHandling({}); setConfirmFlocks(false) }
  }

  useEffect(() => {
    if (!open) return
    idemKey.current = newKey()
    setPreview(null); setReasonCode(""); setReason(""); setError(null); setStale(false); setHandling({}); setConfirmFlocks(false)
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, batchId])

  const actionFor = (key: string, allowed: BatchMoneyAction[], def: BatchMoneyAction) => {
    const chosen = handling[key]
    return chosen && allowed.includes(chosen) ? chosen : def
  }
  const outcome = useMemo(() => {
    let refund = 0, credit = 0
    for (const p of preview?.payments ?? []) (actionFor(p.key, p.allowed, p.default) === "Refund" ? (refund += p.allocated) : (credit += p.allocated))
    return { refund, credit }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [preview, handling])

  const flocks = preview?.flocks ?? []
  const blocked = !!preview && preview.blockers.length > 0
  const noteRequired = reasonCode === "Other"
  const canConfirm = !!preview && preview.found && !blocked && !!reasonCode && (!noteRequired || reason.trim().length > 0)
    && (flocks.length === 0 || confirmFlocks) && !saving && !loading

  const confirm = async () => {
    if (!preview || !batchId) return
    const { farmId, userId } = getUserContext()
    if (!farmId) return
    setSaving(true); setError(null)
    const sent: Record<string, BatchMoneyAction> = {}
    for (const p of preview.payments) sent[p.key] = actionFor(p.key, p.allowed, p.default)
    const res = await reverseFlockBatch(batchId, {
      farmId, userId: userId ?? undefined, reasonCode, reason: reason.trim(), paymentHandling: sent,
      deleteFlocks: flocks.length > 0 && confirmFlocks, expectedFingerprint: preview.fingerprint, idempotencyKey: idemKey.current,
    })
    setSaving(false)
    if (res.stale) { setStale(true); idemKey.current = newKey(); await load(true); return }
    if (!res.success) { setError(res.message ?? "The batch was not reversed."); return }
    const r = res.data?.reversal
    onReversed({ reversalNumber: r?.reversalNumber, refunded: r?.refunded ?? 0, creditCreated: r?.creditCreated ?? 0, flocksRemoved: r?.flocksRemoved ?? flocks.length })
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Undo2} color="red">
            Reverse batch{preview?.batchCode ? ` ${preview.batchCode}` : ""}?
          </FormDialogTitle>
          <DialogDescription>
            The batch is kept on record as Reversed (who, when and why), its cost comes off Profit &amp; Loss and it leaves
            the active list. Nothing is erased: the money it paid stays in the cash book.
          </DialogDescription>
        </DialogHeader>

        {loading && !preview ? (
          <div className="flex items-center gap-2 py-8 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Working out what this would do…</div>
        ) : loadError ? (
          <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{loadError}</div>
        ) : preview ? (
          <div className="min-w-0 space-y-4">
            {stale && (
              <div className="flex gap-2 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                This batch changed after the reversal preview was generated. Please review the updated impact before continuing.
              </div>
            )}
            {blocked && (
              <div className="space-y-1 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-800">
                <p className="font-semibold">This batch cannot be reversed yet</p>
                {preview.blockers.map((b) => <p key={b.code}>{b.message}</p>)}
              </div>
            )}

            {preview.found && (
              <FormSection title="The batch" color="blue" tinted columns={4}>
                <Figure label="Batch" value={preview.batchName || preview.batchCode || `#${preview.batchId}`} />
                <Figure label="Birds" value={(preview.birds ?? 0).toLocaleString()} />
                <Figure label="Total cost" value={money(preview.total ?? 0)} />
                <Figure label="Still owed" value={money(preview.outstanding ?? 0)} tone={(preview.outstanding ?? 0) > 0 ? "warn" : undefined} />
              </FormSection>
            )}

            {flocks.length > 0 && (
              <div className={cn("rounded-md border p-3 text-sm", blocked ? "border-slate-200 bg-slate-50" : "border-red-300 bg-red-50")}>
                <p className={cn("font-semibold", blocked ? "text-slate-700" : "text-red-800")}>
                  {blocked
                    ? `This batch was divided into ${flocks.length} flock(s):`
                    : `WARNING: these ${flocks.length} flock(s) will be deleted with the batch:`}
                </p>
                <ul className="mt-1.5 space-y-1">
                  {flocks.map((f) => (
                    <li key={f.flockId} className="flex flex-wrap items-baseline justify-between gap-x-3">
                      <span className="font-medium text-slate-900">{f.name}</span>
                      <span className={cn("text-xs", f.canDelete ? "text-slate-600" : "font-semibold text-red-700")}>
                        {f.canDelete
                          ? `${f.liveBirds.toLocaleString()} birds · no records`
                          : `has ${f.records.map((r) => `${r.rows} ${r.label}`).join(", ")} → make it inactive`}
                      </span>
                    </li>
                  ))}
                </ul>
                {!blocked && (
                  <label className="mt-2 flex cursor-pointer items-start gap-2 rounded-md border border-red-300 bg-white p-2.5">
                    <Checkbox checked={confirmFlocks} onCheckedChange={(v) => setConfirmFlocks(v === true)} className="mt-0.5" />
                    <span className="text-red-800">I understand the {flocks.length} flock(s) above will be deleted with this batch.</span>
                  </label>
                )}
              </div>
            )}

            {!blocked && preview.found && (
              <FormSection title="This reversal will" color="amber" tinted columns={1}>
                <ul className="space-y-1 text-sm text-slate-700">
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Take its {(preview.birds ?? 0).toLocaleString()} birds out of the bird count</li>
                  {Number(preview.expenseRemoved) > 0 && (
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Remove its {money(Number(preview.expenseRemoved))} bird purchase cost from Profit &amp; Loss</li>
                  )}
                  {(preview.outstanding ?? 0) > 0 && (
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Clear the {money(preview.outstanding ?? 0)} still owed to the supplier</li>
                  )}
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Keep a record of the batch under &quot;Reversed batches&quot;</li>
                </ul>
              </FormSection>
            )}

            {!blocked && preview.payments.length > 0 && (
              <FormSection title="Money already paid" color="green" tinted columns={1}>
                <p className="text-sm text-slate-600">The payment itself stays as it was. Choose what has happened to the money since.</p>
                {preview.payments.map((p) => {
                  const action = actionFor(p.key, p.allowed, p.default)
                  const both = p.allowed.includes("KeepAsCredit") && p.allowed.includes("Refund")
                  return (
                    <div key={p.key} className="space-y-2 rounded-md border bg-white p-3">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <p className="text-sm font-medium text-slate-900">{p.paymentNumbers}</p>
                        <p className="text-sm font-semibold tabular-nums">{money(p.allocated)}</p>
                      </div>
                      <p className="text-xs text-slate-500">{p.cashAccountName || "No cash account"}</p>
                      {both ? (
                        <RadioGroup value={action} onValueChange={(v) => setHandling((h) => ({ ...h, [p.key]: v as BatchMoneyAction }))} className="gap-2">
                          <label className={cn("flex cursor-pointer gap-2 rounded-md border p-2.5", action === "Refund" && "border-emerald-400 bg-emerald-50/60")}>
                            <RadioGroupItem value="Refund" className="mt-0.5" />
                            <span className="text-sm">
                              <span className="font-medium">The supplier refunded it</span>
                              <span className="block text-xs text-slate-600">
                                {p.noCashNote ?? `${money(p.allocated)} comes back into ${p.cashAccountName || "its cash account"} today.`}
                              </span>
                            </span>
                          </label>
                          <label className={cn("flex cursor-pointer gap-2 rounded-md border p-2.5", action === "KeepAsCredit" && "border-blue-400 bg-blue-50/60")}>
                            <RadioGroupItem value="KeepAsCredit" className="mt-0.5" />
                            <span className="text-sm">
                              <span className="font-medium">Keep it as supplier credit</span>
                              <span className="block text-xs text-slate-600">
                                {preview.supplierName} still holds the money: {money(p.allocated)} becomes credit for your next bill. No cash moves.
                              </span>
                            </span>
                          </label>
                        </RadioGroup>
                      ) : (
                        <p className={cn("rounded-md p-2.5 text-xs", action === "Refund" ? "bg-emerald-50 text-emerald-900" : "bg-blue-50 text-blue-900")}>
                          {action === "Refund"
                            ? <>{p.keepUnavailableReason ?? "This money can only be recorded as refunded."} {p.noCashNote ?? `${money(p.allocated)} comes back into ${p.cashAccountName || "its cash account"} today.`}</>
                            : <>{p.refundUnavailableReason ?? "This money can only be kept as supplier credit."} No cash moves.</>}
                        </p>
                      )}
                    </div>
                  )
                })}
                <div className="grid grid-cols-2 gap-2">
                  <Figure label="Refunded to you" value={money(outcome.refund)} />
                  <Figure label="Becomes supplier credit" value={money(outcome.credit)} />
                </div>
              </FormSection>
            )}

            {!blocked && preview.found && (
              <FormSection title="Reason" color="slate" tinted columns={1}>
                <div className="grid gap-2 sm:grid-cols-[200px_1fr]">
                  <div>
                    <Label className="sr-only">Reason</Label>
                    <Select value={reasonCode} onValueChange={setReasonCode}>
                      <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Choose a reason" /></SelectTrigger>
                      <SelectContent>
                        {PURCHASE_REVERSAL_REASONS.map((r) => <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  <Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={2} className="bg-white"
                    placeholder={noteRequired ? "Say what happened (needed for Other)" : "Note (optional)"} />
                </div>
              </FormSection>
            )}

            {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
          </div>
        ) : null}

        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={confirm} disabled={!canConfirm} className={cn("px-6", FORM_DIALOG_PRIMARY.red)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Reverse batch
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

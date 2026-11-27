"use client"

// Reverse Purchase (migration 478; Generic 500) -- the Reverse Sale dialog, for
// inventory purchases.
//
// A purchase is never deleted. This dialog shows, from the SERVER's preview,
// exactly what reversing it will do -- the stock that comes back out, what is
// no longer owed, and what happens to every payment on it -- and asks the one
// question that is the user's to answer: for money already paid, did the
// supplier hand it back (refund, money in today) or do they still hold it
// (supplier credit for the next purchase)?

import { useEffect, useMemo, useRef, useState } from "react"
import { AlertTriangle, CheckCircle2, Loader2, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import { formatCurrency } from "@/lib/utils/currency"
import { PURCHASE_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import {
  getPurchaseReversalPreview, reversePurchase,
  type PurchaseModule, type PurchaseMoneyAction, type PurchaseMoneyLine,
  type PurchaseReversalPreview, type PurchaseReversalRecord,
} from "@/lib/api/purchase-reversal"

export interface ReversePurchaseResult {
  preview: PurchaseReversalPreview
  reversal: PurchaseReversalRecord | null
}

interface Props {
  open: boolean
  module: PurchaseModule
  purchaseId: number | null
  /** "#118" */
  purchaseLabel: string
  farmId: string
  userId?: string
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onReversed: (result: ReversePurchaseResult) => void
}

type Handling = Record<string, PurchaseMoneyAction>

const actionFor = (p: PurchaseMoneyLine, h: Handling): PurchaseMoneyAction => {
  const chosen = h[p.key]
  return chosen && p.allowed.includes(chosen) ? chosen : p.default
}

function Figure({ label, value, tone }: { label: string; value: string; tone?: "warn" | "good" }) {
  return (
    <div className="rounded-md border border-slate-200 bg-white p-2.5">
      <p className="text-[11px] leading-tight text-slate-500">{label}</p>
      <p className={cn("text-base font-semibold tabular-nums leading-snug",
        tone === "warn" && "text-amber-700", tone === "good" && "text-emerald-700")}>{value}</p>
    </div>
  )
}

function newKey(): string {
  try { return crypto.randomUUID() } catch { return `rev-${Date.now()}-${Math.random().toString(36).slice(2)}` }
}

const qty = (n: number) => (Number(n) || 0).toLocaleString(undefined, { maximumFractionDigits: 3 })

export function ReversePurchaseDialog({
  open, module, purchaseId, purchaseLabel, farmId, userId, currencyCode, onOpenChange, onReversed,
}: Props) {
  const [preview, setPreview] = useState<PurchaseReversalPreview | null>(null)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [handling, setHandling] = useState<Handling>({})
  const [reasonCode, setReasonCode] = useState<string>("")
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [staleNotice, setStaleNotice] = useState(false)
  // One key per opened dialog: a double-click, or a retry after a dropped
  // response, returns the reversal already made instead of making another.
  const idemKey = useRef(newKey())

  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)
  // 504: the same dialog reverses a Generic expense
  const noun = module === "generic-expense" ? "expense" : "purchase"

  const load = async (keepChoices = false) => {
    if (!purchaseId) return
    setLoading(true)
    setLoadError(null)
    const res = await getPurchaseReversalPreview(module, purchaseId, farmId)
    setLoading(false)
    if (!res.success || !res.data) { setLoadError(res.message ?? `Could not load the ${noun}.`); return }
    setPreview(res.data)
    setHandling((prev) => (keepChoices ? prev : {}))
  }

  useEffect(() => {
    if (!open) return
    idemKey.current = newKey()
    setPreview(null); setReasonCode(""); setReason(""); setError(null); setStaleNotice(false); setHandling({})
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, purchaseId])

  const outcome = useMemo(() => {
    if (!preview) return null
    let credit = 0, refund = 0
    for (const p of preview.payments) (actionFor(p, handling) === "Refund" ? (refund += p.allocated) : (credit += p.allocated))
    return { credit, refund }
  }, [preview, handling])

  const blocked = !!preview && preview.blockers.length > 0
  const reasonText = reason.trim()
  // A reason from the list is enough; only "Other" needs a note (354).
  const noteRequired = reasonCode === "Other"
  const canConfirm = !!preview && !blocked && !!reasonCode && (!noteRequired || reasonText.length > 0) && !saving && !loading
  const unit = preview?.unit ? ` ${preview.unit}` : ""

  const confirm = async () => {
    if (!preview || !purchaseId) return
    setSaving(true)
    setError(null)
    const sent: Handling = {}
    for (const p of preview.payments) sent[p.key] = actionFor(p, handling)
    const res = await reversePurchase(module, purchaseId, {
      farmId, userId, reasonCode, reason: reasonText,
      paymentHandling: sent, expectedFingerprint: preview.fingerprint, idempotencyKey: idemKey.current,
    })
    setSaving(false)
    if (res.stale) {
      // Something changed (a payment, a production draw). Show the new impact
      // and let the user confirm again -- never act on the old one.
      setStaleNotice(true)
      idemKey.current = newKey()
      await load(true)
      return
    }
    if (!res.success) { setError(res.message ?? `The ${noun} was not reversed.`); return }
    onReversed({ preview, reversal: res.data?.reversal ?? null })
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Undo2} color="red">Reverse {noun} {purchaseLabel}?</FormDialogTitle>
          <DialogDescription>
            The {noun} stays in the history, marked Reversed. {module === "generic-expense" ? "Its cost comes off Profit & Loss" : "Its stock comes back out"} and the supplier is no longer
            owed for it. Nothing is deleted.
          </DialogDescription>
        </DialogHeader>

        {loading && !preview ? (
          <div className="flex items-center gap-2 py-8 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Working out what this would do…</div>
        ) : loadError ? (
          <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{loadError}</div>
        ) : preview ? (
          <div className="min-w-0 space-y-4">
            {staleNotice && (
              <div className="flex gap-2 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                This {noun} changed after the reversal preview was generated. Please review the updated impact before continuing.
              </div>
            )}

            {blocked && (
              <div className="space-y-1 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                <p className="font-semibold">This {noun} cannot be reversed yet</p>
                {preview.blockers.map((b) => <p key={b.code}>{b.message}</p>)}
              </div>
            )}

            <FormSection title={`The ${noun}`} color="blue" tinted columns={4}>
              <Figure label="Item" value={`${preview.itemName}`} />
              <Figure label="Supplier" value={preview.supplierName} />
              <Figure label="Total" value={money(preview.total)} />
              <Figure label="Still owed" value={money(preview.outstanding)} tone={preview.outstanding > 0 ? "warn" : undefined} />
            </FormSection>

            <FormSection title="This reversal will" color="amber" tinted columns={1}>
              <ul className="space-y-1 text-sm text-slate-700">
                {preview.noStock ? null : preview.lines ? (
                  // Generic: one row per product the purchase stocked
                  preview.lines.length > 0 ? (
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                      <span>
                        Take back out of stock exactly what this purchase added:
                        <span className="mt-1 block space-y-0.5">
                          {preview.lines.map((l) => (
                            <span key={l.productId} className="block text-slate-600">· {qty(l.quantity)} {l.unit} of {l.name}</span>
                          ))}
                        </span>
                      </span>
                    </li>
                  ) : (
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Nothing comes out of stock (its items are not stock-tracked)</li>
                  )
                ) : (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Take {qty(preview.stockToRemove)}{unit} of {preview.itemName} back out of stock — exactly what this purchase added</li>
                )}
                {preview.costOnPl !== false && (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Remove its {money(preview.total)} cost from Profit &amp; Loss</li>
                )}
                {preview.outstanding > 0 && (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Clear the {money(preview.outstanding)} still owed to the supplier for it</li>
                )}
                {preview.creditApplied > 0 && (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Give back the {money(preview.creditApplied)} of supplier credit used on it</li>
                )}
                <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Keep the {noun} and its payments in the history</li>
              </ul>
            </FormSection>

            {preview.payments.length > 0 ? (
              <FormSection title="Money already paid" color="green" tinted columns={1}>
                <p className="text-sm text-slate-600">
                  The payment itself stays as it was — the money did leave on that day. Choose what has happened to it since.
                </p>
                {preview.payments.map((p) => {
                  const action = actionFor(p, handling)
                  const both = p.allowed.includes("KeepAsCredit") && p.allowed.includes("Refund")
                  const where = p.cashAccountName || "its cash account"
                  return (
                    <div key={p.key} className="space-y-2 rounded-md border bg-white p-3">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <p className="text-sm font-medium text-slate-900">{p.paymentNumbers}</p>
                        <p className="text-sm font-semibold tabular-nums">{money(p.allocated)}</p>
                      </div>
                      <p className="text-xs text-slate-500">
                        {[p.paymentMethod, p.cashAccountName].filter(Boolean).join(" · ") || "No cash account"}
                      </p>
                      {both ? (
                        <RadioGroup
                          value={action}
                          onValueChange={(v) => setHandling((h) => ({ ...h, [p.key]: v as PurchaseMoneyAction }))}
                          className="gap-2"
                        >
                          <label className={cn("flex cursor-pointer gap-2 rounded-md border p-2.5", action === "KeepAsCredit" && "border-blue-400 bg-blue-50/60")}>
                            <RadioGroupItem value="KeepAsCredit" className="mt-0.5" />
                            <span className="text-sm">
                              <span className="font-medium">Keep it as supplier credit</span>
                              <span className="block text-xs text-slate-600">
                                {preview.supplierName} still holds the money. {money(p.allocated)} becomes credit you can use on your
                                next purchase from them. No cash moves.
                              </span>
                            </span>
                          </label>
                          <label className={cn("flex cursor-pointer gap-2 rounded-md border p-2.5", action === "Refund" && "border-emerald-400 bg-emerald-50/60")}>
                            <RadioGroupItem value="Refund" className="mt-0.5" />
                            <span className="text-sm">
                              <span className="font-medium">The supplier refunded it</span>
                              <span className="block text-xs text-slate-600">
                                {p.noCashNote
                                  ? p.noCashNote
                                  : `${money(p.allocated)} comes back into ${where} today, shown in Cash Flow as a refund (not income).`}
                              </span>
                            </span>
                          </label>
                        </RadioGroup>
                      ) : action === "KeepAsCredit" ? (
                        <p className="rounded-md bg-blue-50 p-2.5 text-xs text-blue-900">
                          {p.refundUnavailableReason ?? "This money can only be kept as supplier credit."}{" "}
                          No cash moves; {money(p.allocated)} becomes credit with {preview.supplierName}.
                        </p>
                      ) : (
                        <p className="rounded-md bg-emerald-50 p-2.5 text-xs text-emerald-900">
                          {p.keepUnavailableReason ?? "This money can only be recorded as refunded."}{" "}
                          {p.noCashNote ?? `${money(p.allocated)} comes back into ${where} today.`}
                        </p>
                      )}
                    </div>
                  )
                })}
                {outcome && (
                  <div className="grid grid-cols-2 gap-2">
                    <Figure label="Becomes supplier credit" value={money(outcome.credit)} />
                    <Figure label="Refunded to you" value={money(outcome.refund)} tone={outcome.refund > 0 ? "good" : undefined} />
                  </div>
                )}
              </FormSection>
            ) : (
              <p className="rounded-md bg-slate-50 p-3 text-sm text-slate-600">
                {preview.creditApplied > 0
                  ? `No money was paid on this ${noun}; the supplier credit used on it goes back to the supplier.`
                  : `Nothing was paid on this ${noun}, so no money moves.`}
              </p>
            )}

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
                <Textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder={noteRequired ? "Say what happened (needed for Other)" : "Note (optional)"}
                  rows={2}
                  className="bg-white"
                />
              </div>
            </FormSection>

            {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
          </div>
        ) : null}

        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={confirm} disabled={!canConfirm} className={cn("px-6", FORM_DIALOG_PRIMARY.red)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Reverse {noun}{preview ? ` · ${money(preview.total)}` : ""}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

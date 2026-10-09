"use client"

// Reverse Sale (migration 351).
//
// A posted sale is never edited or deleted. This dialog shows, from the
// SERVER's preview, exactly what reversing it will do -- revenue, receivable,
// the stock that comes back (by egg class), and what happens to every payment
// on it -- and asks the one question that is the user's to answer: for money
// the sale itself brought in, does the business still hold it (customer
// credit) or did it go back (reverse the payment, Money Out)?
//
// "Correct Sale" is the same dialog in mode "correct": after the reversal the
// page opens a new sale pre-filled from this one.

import { useEffect, useMemo, useRef, useState } from "react"
import { AlertTriangle, CheckCircle2, Loader2, RotateCcw, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import { formatCurrency } from "@/lib/utils/currency"
import {
  getSaleReversalPreview, reverseSale, REVERSAL_REASONS,
  type PaymentAction, type SaleReversalPreview, type SaleReversalRecord,
} from "@/lib/api/sale"
import {
  defaultHandling, effectiveAction, paymentSourceLabel, restoreLabel, reversalOutcome, type Handling,
} from "@/lib/sales/reversal"

export interface ReverseSaleResult {
  preview: SaleReversalPreview
  reversal: SaleReversalRecord | null
  handling: Handling
}

interface Props {
  open: boolean
  saleId: number | null
  /** "#2351" or "SG-00012" */
  saleLabel: string
  mode: "reverse" | "correct"
  farmId: string
  userId?: string
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onReversed: (result: ReverseSaleResult) => void
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">{children}</p>
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

export function ReverseSaleDialog({
  open, saleId, saleLabel, mode, farmId, userId, currencyCode, onOpenChange, onReversed,
}: Props) {
  const [preview, setPreview] = useState<SaleReversalPreview | null>(null)
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

  const load = async (keepChoices = false) => {
    if (!saleId) return
    setLoading(true)
    setLoadError(null)
    const res = await getSaleReversalPreview(saleId, farmId)
    setLoading(false)
    if (!res.success || !res.data) { setLoadError(res.message ?? "Could not load the sale."); return }
    setPreview(res.data)
    setHandling((prev) => (keepChoices ? { ...defaultHandling(res.data!), ...prev } : defaultHandling(res.data!)))
  }

  useEffect(() => {
    if (!open) return
    idemKey.current = newKey()
    setPreview(null); setReasonCode(""); setReason(""); setError(null); setStaleNotice(false)
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, saleId])

  const outcome = useMemo(() => (preview ? reversalOutcome(preview, handling) : null), [preview, handling])
  const blocked = !!preview && preview.blockers.length > 0
  const restoreLines = (preview?.lines ?? []).map((l) => restoreLabel(l)).filter(Boolean) as string[]
  const reasonText = reason.trim()
  // A reason from the list is enough; only "Other" needs a note (354).
  const noteRequired = reasonCode === "Other"
  const canConfirm = !!preview && !blocked && !!reasonCode && (!noteRequired || reasonText.length > 0) && !saving && !loading

  const confirm = async () => {
    if (!preview || !saleId) return
    setSaving(true)
    setError(null)
    const sent: Handling = {}
    for (const p of preview.payments) sent[p.key] = effectiveAction(p, handling)
    const res = await reverseSale(saleId, {
      farmId, userId, reasonCode, reason: reasonText,
      paymentHandling: sent, expectedFingerprint: preview.fingerprint, idempotencyKey: idemKey.current,
    })
    setSaving(false)
    if (res.stale) {
      // Something changed (a payment arrived, say). Show the new impact and let
      // the user confirm again -- never act on the old one.
      setStaleNotice(true)
      idemKey.current = newKey()
      await load(true)
      return
    }
    if (!res.success) { setError(res.message ?? "The sale was not reversed."); return }
    onReversed({ preview, reversal: res.data?.reversal ?? null, handling: sent })
  }

  const title = mode === "correct" ? `Correct sale ${saleLabel}` : `Reverse sale ${saleLabel}?`

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {mode === "correct" ? <RotateCcw className="h-5 w-5 text-blue-600" /> : <Undo2 className="h-5 w-5 text-red-600" />}
            {title}
          </DialogTitle>
          <DialogDescription>
            {mode === "correct"
              ? "A posted sale is not edited. It is reversed, and a new sale is opened filled in from it for you to fix and save."
              : "The sale stays in the history, marked Reversed. Its revenue, what the customer owes and its stock are undone with opposite entries."}
          </DialogDescription>
        </DialogHeader>

        {loading && !preview ? (
          <div className="flex items-center gap-2 py-8 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Working out what this would do…</div>
        ) : loadError ? (
          <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{loadError}</div>
        ) : preview ? (
          <div className="space-y-4">
            {staleNotice && (
              <div className="flex gap-2 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                This sale changed after the reversal preview was generated. Please review the updated impact before continuing.
              </div>
            )}

            {blocked && (
              <div className="space-y-1 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                <p className="font-semibold">This sale cannot be reversed here</p>
                {preview.blockers.map((b) => <p key={b.code}>{b.message}</p>)}
              </div>
            )}

            <section className="space-y-2">
              <SectionLabel>The sale</SectionLabel>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                <Figure label="Customer" value={preview.customerName || "Walk-in"} />
                <Figure label="Sale total" value={money(preview.total)} />
                <Figure label="Paid" value={money(preview.paid)} tone={preview.paid > 0 ? "good" : undefined} />
                <Figure label="Outstanding" value={money(preview.outstanding)} tone={preview.outstanding > 0 ? "warn" : undefined} />
              </div>
            </section>

            <section className="space-y-2">
              <SectionLabel>This reversal will</SectionLabel>
              <ul className="space-y-1 text-sm text-slate-700">
                <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Reverse the sale's revenue of {money(preview.total)}</li>
                {restoreLines.length > 0 && (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Put back {restoreLines.join(", ")} — exactly what was sold</li>
                )}
                {preview.outstanding > 0 && (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Remove the {money(preview.outstanding)} the customer still owes on it</li>
                )}
                {preview.payments.length > 0 && (
                  <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Release the payments applied to it (below)</li>
                )}
                <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /> Keep the sale, its payments and its stock movements in the history</li>
              </ul>
            </section>

            {preview.payments.length > 0 ? (
              <section className="space-y-2">
                <SectionLabel>Payment handling</SectionLabel>
                <p className="text-sm text-slate-600">
                  Reversing a sale does not by itself mean the money left the business. Choose what happened to it.
                </p>
                {preview.payments.map((p) => {
                  const action = effectiveAction(p, handling)
                  const both = p.allowed.includes("KeepAsCredit") && p.allowed.includes("ReversePayment")
                  return (
                    <div key={p.key} className="space-y-2 rounded-md border p-3">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <p className="text-sm font-medium text-slate-900">
                          {p.paymentNumbers || "Money received at the sale"}
                          <span className="ml-2 text-xs font-normal text-slate-500">{paymentSourceLabel(p)}</span>
                        </p>
                        <p className="text-sm font-semibold tabular-nums">{money(p.allocated)}</p>
                      </div>
                      <p className="text-xs text-slate-500">
                        {[p.paymentMethod, p.cashAccountName].filter(Boolean).join(" · ") || "No cash account"}
                        {p.paymentTotal > p.allocated + 0.005 && ` · ${money(p.paymentTotal)} payment, ${money(p.allocated)} of it on this sale`}
                      </p>
                      {both ? (
                        <RadioGroup
                          value={action}
                          onValueChange={(v) => setHandling((h) => ({ ...h, [p.key]: v as PaymentAction }))}
                          className="gap-2"
                        >
                          <label className={cn("flex cursor-pointer gap-2 rounded-md border p-2.5", action === "KeepAsCredit" && "border-blue-400 bg-blue-50/60")}>
                            <RadioGroupItem value="KeepAsCredit" className="mt-0.5" />
                            <span className="text-sm">
                              <span className="font-medium">Keep it as customer credit</span>
                              <span className="block text-xs text-slate-600">
                                The money stays received. {money(p.allocated)} becomes credit the customer can use on another sale. The cash account does not change.
                              </span>
                            </span>
                          </label>
                          <label className={cn("flex cursor-pointer gap-2 rounded-md border p-2.5", action === "ReversePayment" && "border-red-300 bg-red-50/60")}>
                            <RadioGroupItem value="ReversePayment" className="mt-0.5" />
                            <span className="text-sm">
                              <span className="font-medium">Reverse the payment</span>
                              <span className="block text-xs text-slate-600">
                                {p.paymentNumbers ? `Payment ${p.paymentNumbers}` : "The money received"} is reversed. {p.cashAccountName || "Its cash account"} decreases by {money(p.allocated)}, shown in Cash Flow as a payment reversal (not an expense).
                              </span>
                            </span>
                          </label>
                        </RadioGroup>
                      ) : action === "ReversePayment" ? (
                        <p className="rounded-md bg-red-50 p-2.5 text-xs text-red-800">
                          This sale has no customer to hold the money as credit, so the {money(p.allocated)} is reversed: {p.cashAccountName || "its cash account"} decreases by that amount.
                        </p>
                      ) : (
                        <p className="rounded-md bg-slate-50 p-2.5 text-xs text-slate-700">
                          {p.reverseUnavailableReason || "This payment stays Posted."} Cash does not change; {money(p.allocated)} becomes customer credit.
                          {" "}To give the money back, refund it from Customer Balances afterwards.
                        </p>
                      )}
                    </div>
                  )
                })}
                {outcome && (
                  <div className="grid grid-cols-2 gap-2">
                    <Figure label="Becomes customer credit" value={money(outcome.creditCreated)} />
                    <Figure label="Money out of cash" value={money(outcome.cashOut)} tone={outcome.cashOut > 0 ? "warn" : undefined} />
                  </div>
                )}
              </section>
            ) : (
              <p className="rounded-md bg-slate-50 p-3 text-sm text-slate-600">
                Nothing was paid on this sale, so no money moves.
              </p>
            )}

            <section className="space-y-2">
              <SectionLabel>Reason</SectionLabel>
              <div className="grid gap-2 sm:grid-cols-[200px_1fr]">
                <div>
                  <Label className="sr-only">Reason</Label>
                  <Select value={reasonCode} onValueChange={setReasonCode}>
                    <SelectTrigger><SelectValue placeholder="Choose a reason" /></SelectTrigger>
                    <SelectContent>
                      {REVERSAL_REASONS.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <Textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder={noteRequired
                    ? "Say what happened (needed for Other)"
                    : mode === "correct" ? "Note (optional), e.g. price should have been 25 per crate" : "Note (optional)"}
                  rows={2}
                />
              </div>
            </section>

            {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
          </div>
        ) : null}

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button
            onClick={confirm}
            disabled={!canConfirm}
            className={mode === "correct" ? "bg-blue-600 hover:bg-blue-700" : "bg-red-600 hover:bg-red-700"}
          >
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {mode === "correct" ? "Reverse and correct" : "Reverse sale"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

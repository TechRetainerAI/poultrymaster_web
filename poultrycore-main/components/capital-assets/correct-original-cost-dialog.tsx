"use client"

// =============================================================================
// Correct original cost (migrations 313, 314).
//
// WHY THIS IS NOT A TEXT BOX ON THE EDIT FORM
// -------------------------------------------
// Somebody typed 130,000 where the invoice said 13,000. Before this dialog the
// only offered way to change that number was "Add cost", which would have made
// the register say the thing cost 143,000 -- so the fix for a wrong number was
// to record a second wrong number.
//
// Making the field editable instead would have been worse in a quieter way. The
// original cost is not just a label: cash moved by it, a supplier balance was
// opened by it, and every future month's depreciation is computed from it. A
// number that three other things depend on does not get silently replaced. So
// this asks for a reason, shows what it is about to change, and leaves a dated
// row on the record.
//
// WHAT THE PREVIEW IS, AND IS NOT
// -------------------------------
// The figures under "What this will change" are a PROJECTION, computed here from
// values the server has already given. They are shown because §21 asks for the
// impact before the confirmation, and there is no way to ask the server what a
// number would be if it were different without writing it.
//
// They are deliberately marked as a projection, and nothing is saved from them:
// the moment Save returns, the register reloads and every figure on the page is
// the server's own again. This is the one place in the feature that does its own
// arithmetic, and it earns it by never being persisted.
// =============================================================================

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertTriangle, Info, Loader2, SlidersHorizontal } from "lucide-react"
import { cn } from "@/lib/utils"
import { previewCorrection, round2 } from "@/lib/capital-assets/correction-preview"

/**
 * Everything the dialog needs, all of it already on the register row -- so it
 * can be opened straight from the list without waiting for a detail fetch.
 */
export interface CorrectableAsset {
  id: number
  assetName: string
  assetNumber?: string | null
  acquisitionCost: number
  additionalCost: number
  totalCapitalizedCost: number
  residualValue: number
  usefulLifeMonths?: number | null
  accumulatedDepreciation: number
  currentBookValue: number
  depreciationEntries: number
}

export interface CorrectOriginalCostDialogProps {
  asset: CorrectableAsset | null
  onClose: () => void
  /** Resolves when the server has accepted it; the caller reloads. */
  onSubmit: (input: { newAmount: number; effectiveDate: string | null; reason: string }) => Promise<void>
  fmt: (n: number) => string
  term: "investment" | "asset"
  /** The module's own wording, from lib/{poultry,water}/financial-classification. */
  notes: { correctOriginalCostNote: string; correctionDepreciationNote: string }
}

const today = () => new Date().toISOString().slice(0, 10)

export function CorrectOriginalCostDialog({
  asset, onClose, onSubmit, fmt, term, notes,
}: CorrectOriginalCostDialogProps) {
  const [amount, setAmount] = useState<string>("")
  const [effectiveDate, setEffectiveDate] = useState<string>(today())
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (asset) {
      setAmount(String(asset.acquisitionCost))
      setEffectiveDate(today())
      setReason("")
      setError(null)
    }
  }, [asset])

  // Every rule in here is the server's, mirrored -- and tested against it in
  // lib/capital-assets/correction-preview.test.ts, because a preview that
  // disagreed with the save would be worse than no preview.
  const preview = useMemo(
    () => (asset
      ? previewCorrection({
          acquisitionCost: asset.acquisitionCost,
          additionalCost: asset.additionalCost,
          residualValue: asset.residualValue,
          usefulLifeMonths: asset.usefulLifeMonths,
          accumulatedDepreciation: asset.accumulatedDepreciation,
          newAcquisitionCost: Number(amount),
        })
      : null),
    [asset, amount],
  )

  const hasDepreciation = (asset?.depreciationEntries ?? 0) > 0
  const canSave = !!preview && !preview.residualTooHigh && reason.trim().length > 0 && !saving

  const save = async () => {
    if (!asset || !preview) return
    setSaving(true)
    setError(null)
    try {
      await onSubmit({
        newAmount: preview.next,
        effectiveDate: effectiveDate || null,
        reason: reason.trim(),
      })
      onClose()
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={!!asset} onOpenChange={(o) => { if (!o && !saving) onClose() }}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <SlidersHorizontal className="h-4 w-4" />
            Correct the original cost of {asset?.assetName}
          </DialogTitle>
          <DialogDescription>{notes.correctOriginalCostNote}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <section className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label className="text-sm">Current original acquisition cost</Label>
              <Input value={asset ? fmt(asset.acquisitionCost) : ""} disabled className="mt-1" />
              {!!asset && asset.additionalCost > 0 && (
                <p className="mt-1 text-[11px] text-slate-500">
                  Plus {fmt(asset.additionalCost)} of additional costs, which this does not touch.
                </p>
              )}
            </div>
            <div>
              <Label className="text-sm">Corrected original acquisition cost</Label>
              <NumberInput value={amount} onChange={(e) => setAmount(e.target.value)} className="mt-1" />
            </div>
            <div>
              <Label className="text-sm">Effective date</Label>
              <Input type="date" value={effectiveDate} className="mt-1"
                     onChange={(e) => setEffectiveDate(e.target.value)} />
              <p className="mt-1 text-[11px] text-slate-500">
                The date the correction is recorded against. It does not move the acquisition date.
              </p>
            </div>
            <div>
              <Label className="text-sm">Difference</Label>
              <Input
                className={cn("mt-1 tabular-nums", preview && preview.difference < 0 && "text-red-600")}
                disabled
                value={preview
                  ? `${preview.difference < 0 ? "−" : "+"}${fmt(Math.abs(preview.difference))}`
                  : "—"}
              />
            </div>
          </section>

          <section>
            <Label className="text-sm">Reason <span className="text-red-600">*</span></Label>
            <Textarea rows={2} value={reason} className="mt-1"
                      onChange={(e) => setReason(e.target.value)}
                      placeholder="Original invoice amount was entered incorrectly" />
            <p className="mt-1 text-[11px] text-slate-500">
              Required. It is kept on the {term}&apos;s cost history with your name and the date.
            </p>
          </section>

          {preview && (
            <section className="space-y-2 rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-xs text-sky-900">
              <div className="flex items-start gap-1.5">
                <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span className="font-medium">What this will change — a projection, not yet saved</span>
              </div>
              <dl className="grid gap-x-6 gap-y-1 sm:grid-cols-2">
                <Row label="Total capitalised cost"
                     from={fmt(asset!.totalCapitalizedCost)} to={fmt(preview.newTotal)} />
                <Row label="Depreciable basis"
                     from={fmt(Math.max(round2(asset!.totalCapitalizedCost - asset!.residualValue), 0))}
                     to={fmt(preview.newDepreciable)} />
                <Row label="Current book value"
                     from={fmt(asset!.currentBookValue)} to={fmt(preview.newBookValue)} />
                <Row label="Monthly depreciation"
                     from={asset!.usefulLifeMonths
                       ? fmt(round2(Math.max(round2(asset!.totalCapitalizedCost - asset!.residualValue), 0)
                             / asset!.usefulLifeMonths))
                       : "—"}
                     to={preview.newMonthly != null ? fmt(preview.newMonthly) : "—"} />
                <Row label="Still to be charged to profit"
                     from={fmt(Math.max(round2(Math.max(round2(asset!.totalCapitalizedCost - asset!.residualValue), 0)
                            - asset!.accumulatedDepreciation), 0))}
                     to={fmt(preview.newRemaining)} />
                <Row label="Depreciation already posted"
                     from={fmt(asset!.accumulatedDepreciation)} to="unchanged" />
              </dl>
              <p className="pt-1">
                {preview.difference < 0
                  ? `Cash already recorded as paid is reduced to the corrected amount and the difference is returned to the account it came from. No second payment and no second expense are created.`
                  : `The amount recorded as owed rises by ${fmt(Math.abs(preview.difference))}. No payment is created — correcting what something cost does not spend money.`}
              </p>
            </section>
          )}

          {hasDepreciation && (
            <p className="flex items-start gap-1.5 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-[11px] text-amber-900">
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              <span>
                {asset!.depreciationEntries} month(s) of depreciation have already been posted for this {term}.
                {" "}{notes.correctionDepreciationNote}
              </span>
            </p>
          )}

          {preview?.residualTooHigh && (
            <p className="flex items-start gap-1.5 rounded-md border border-red-300 bg-red-50 px-3 py-2 text-[11px] text-red-800">
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              The residual value of {fmt(asset!.residualValue)} would be more than the corrected cost of{" "}
              {fmt(preview.newTotal)}. Lower the residual value first — book value can never fall below it.
            </p>
          )}

          {preview && !preview.residualTooHigh && (preview.overDepreciated || preview.nothingLeft) && (
            <p className="flex items-start gap-1.5 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-[11px] text-amber-900">
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              After this correction there is nothing further to depreciate. The months already charged
              stand as charged and nothing more will be due — the {term} will read as fully depreciated.
            </p>
          )}

          {error && (
            <p className="rounded-md border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">{error}</p>
          )}

          <div className="flex justify-end gap-2 pt-1">
            <Button variant="outline" onClick={onClose} disabled={saving}>Cancel</Button>
            <Button onClick={save} disabled={!canSave}>
              {saving ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : null}
              Record correction
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function Row({ label, from, to }: { label: string; from: string; to: string }) {
  const same = from === to || to === "unchanged"
  return (
    <div className="flex justify-between gap-3">
      <dt>{label}</dt>
      <dd className="tabular-nums">
        {same ? (
          <span>{to === "unchanged" ? from : to} <span className="opacity-70">(unchanged)</span></span>
        ) : (
          <>
            <span className="line-through opacity-60">{from}</span>{" → "}
            <strong>{to}</strong>
          </>
        )}
      </dd>
    </div>
  )
}

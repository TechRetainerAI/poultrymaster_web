"use client"

/**
 * The cash count fields — counted amount against the system figure, with a live
 * variance, a reason and notes.
 *
 * Rendered inline on the reconciliation page rather than behind a dialog: a
 * page whose main action opens a modal reads as an afterthought. The `horizontal`
 * prop exists for that layout; the stacked default is what a dialog would want,
 * and is kept for the next surface that needs one.
 *
 * API-injected via props — nothing here imports from lib/api — so Poultry and
 * Generic can reuse it once migration 222 is ported.
 *
 * The expected/actual/variance treatment follows the water daily-closing submit
 * form: read-only expected figure beside the input, live variance, a 0.01
 * epsilon, emerald when it matches and amber when it does not.
 */

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { cashAccountVocabulary, type CashAccountVocabulary } from "./cash-account-vocabulary"

/** Below this the count is treated as matching. Same epsilon daily closing uses. */
export const CASH_COUNT_EPSILON = 0.01

export type CashCountReason = { value: string; label: string }

export type CashCountSubmit = {
  actualBalance: number
  reason: string | null
  notes: string | null
  reconciliationDate: string
}

/**
 * Prefill for an existing count — an unfinished draft being corrected, or a
 * reversed one being counted again. Same shape the form submits, so a round
 * trip through the API and back needs no translation.
 */
export type CashCountInitial = {
  actualBalance?: number | null
  reason?: string | null
  notes?: string | null
  reconciliationDate?: string | null
}

export function CashCountForm({
  systemBalance,
  reasons,
  fmtMoney,
  onSubmit,
  onDone,
  onCancel,
  submitLabel,
  disabled,
  /**
   * Words for the kind of account being reconciled — see cash-account-vocabulary.
   * Only labels and prose change; the arithmetic and what gets submitted do not.
   * Defaults to the neutral set so a caller that omits it still reads sensibly.
   */
  vocab = cashAccountVocabulary(null),
  /** Bumping this resets the fields — used when the page switches account. */
  resetKey,
  /** Seeds the fields on reset. See CashCountInitial. */
  initial,
  /**
   * What submitting does.
   *
   *   "draft" — saves the count and nothing else. Nothing reaches the ledger
   *             until it is posted, which is a separate, deliberate act.
   *   "post"  — the old one-shot behaviour: save and apply in one click.
   *
   * The wording of the button and the success toast follow from this, because
   * telling someone "Cash count posted" when no money has moved is how a draft
   * gets left unposted for a week.
   */
  intent = "post",
  /**
   * One row of fields instead of a stack. For the reconciliation page, where the
   * form sits above a full-width history table and every field has to fit on one
   * screen. The dialog keeps the stacked layout — it has no width to spend.
   */
  horizontal = false,
}: {
  systemBalance: number
  reasons: readonly CashCountReason[]
  fmtMoney: (n: number) => string
  /** Resolves with the adjustment transaction id, or null when it balanced. */
  onSubmit: (input: CashCountSubmit) => Promise<number | null>
  onDone?: () => void
  onCancel?: () => void
  submitLabel?: string
  disabled?: boolean
  vocab?: CashAccountVocabulary
  resetKey?: string | number
  initial?: CashCountInitial | null
  intent?: "draft" | "post"
  horizontal?: boolean
}) {
  const { toast } = useToast()
  const label = submitLabel ?? (intent === "draft"
    ? `Save ${vocab.recordNoun}`
    : `Post ${vocab.recordNoun}`)
  const [saving, setSaving] = useState(false)
  const [actual, setActual] = useState<number | undefined>(undefined)
  const [reason, setReason] = useState("")
  const [reasonNote, setReasonNote] = useState("")
  const [notes, setNotes] = useState("")
  const [when, setWhen] = useState(() => new Date().toISOString().split("T")[0])

  // Never carry one account's count over to another. With `initial`, the same
  // reset seeds the fields instead of blanking them — resetKey is what the page
  // changes to say "this is now a different count".
  useEffect(() => {
    if (initial) {
      setActual(initial.actualBalance ?? undefined)
      // A stored reason that is not in the list was typed under "Other" the
      // first time. Round-tripping it as free text keeps the edit faithful;
      // dropping it to "" would quietly discard the operator's explanation.
      const stored = initial.reason ?? ""
      const known = reasons.some((r) => r.value === stored)
      setReason(stored ? (known ? stored : "Other") : "")
      setReasonNote(stored && !known ? stored : "")
      setNotes(initial.notes ?? "")
      setWhen((initial.reconciliationDate ?? new Date().toISOString()).split("T")[0])
      return
    }
    setActual(undefined); setReason(""); setReasonNote(""); setNotes("")
    setWhen(new Date().toISOString().split("T")[0])
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resetKey])

  const counted = actual ?? 0
  const entered = actual !== undefined && !Number.isNaN(actual)
  const difference = useMemo(
    () => Math.round((counted - systemBalance) * 100) / 100,
    [counted, systemBalance],
  )
  const balanced = Math.abs(difference) < CASH_COUNT_EPSILON

  // A reason only means anything when there is something to explain.
  const reasonRequired = entered && !balanced
  const needsNote = reason === "Other"
  const canSubmit =
    entered && !saving && !disabled &&
    (!reasonRequired || (!!reason && (!needsNote || !!reasonNote.trim())))

  async function submit() {
    if (!canSubmit) return
    setSaving(true)
    try {
      await onSubmit({
        actualBalance: counted,
        // "Other" submits what was typed; a picked option submits itself.
        reason: reason ? (needsNote ? reasonNote.trim() : reason) : null,
        notes: notes.trim() || null,
        reconciliationDate: when,
      })
      toast(intent === "draft"
        ? {
            title: `${vocab.recordNoun[0].toUpperCase()}${vocab.recordNoun.slice(1)} saved`,
            // Deliberately not "posted", and deliberately conditional: the
            // difference shown here is measured against the ledger as it stands
            // now, and posting re-measures it. Promising an exact figure that
            // the post might legitimately change would be a lie by rounding.
            description: balanced
              ? `The ${vocab.balanceTerm.toLowerCase()} matches the system as things stand. Post it to confirm — nothing has moved yet.`
              : `Post it to move ${fmtMoney(Math.abs(difference))} ${difference > 0 ? "in" : "out"}. Nothing has moved yet.`,
          }
        : {
            title: balanced ? "Balanced" : `${vocab.recordNoun[0].toUpperCase()}${vocab.recordNoun.slice(1)} posted`,
            description: balanced
              ? "The counted amount matched the system. No adjustment was needed."
              : `${fmtMoney(Math.abs(difference))} ${difference > 0 ? "added" : "removed"} as an adjustment.`,
          })
      onDone?.()
    } catch (e: any) {
      toast({
        title: intent === "draft"
          ? `Couldn't save the ${vocab.recordNoun}`
          : `Couldn't post the ${vocab.recordNoun}`,
        description: e?.message, variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  const varianceLine = entered ? (
    <span className={cn("text-sm font-medium", balanced ? "text-emerald-700" : "text-amber-700")}>
      {balanced
        ? "Balanced — no adjustment needed"
        : `Difference: ${fmtMoney(difference)} ${difference > 0 ? "(over)" : "(short)"}`}
    </span>
  ) : (
    <span className="text-sm text-slate-500">
      System balance {fmtMoney(systemBalance)} — enter the {vocab.balanceTerm.toLowerCase()} to compare
    </span>
  )

  if (horizontal) {
    return (
      <div className="space-y-3">
        <div className="grid gap-3 md:grid-cols-12">
          <div className="space-y-1.5 md:col-span-3">
            <Label>{vocab.amountLabel}</Label>
            <NumberInput
              step="0.01"
              placeholder="0.00"
              disabled={disabled}
              value={actual ?? ""}
              onChange={(e) => setActual(e.target.value === "" ? undefined : parseFloat(e.target.value))}
            />
          </div>
          <div className="space-y-1.5 md:col-span-2">
            <Label>Date checked</Label>
            <Input type="date" disabled={disabled} value={when} onChange={(e) => setWhen(e.target.value)} />
          </div>
          <div className="space-y-1.5 md:col-span-3">
            <Label>Reason{reasonRequired ? " *" : <span className="text-slate-400"> (optional)</span>}</Label>
            <Select value={reason} onValueChange={(v) => { setReason(v); setReasonNote("") }} disabled={disabled}>
              <SelectTrigger><SelectValue placeholder={balanced ? "Not needed" : "Why the difference?"} /></SelectTrigger>
              <SelectContent>
                {reasons.map((r) => (
                  <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5 md:col-span-4">
            <Label>
              {needsNote
                ? <>Say what happened <span className="text-rose-600">*</span></>
                : <>Notes <span className="text-slate-400">(optional)</span></>}
            </Label>
            {/* When the reason is "Other" this field carries the explanation
                instead of general notes — one input, so the row keeps its shape
                rather than growing a sixth column. */}
            <Input
              disabled={disabled}
              value={needsNote ? reasonNote : notes}
              onChange={(e) => needsNote ? setReasonNote(e.target.value) : setNotes(e.target.value)}
              placeholder={needsNote ? "e.g. Till float returned from the depot" : "Anything that explains the count"}
            />
          </div>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="min-w-0">
            {varianceLine}
            {entered && !balanced && (
              <span className="ml-2 text-xs text-slate-500">
                A {difference > 0 ? "money-in" : "money-out"} adjustment of{" "}
                {fmtMoney(Math.abs(difference))} will be posted. Reversible.
              </span>
            )}
          </div>
          <div className="flex gap-2">
            {onCancel && <Button variant="ghost" onClick={onCancel} disabled={saving}>Cancel</Button>}
            <Button onClick={submit} disabled={!canSubmit}>
              {saving && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}
              {label}
            </Button>
          </div>
        </div>
      </div>
    )
  }

  // Stacked layout, used inside the reconciliation modal. Built from
  // FormSection/FormField so it reads as one of the system's dialogs rather
  // than a bare form dropped into a Dialog: coloured section band, the same
  // field rhythm, the same right-aligned ghost-Cancel footer. See the Adjust
  // balance dialog on the cash account page for the pattern being matched.
  return (
    <div className="space-y-4">
      <FormSection title={vocab.action} color="sky" columns={2}>
        <FormField label={`${vocab.amountLabel} *`}>
          <NumberInput
            step="0.01"
            placeholder="0.00"
            disabled={disabled}
            value={actual ?? ""}
            onChange={(e) => setActual(e.target.value === "" ? undefined : parseFloat(e.target.value))}
          />
          {/* Where to get the figure. The commonest way to get a reconciliation
              wrong is to type the ledger's own number back in. */}
          <p className="mt-1 text-[11px] leading-snug text-slate-500">{vocab.helper}</p>
        </FormField>

        <FormField label="System balance">
          {/* Read-only on purpose: this is what the books say, and the whole
              exercise is to disagree with it when reality does. */}
          <div className="flex h-10 items-center rounded-md border border-slate-200 bg-slate-50 px-3">
            <span className="font-semibold tabular-nums text-slate-900">{fmtMoney(systemBalance)}</span>
          </div>
          {entered && (
            <p className={cn("mt-1 text-[11px] font-medium leading-snug",
                             balanced ? "text-emerald-700" : "text-amber-700")}>
              {balanced
                ? "Balanced — no adjustment needed"
                : `Difference: ${fmtMoney(difference)} ${difference > 0 ? "(over)" : "(short)"}`}
            </p>
          )}
        </FormField>

        <FormField label="Date checked *">
          <Input type="date" disabled={disabled} value={when} onChange={(e) => setWhen(e.target.value)} />
        </FormField>

        <FormField label={reasonRequired ? "Reason *" : "Reason"}>
          <Select value={reason} onValueChange={(v) => { setReason(v); setReasonNote("") }} disabled={disabled}>
            <SelectTrigger>
              <SelectValue placeholder={balanced ? "Not needed" : "Why the difference?"} />
            </SelectTrigger>
            <SelectContent>
              {reasons.map((r) => (
                <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          {/* A fixed list never covers everything, and forcing someone into the
              nearest wrong option is worse than letting them type. */}
          {needsNote && (
            <Input
              autoFocus
              className="mt-2"
              disabled={disabled}
              value={reasonNote}
              onChange={(e) => setReasonNote(e.target.value)}
              placeholder="Say what happened"
            />
          )}
        </FormField>
      </FormSection>

      <FormSection title="Notes" color="slate" columns={1}>
        <FormField label="Notes (optional)">
          <Textarea rows={2} disabled={disabled} value={notes} onChange={(e) => setNotes(e.target.value)}
                    placeholder={`Anything that explains the ${vocab.recordNoun}`} />
        </FormField>
      </FormSection>

      {/* Say what pressing the button will do, in the words the ledger will use. */}
      {entered && (
        <p className="rounded-md border border-slate-200 bg-slate-50 p-2 text-[11px] leading-snug text-slate-600">
          {balanced
            ? `No adjustment will be created. The ${vocab.recordNoun} is recorded as balanced.`
            : `A ${difference > 0 ? "money-in" : "money-out"} adjustment of ${fmtMoney(Math.abs(difference))} will be posted to this account. The original transactions are untouched, and the ${vocab.recordNoun} can be reversed.`}
        </p>
      )}

      <div className="flex gap-3 justify-end pt-2">
        {onCancel && <Button type="button" variant="ghost" onClick={onCancel} disabled={saving}>Cancel</Button>}
        <Button onClick={submit} disabled={!canSubmit}>
          {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : label}
        </Button>
      </div>
    </div>
  )
}

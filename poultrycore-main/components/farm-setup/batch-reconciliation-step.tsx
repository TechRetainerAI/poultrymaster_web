"use client"

// 413 / Issue 2: Initial Farm Setup's batch-level reconciliation. Flock-level
// history (placed vs standing in a pen) stays on the flock cards above it; this
// asks only about birds that NEVER went into a pen. The server posts it through
// sppoultrybatchreconcile_post inside the setup transaction -- the same
// function as the Reconcile dialog on Flock Purchases.

import Link from "next/link"
import { ExternalLink, Plus, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import {
  emptyBatchReconciliation,
  type BatchReconciliationDraft, type BatchReconciliationView, type BatchSaleDraft,
} from "@/lib/farm-setup/wizard"

const money = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })

export function BatchReconciliationStep({ views, value, onChange, businessDate }: {
  views: BatchReconciliationView[]
  value: Record<string, BatchReconciliationDraft> | undefined
  onChange: (next: Record<string, BatchReconciliationDraft>) => void
  businessDate: string
}) {
  if (views.length === 0) return null
  const get = (key: string) => value?.[key] ?? emptyBatchReconciliation()
  const set = (key: string, patch: Partial<BatchReconciliationDraft>) =>
    onChange({ ...(value ?? {}), [key]: { ...get(key), ...patch } })
  const setSale = (key: string, saleKey: string, patch: Partial<BatchSaleDraft>) =>
    set(key, { sales: get(key).sales.map((s) => (s.key === saleKey ? { ...s, ...patch } : s)) })

  return (
    <div className="overflow-hidden rounded-xl border border-indigo-200">
      <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
        Birds never placed in a flock <span className="ml-1 rounded-full bg-white/25 px-2 py-0.5 text-xs">{views.length}</span>
      </div>
      <div className="space-y-4 bg-indigo-50/40 p-3 sm:p-4">
        <p className="text-sm text-slate-600">
          Worked out from the birds each flock was <b>originally</b> placed with, so a flock&apos;s own deaths are not counted
          again here. Nothing below creates a sale, cash or revenue.
        </p>
        {views.map((v) => {
          const r = get(v.batchKey)
          const tone = v.unexplained === 0 ? "text-emerald-700" : v.unexplained < 0 ? "text-red-600" : "text-amber-700"
          return (
            <div key={v.batchKey} className="space-y-3 rounded-lg border border-indigo-200 bg-white p-4 [&_input]:bg-white">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-medium text-slate-900">{v.label}</p>
                  <p className="text-sm text-slate-600">
                    {v.originalBirds.toLocaleString()} bought
                    {v.previouslyAccountedFor !== 0 && <> · {v.previouslyAccountedFor.toLocaleString()} already recorded</>}
                    {" "}· {v.placed.toLocaleString()} originally placed in flocks ·{" "}
                    <b>{v.neverPlaced.toLocaleString()} still not in a pen</b>
                  </p>
                  <p className="mt-1 text-sm font-medium text-slate-800">
                    What happened to the remaining {v.neverPlaced.toLocaleString()} birds that are not in a pen?
                  </p>
                </div>
                <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-1.5 text-right">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">Unexplained</p>
                  <p className={`text-xl font-bold tabular-nums ${tone}`}>{v.unexplained.toLocaleString()}</p>
                </div>
              </div>

              {v.previous && v.previouslyAccountedFor !== 0 && <AlreadyRecorded v={v} />}

              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-slate-700">
                    {v.previouslyAccountedFor !== 0 ? "Further sales not yet recorded" : "Previously sold"}
                  </span>
                  <Button type="button" size="sm" variant="outline"
                    onClick={() => set(v.batchKey, { sales: [...r.sales, { key: `${Date.now()}-${r.sales.length}`, quantity: "", pricePerBird: "", amountReceived: "", valueUnknown: false, date: businessDate }] })}>
                    <Plus className="mr-1 h-4 w-4" />Add historical sale
                  </Button>
                </div>
                {r.sales.map((s) => {
                  const total = s.valueUnknown ? null : Math.round((Number(s.quantity) || 0) * Math.round((Number(s.pricePerBird) || 0) * 100)) / 100
                  return (
                    <div key={s.key} className="grid grid-cols-2 items-end gap-2 rounded-md bg-slate-50 p-2 md:grid-cols-7">
                      <Field label="Birds"><NumberInput min="0" value={s.quantity} onChange={(e) => setSale(v.batchKey, s.key, { quantity: e.target.value })} /></Field>
                      <Field label="Date"><Input type="date" max={businessDate} value={s.date} onChange={(e) => setSale(v.batchKey, s.key, { date: e.target.value })} /></Field>
                      <Field label="Price per bird"><NumberInput min="0" step="0.01" disabled={s.valueUnknown} value={s.pricePerBird} onChange={(e) => setSale(v.batchKey, s.key, { pricePerBird: e.target.value })} /></Field>
                      <Field label="Sale value"><div className="flex h-10 items-center rounded-md border bg-white px-3 tabular-nums">{total == null ? "—" : money(total)}</div></Field>
                      <Field label="Already received"><NumberInput min="0" step="0.01" disabled={s.valueUnknown} placeholder={total == null ? "" : String(total)} value={s.amountReceived} onChange={(e) => setSale(v.batchKey, s.key, { amountReceived: e.target.value })} /></Field>
                      <label className="flex h-10 items-center gap-2 text-xs text-slate-700">
                        <Checkbox checked={s.valueUnknown} onCheckedChange={(c) => setSale(v.batchKey, s.key, { valueUnknown: c === true, pricePerBird: "", amountReceived: "" })} />
                        Value unknown
                      </label>
                      <Button type="button" size="sm" variant="ghost" className="text-red-600"
                        onClick={() => set(v.batchKey, { sales: r.sales.filter((x) => x.key !== s.key) })}><Trash2 className="h-4 w-4" /></Button>
                    </div>
                  )
                })}
                {r.sales.length > 0 && (
                  <p className="text-xs text-slate-500">
                    Historical sales value {money(v.saleValue)}. Recorded as history only — no cash today, no revenue in this period.
                    Money a customer still owes can be added as an opening debt from the batch&apos;s Reconcile action after setup.
                  </p>
                )}
              </div>

              <div className="grid grid-cols-2 gap-3 md:grid-cols-6">
                <Field label="Historical mortality"><NumberInput min="0" value={r.mortality} onChange={(e) => set(v.batchKey, { mortality: e.target.value })} /></Field>
                <Field label="Culled / removed"><NumberInput min="0" value={r.culled} onChange={(e) => set(v.batchKey, { culled: e.target.value })} /></Field>
                <Field label="Transferred outside the batch"><NumberInput min="0" value={r.transferred} onChange={(e) => set(v.batchKey, { transferred: e.target.value })} /></Field>
                <Field label="Other documented reason"><NumberInput min="0" value={r.other} onChange={(e) => set(v.batchKey, { other: e.target.value })} /></Field>
                <Field label={Number(r.other) > 0 ? "What were they? *" : "What were they?"}><Input value={r.otherNote} onChange={(e) => set(v.batchKey, { otherNote: e.target.value })} /></Field>
                <Field label="Still alive, not yet in a flock"><NumberInput min="0" value={r.stillAlive} onChange={(e) => set(v.batchKey, { stillAlive: e.target.value })} /></Field>
              </div>
              <p className={`text-xs ${tone}`}>
                {v.unexplained === 0
                  ? "Fully accounted for."
                  : v.unexplained < 0
                    ? `These add up to ${v.explained.toLocaleString()} — more than the ${v.neverPlaced.toLocaleString()} not in a pen.`
                    : v.isHistorical
                      ? `${v.unexplained.toLocaleString()} still to explain. A batch you already had must be fully accounted for before setup can finish (save the draft and come back if you need to find out).`
                      : `${v.unexplained.toLocaleString()} not explained — for a new purchase they stay available to place in a flock later.`}
              </p>
            </div>
          )
        })}
      </div>
    </div>
  )
}

/**
 * Dispositions already POSTED against this batch's never-placed birds before
 * the wizard opened. Shown as existing records -- read-only, never sent again.
 * Corrections go through the batch's own Reconcile / reverse workflow.
 */
function AlreadyRecorded({ v }: { v: BatchReconciliationView }) {
  const p = v.previous!
  const rows: [string, number][] = ([
    ["Historical sales", p.previouslySold],
    ["Historical mortality", p.previousMortality],
    ["Culled / removed", p.previouslyCulled],
    ["Transferred out", p.previouslyTransferred],
    ["Other removals", p.previousOther],
    ["Birds added", -p.previousAdditions],
  ] as [string, number][]).filter(([, q]) => q !== 0)
  return (
    <div className="rounded-md border border-slate-200 bg-slate-50 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-sm font-medium text-slate-700">
          Already recorded{p.lastReconciliationNo ? ` (last: ${p.lastReconciliationNo})` : ""} — not posted again
        </span>
        {v.existingBatchId != null && (
          <Link href={`/poultry/reports/batch-bird-reconciliation?batchId=${v.existingBatchId}`} target="_blank"
            className="inline-flex items-center gap-1 text-xs font-medium text-indigo-700 hover:underline">
            View source<ExternalLink className="h-3 w-3" />
          </Link>
        )}
      </div>
      <table className="mt-2 w-full text-sm">
        <tbody>
          {rows.map(([label, q]) => (
            <tr key={label}>
              <td className="py-0.5 text-slate-600">{label}</td>
              <td className="py-0.5 text-right tabular-nums text-slate-900">{q > 0 ? "−" : "+"}{Math.abs(q).toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="mt-1 text-xs text-slate-500">
        These birds are already accounted for, so you are not asked about them again. To correct one, reverse it from the
        batch&apos;s reconciliation history.
      </p>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <span className="block text-xs font-medium text-slate-600">{label}</span>
      {children}
    </div>
  )
}

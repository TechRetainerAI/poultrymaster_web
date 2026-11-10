"use client"

// What Edit Flock shows about a flock's birds: how it was registered, what
// happened to the difference, and what has happened since.
// Everything comes from posted records (GET /api/Flock/{id}/edit-context), so it
// is the same after a reload, on another device, and on both the Flocks page
// and the Farm Setup partial view.
//
// For a flock with an opening position (Initial Farm Setup or "existing flock")
// the history is edited right here and saved with the flock
// (PUT /api/Flock/{id} OpeningHistory). The server posts only the ledger
// DIFFERENCE, so nothing is ever recorded twice. Numbers that do not add up are
// warnings, never a block.

import { Checkbox } from "@/components/ui/checkbox"
import { NumberInput } from "@/components/ui/number-input"
import { FlockModeSelector } from "@/components/poultry/existing-flock-fields"
import type { FlockEditContext } from "@/lib/api/flock"
import { formatDateKey, businessDatePart, fmtInstant } from "@/lib/utils/company-datetime"

const n = (v: number | null | undefined) => Number(v ?? 0).toLocaleString()
const day = (v: string | null | undefined) => formatDateKey(businessDatePart(v)) || "—"
const num = (s: string) => Math.max(0, Math.trunc(Number(s) || 0))

/** The opening history as typed in Edit Flock. Strings so a cleared box stays empty. */
export interface OpeningHistoryDraft {
  placed: string
  live: string
  known: boolean
  mort: string
  sold: string
  culled: string
  moved: string
}

export function openingDraftFrom(ctx: FlockEditContext | null): OpeningHistoryDraft | null {
  const o = ctx?.opening
  if (!o) return null
  return {
    placed: String(o.originallyPlaced ?? 0),
    live: String(o.openingLiveBirds ?? 0),
    known: o.historyKnown,
    mort: o.historicalMortality ? String(o.historicalMortality) : "",
    sold: o.historicalSold ? String(o.historicalSold) : "",
    culled: o.historicalCulled ? String(o.historicalCulled) : "",
    moved: o.historicalTransferred ? String(o.historicalTransferred) : "",
  }
}

/** What PUT /api/Flock/{id} takes as OpeningHistory. */
export function openingDraftToEdit(d: OpeningHistoryDraft) {
  return {
    originallyPlaced: num(d.placed),
    openingLiveBirds: num(d.live),
    historyKnown: d.known,
    historicalMortality: d.known ? num(d.mort) : 0,
    historicalSold: d.known ? num(d.sold) : 0,
    historicalCulled: d.known ? num(d.culled) : 0,
    historicalTransferred: d.known ? num(d.moved) : 0,
  }
}

/**
 * Warnings only -- nothing here stops the save. The server applies the same
 * rules (raises placed to the live count; an over-explained breakdown is saved
 * as "not yet explained") and returns its own warnings.
 */
export function openingDraftWarnings(ctx: FlockEditContext | null, d: OpeningHistoryDraft | null): string[] {
  const o = ctx?.opening
  if (!o || !d) return []
  const w: string[] = []
  const placed = num(d.placed), live = num(d.live)
  const missing = placed - live
  const explained = num(d.mort) + num(d.sold) + num(d.culled) + num(d.moved)
  if (live > placed) {
    w.push(`${live.toLocaleString()} alive is more than the ${placed.toLocaleString()} originally placed — originally placed will be saved as ${live.toLocaleString()}.`)
  } else if (d.known && explained > missing) {
    w.push(`The breakdown adds up to ${explained.toLocaleString()}, but only ${missing.toLocaleString()} birds are missing. It will be saved as "not yet explained" until it matches.`)
  }
  const recs = ctx?.position?.productionrecordcount ?? 0
  if (recs > 0 && (placed !== o.originallyPlaced || live !== o.openingLiveBirds)) {
    w.push(`This flock already has ${recs.toLocaleString()} production record(s). Live birds now come from the latest record, so check it still matches.`)
  }
  return w
}

export function FlockHistoryPanel({ ctx, draft, onDraftChange, disabled }: {
  ctx: FlockEditContext
  /** When given (a flock with an opening position), the history is editable here. */
  draft?: OpeningHistoryDraft | null
  onDraftChange?: (d: OpeningHistoryDraft) => void
  disabled?: boolean
}) {
  const o = ctx.opening
  const p = ctx.position
  const d = o && draft && onDraftChange ? draft : null
  const placed = d ? num(d.placed) : (o?.originallyPlaced ?? p?.originallyplaced ?? 0)
  const live = d ? num(d.live) : (o?.openingLiveBirds ?? 0)
  const reduction = Math.max(0, placed - live)
  const known = d ? d.known : !!o?.historyKnown
  const parts = d
    ? { mort: num(d.mort), sold: num(d.sold), culled: num(d.culled), moved: num(d.moved) }
    : { mort: o?.historicalMortality ?? 0, sold: o?.historicalSold ?? 0, culled: o?.historicalCulled ?? 0, moved: o?.historicalTransferred ?? 0 }
  const explained = parts.mort + parts.sold + parts.culled + parts.moved
  const unexplained = !known ? reduction : Math.max(0, reduction - explained)
  const breakdown: [string, number][] = ([
    ["Died", parts.mort], ["Sold", parts.sold], ["Culled", parts.culled],
    ["Transferred out", parts.moved], ["Not explained", unexplained],
  ] as [string, number][]).filter(([, q]) => q > 0)
  const set = (patch: Partial<OpeningHistoryDraft>) => { if (d && onDraftChange) onDraftChange({ ...d, ...patch }) }
  const liveNow = p?.currentlivebirds ?? live
  const sinceLost = (p?.recordedmortality ?? 0) + (p?.birdssold ?? 0) + (p?.birdsculled ?? 0) + (p?.birdstransferred ?? 0)

  return (
    <div className="rounded-xl border border-slate-200 overflow-hidden">
      <div className="bg-slate-700 px-4 py-2 text-sm font-semibold text-white">
        {o ? "Bird history — originally placed, current and the difference" : "Bird history"}
      </div>
      <div className="space-y-4 bg-white p-4">
        <FlockModeSelector mode={ctx.mode === "Existing" ? "existing" : "new"} onChange={() => {}} disabled />

        {d ? (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <L label="Originally placed">
              <NumberInput min="0" value={d.placed} disabled={disabled} onChange={(e) => set({ placed: e.target.value })} />
            </L>
            <L label={`Birds on ${day(o!.effectiveDate)}`}>
              <NumberInput min="0" value={d.live} disabled={disabled} onChange={(e) => set({ live: e.target.value })} />
            </L>
            <Figure label="Difference" value={reduction} tone={reduction > 0 ? "amber" : undefined} />
            <Figure label="Live birds now" value={liveNow} tone="emerald" />
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Figure label="Originally placed" value={placed} />
            {o && <Figure label={`Birds on ${day(o.effectiveDate)}`} value={live} />}
            {o && <Figure label="Difference" value={reduction} tone={reduction > 0 ? "amber" : undefined} />}
            <Figure label="Live birds now" value={liveNow} tone="emerald" />
          </div>
        )}

        {o && (
          <div className="rounded-md bg-slate-50 p-3 text-sm space-y-2">
            <p className="font-medium text-slate-800">
              {reduction === 0
                ? "No birds were missing when it was registered."
                : `How the difference of ${n(reduction)} was allocated (${n(placed)} placed − ${n(live)} current)`}
            </p>
            {d && reduction > 0 && (
              <>
                <label className="flex items-center gap-2 text-sm text-slate-700">
                  <Checkbox checked={d.known} onCheckedChange={(c) => set({ known: c === true })} disabled={disabled} />
                  We know what happened to them
                </label>
                {d.known && (
                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                    <L label="Died"><NumberInput min="0" value={d.mort} disabled={disabled} onChange={(e) => set({ mort: e.target.value })} /></L>
                    <L label="Sold (historical)"><NumberInput min="0" value={d.sold} disabled={disabled} onChange={(e) => set({ sold: e.target.value })} /></L>
                    <L label="Culled"><NumberInput min="0" value={d.culled} disabled={disabled} onChange={(e) => set({ culled: e.target.value })} /></L>
                    <L label="Transferred out"><NumberInput min="0" value={d.moved} disabled={disabled} onChange={(e) => set({ moved: e.target.value })} /></L>
                  </div>
                )}
              </>
            )}
            {!d && breakdown.length > 0 && (
              <ul className="grid grid-cols-2 gap-x-6 text-slate-600 sm:grid-cols-3">
                {breakdown.map(([label, q]) => <li key={label}>{label}: <b className="tabular-nums text-slate-900">{n(q)}</b></li>)}
              </ul>
            )}
            {reduction > 0 && (
              <p className={`text-xs ${unexplained > 0 || (known && explained > reduction) ? "text-amber-700" : "text-emerald-700"}`}>
                {known && explained > reduction
                  ? `The breakdown adds up to ${n(explained)} — ${n(explained - reduction)} more than are missing.`
                  : unexplained > 0 ? `${n(unexplained)} not explained yet.` : "All of the difference is explained."}
                {o.source ? ` Registered from ${o.source}.` : ""}
                {o.startDateEstimated ? " Start date was estimated." : ""}
              </p>
            )}
          </div>
        )}

        {p && (sinceLost > 0 || p.productionrecordcount > 0) && (
          <div className="rounded-md border border-slate-200 p-3 text-sm text-slate-700">
            <p className="font-medium text-slate-800">Since {o ? "it was registered" : "it was placed"}</p>
            <p className="mt-1 text-xs text-slate-600">
              {n(o ? live : placed)} at the start − {n(p.recordedmortality)} recorded deaths − {n(p.birdssold)} sold
              {p.birdsculled ? ` − ${n(p.birdsculled)} culled` : ""}
              {p.birdstransferred ? ` − ${n(p.birdstransferred)} transferred` : ""}
              {" "}→ <b className="text-emerald-700">{n(liveNow)} live now</b>
              {" "}({n(p.productionrecordcount)} production record{p.productionrecordcount === 1 ? "" : "s"}).
            </p>
          </div>
        )}

        {ctx.movements.length > 0 && (
          <div>
            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Posted bird movements</p>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-slate-500">
                    <th className="py-1 pr-3 font-medium">Effective</th>
                    <th className="py-1 pr-3 font-medium">Entered</th>
                    <th className="py-1 pr-3 font-medium">Movement</th>
                    <th className="py-1 pr-3 text-right font-medium">Birds</th>
                  </tr>
                </thead>
                <tbody>
                  {ctx.movements.map((m) => (
                    <tr key={`${m.kind}-${m.id}`} className="border-t border-slate-100">
                      <td className="py-1 pr-3 whitespace-nowrap">{day(m.effectiveDate)}</td>
                      <td className="py-1 pr-3 whitespace-nowrap text-slate-500">{m.postedAt ? fmtInstant(m.postedAt) : "time not recorded"}</td>
                      <td className="py-1 pr-3">{m.reason || m.type}{m.note ? <span className="block text-xs text-slate-500">{m.note}</span> : null}</td>
                      <td className={`py-1 pr-3 text-right tabular-nums ${Number(m.quantity) < 0 ? "text-red-600" : "text-green-700"}`}>
                        {Number(m.quantity) > 0 ? "+" : ""}{n(Number(m.quantity))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function Figure({ label, value, tone }: { label: string; value: number; tone?: "amber" | "emerald" }) {
  const cls = tone === "amber" ? "text-amber-700" : tone === "emerald" ? "text-emerald-700" : "text-slate-900"
  return (
    <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">{label}</p>
      <p className={`text-lg font-bold tabular-nums ${cls}`}>{n(value)}</p>
    </div>
  )
}

function L({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-1"><span className="block text-xs font-medium text-slate-600">{label}</span>{children}</div>
}

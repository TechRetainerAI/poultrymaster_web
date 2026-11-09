"use client"

// 413 / Issue 5: "New flock" vs "Existing flock — already operating", and for
// an existing flock the birds originally placed, the birds remaining today and
// what happened to the difference. Shared by the Add Flock dialog (Flocks page
// and Farm Setup → Flocks, which is the same view) and the /flocks/new page.
// The server (POST api/Flock/existing -> OpeningFlockPoster) applies the same
// rules as previewFlockHistory and Initial Farm Setup.

import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { previewFlockHistory, type FlockHistoryDraft } from "@/lib/flocks/bird-reconciliation"

export type FlockCreationMode = "new" | "existing"

export interface ExistingFlockDraft extends Omit<FlockHistoryDraft, "originallyPlaced"> {
  asOfDate: string
}

export const emptyExistingFlockDraft = (today: string): ExistingFlockDraft => ({
  currentLiveBirds: "", historyKnown: true,
  historicalMortality: "", historicalSold: "", historicalCulled: "", historicalTransferred: "",
  asOfDate: today,
})

export function FlockModeSelector({ mode, onChange, disabled }: { mode: FlockCreationMode; onChange: (m: FlockCreationMode) => void; disabled?: boolean }) {
  const opt = (value: FlockCreationMode, title: string, hint: string) => (
    <label className={`flex flex-1 cursor-pointer items-start gap-2 rounded-lg border p-3 text-sm ${mode === value ? "border-blue-500 bg-blue-50" : "border-slate-200 bg-white"}`}>
      <input type="radio" name="flock-mode" className="mt-1" checked={mode === value} disabled={disabled} onChange={() => onChange(value)} />
      <span>
        <span className="block font-medium text-slate-900">{title}</span>
        <span className="block text-xs text-slate-500">{hint}</span>
      </span>
    </label>
  )
  return (
    <div className="flex flex-col gap-2 sm:flex-row" role="radiogroup" aria-label="Is this a new or an existing flock?">
      {opt("new", "New flock — birds being placed now", "Birds now = birds placed from the batch.")}
      {opt("existing", "Existing flock — already operating", "Some birds have already died, been sold or moved.")}
    </div>
  )
}

/** The existing-flock part. `placed` is the dialog's own "birds originally placed" field. */
export function ExistingFlockFields({ placed, draft, onChange, maxDate, disabled }: {
  placed: number
  draft: ExistingFlockDraft
  onChange: (d: ExistingFlockDraft) => void
  maxDate?: string
  disabled?: boolean
}) {
  const p = previewFlockHistory({ ...draft, originallyPlaced: placed })
  const set = (patch: Partial<ExistingFlockDraft>) => onChange({ ...draft, ...patch })
  return (
    <div className="space-y-3 rounded-lg border border-amber-200 bg-amber-50/50 p-3">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 sm:items-end">
        <div className="space-y-1">
          <Label className="text-sm font-medium text-slate-700 whitespace-nowrap">Birds remaining now *</Label>
          <NumberInput min="0" value={draft.currentLiveBirds} disabled={disabled}
            onChange={(e) => set({ currentLiveBirds: e.target.value })} />
        </div>
        <div className="space-y-1">
          <Label className="text-sm font-medium text-slate-700 whitespace-nowrap">Counted on *</Label>
          <Input type="date" value={draft.asOfDate} max={maxDate} disabled={disabled} onChange={(e) => set({ asOfDate: e.target.value })} />
        </div>
        <div className="space-y-1">
          <Label className="text-sm font-medium text-slate-700 whitespace-nowrap">Historical difference</Label>
          <div className="flex h-9 items-center rounded-md border border-slate-200 bg-white px-3 font-semibold tabular-nums text-amber-700">
            {p.difference.toLocaleString()}
          </div>
        </div>
      </div>

      {p.difference > 0 && (
        <>
          <label className="flex items-center gap-2 text-sm text-slate-700">
            <Checkbox checked={!draft.historyKnown} disabled={disabled}
              onCheckedChange={(v) => set(v === true
                ? { historyKnown: false, historicalMortality: "", historicalSold: "", historicalCulled: "", historicalTransferred: "" }
                : { historyKnown: true })} />
            I don&apos;t know what happened to them
          </label>
          {draft.historyKnown && (
            <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
              {([
                ["historicalMortality", "Historical mortality"],
                ["historicalSold", "Previously sold"],
                ["historicalCulled", "Culled"],
                ["historicalTransferred", "Transferred out"],
              ] as const).map(([k, label]) => (
                <div key={k} className="space-y-1">
                  <Label className="text-xs font-medium text-slate-600">{label}</Label>
                  <NumberInput min="0" value={draft[k]} disabled={disabled} onChange={(e) => set({ [k]: e.target.value } as Partial<ExistingFlockDraft>)} />
                </div>
              ))}
              <div className="space-y-1">
                <Label className="text-xs font-medium text-slate-600">Other / unknown</Label>
                <div className="flex h-9 items-center rounded-md border border-slate-200 bg-slate-50 px-3 tabular-nums text-slate-700">{p.other.toLocaleString()}</div>
              </div>
            </div>
          )}
        </>
      )}

      <p className={`text-xs ${p.problem ? "text-red-600" : "text-slate-600"}`}>
        {p.problem ?? (p.difference === 0
          ? "No birds are missing: the flock starts with every bird placed."
          : `${placed.toLocaleString()} placed from the batch, ${p.live.toLocaleString()} standing now. The ${p.difference.toLocaleString()} gone are recorded once, as this flock's opening history — not as today's deaths and not as a sale. ${p.other > 0 ? `${p.other.toLocaleString()} unexplained are recorded as “other”, never as mortality.` : ""}`)}
      </p>
    </div>
  )
}

/** The body for createExistingFlock, or the reason it cannot be sent. */
export function existingFlockHistory(placed: number, draft: ExistingFlockDraft) {
  const p = previewFlockHistory({ ...draft, originallyPlaced: placed })
  const n = (v: string | number) => Math.max(0, Math.trunc(Number(v) || 0))
  return {
    problem: p.problem ?? (String(draft.currentLiveBirds).trim() === "" ? "Enter how many birds are remaining today." : !draft.asOfDate ? "Enter the date the birds were counted." : null),
    history: {
      originallyPlaced: p.placed,
      currentLiveBirds: p.live,
      historyKnown: draft.historyKnown,
      historicalMortality: draft.historyKnown ? n(draft.historicalMortality) : 0,
      historicalSold: draft.historyKnown ? n(draft.historicalSold) : 0,
      historicalCulled: draft.historyKnown ? n(draft.historicalCulled) : 0,
      historicalTransferred: draft.historyKnown ? n(draft.historicalTransferred) : 0,
    },
  }
}

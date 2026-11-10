"use client"

// Weigh-ins (migration 400) -- broilers, phase 2.
//
// One flock at a time: its growth curve (average weight by age), the weigh-ins
// behind it, and a form to add one, either bird by bird off the scale or as the
// summary the farm wrote down. The server derives every figure from individual
// weights; the preview here is lib/poultry/weigh-in-stats.ts, the same rule.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts"
import { Loader2, Pencil, Plus, Scale, Trash2 } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
import { ReasonDialog } from "@/components/closing/daily-closing-dialogs"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useBusinessDate } from "@/hooks/use-business-date"
import { getUserContext } from "@/lib/api/config"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { createWeighIn, deleteWeighIn, listWeighIns, updateWeighIn, type FlockWeighIn } from "@/lib/api/weigh-ins"
import { isBroilerFlock } from "@/lib/poultry/flock-type"
import { computeWeighInStats, formatWeight, parseWeights, type WeightUnit } from "@/lib/poultry/weigh-in-stats"
import { WEIGH_IN_DELETE_REASONS } from "@/lib/reversal-reasons"

const PAGE = "/poultry-weigh-ins"

export default function WeighInsPage() {
  return (
    <Suspense fallback={null}>
      <WeighIns />
    </Suspense>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  const logout = useLogout()
  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">{children}</div>
        </main>
      </div>
    </div>
  )
}

const fmtDate = (iso: string) => {
  const d = new Date(`${iso.slice(0, 10)}T00:00:00`)
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleDateString(undefined, { day: "2-digit", month: "short", year: "numeric" })
}
const fmtPct = (n: number | null | undefined, dp = 1) => (n === null || n === undefined ? "—" : `${Number(n).toFixed(dp)}%`)

function WeighIns() {
  const router = useRouter()
  const params = useSearchParams()
  const { toast } = useToast()
  const { businessDate } = useBusinessDate()

  const [flocks, setFlocks] = useState<Flock[]>([])
  const [flocksLoading, setFlocksLoading] = useState(true)
  const [rows, setRows] = useState<FlockWeighIn[]>([])
  const [rowsLoading, setRowsLoading] = useState(false)
  const [error, setError] = useState("")
  const [editing, setEditing] = useState<FlockWeighIn | "new" | null>(null)
  const [deleting, setDeleting] = useState<FlockWeighIn | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)

  // Open flocks first, broilers before layers; closed flocks after, for history.
  const { openFlocks, closedFlocks } = useMemo(() => {
    const live = flocks.filter((f) => !(f as { isDeleted?: boolean }).isDeleted)
    const byType = (a: Flock, b: Flock) =>
      Number(isBroilerFlock(b)) - Number(isBroilerFlock(a)) || a.name.localeCompare(b.name)
    return {
      openFlocks: live.filter((f) => !f.closedDate).sort(byType),
      closedFlocks: live.filter((f) => !!f.closedDate).sort(byType),
    }
  }, [flocks])

  const selectedId = Number(params.get("flockId")) || openFlocks[0]?.flockId || closedFlocks[0]?.flockId || 0
  const selected = flocks.find((f) => f.flockId === selectedId) ?? null
  const isClosed = !!selected?.closedDate

  const selectFlock = (id: number) => router.replace(`${PAGE}?flockId=${id}`)

  useEffect(() => {
    const { userId, farmId } = getUserContext()
    getFlocks(userId, farmId)
      .then((r) => setFlocks(r.success ? r.data ?? [] : []))
      .finally(() => setFlocksLoading(false))
  }, [])

  const loadRows = useCallback(async () => {
    if (!selectedId) { setRows([]); return }
    setRowsLoading(true)
    setError("")
    try {
      setRows(await listWeighIns(selectedId))
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load the weigh-ins.")
    } finally {
      setRowsLoading(false)
    }
  }, [selectedId])

  useEffect(() => { void loadRows() }, [loadRows])

  const latest = rows.length ? rows[rows.length - 1] : null

  const confirmDelete = async (reason: string) => {
    if (!deleting) return
    setDeleteBusy(true)
    try {
      await deleteWeighIn(deleting.weighInId, reason)
      toast({ title: "Weigh-in deleted" })
      setDeleting(null)
      await loadRows()
    } catch (e) {
      toast({ title: "Not deleted", description: e instanceof Error ? e.message : String(e), variant: "destructive" })
    } finally {
      setDeleteBusy(false)
    }
  }

  return (
    <Shell>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-orange-100">
            <Scale className="h-5 w-5 text-orange-700" />
          </div>
          <div className="min-w-0">
            <h1 className="text-2xl font-bold text-slate-900">Weigh-ins</h1>
            <p className="text-sm text-slate-600">Weigh a sample of birds to follow how a flock is growing.</p>
          </div>
        </div>
        <Button onClick={() => setEditing("new")} disabled={!selected || isClosed}
                className="bg-orange-500 text-white hover:bg-orange-600">
          <Plus className="mr-1 h-4 w-4" /> New weigh-in
        </Button>
      </div>

      <Card>
        <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-end">
          <div className="w-full space-y-1.5 sm:max-w-sm">
            <Label>Flock</Label>
            <Select value={selectedId ? String(selectedId) : ""} onValueChange={(v) => selectFlock(Number(v))}
                    disabled={flocksLoading || flocks.length === 0}>
              <SelectTrigger><SelectValue placeholder={flocksLoading ? "Loading flocks…" : "No flocks yet"} /></SelectTrigger>
              <SelectContent>
                {openFlocks.length > 0 && (
                  <SelectGroup>
                    <SelectLabel>Running</SelectLabel>
                    {openFlocks.map((f) => (
                      <SelectItem key={f.flockId} value={String(f.flockId)}>
                        {f.name}{isBroilerFlock(f) ? " · Broiler" : ""}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                )}
                {closedFlocks.length > 0 && (
                  <SelectGroup>
                    <SelectLabel>Closed</SelectLabel>
                    {closedFlocks.map((f) => (
                      <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}</SelectItem>
                    ))}
                  </SelectGroup>
                )}
              </SelectContent>
            </Select>
          </div>
          {selected && (
            <div className="flex flex-wrap items-center gap-2 text-sm text-slate-600">
              {isBroilerFlock(selected) && <Badge className="border border-orange-200 bg-orange-100 text-orange-800">Broiler</Badge>}
              {selected.breed && <span>{selected.breed}</span>}
              <span>· started {fmtDate(selected.startDate)}</span>
              {isClosed && <Badge variant="secondary">Closed: weigh-ins are read-only</Badge>}
            </div>
          )}
        </CardContent>
      </Card>

      {error && <p className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

      {/* ---- Headline figures ------------------------------------------- */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Tile label="Latest average" value={latest ? formatWeight(latest.avgWeightG) : "—"}
              sub={latest ? `Day ${latest.ageInDays} · ${fmtDate(latest.weighDate)}` : "No weigh-ins yet"} />
        <Tile label="Gain per day" value={latest?.dailyGainG != null ? `${Number(latest.dailyGainG).toFixed(1)} g` : "—"}
              sub={latest?.daysSincePrev ? `over the last ${latest.daysSincePrev} days` : "Needs two weigh-ins"} />
        <Tile label="Uniformity" value={fmtPct(latest?.uniformityPct)}
              sub="Birds within ±10% of the average" />
        <Tile label="Weigh-ins" value={String(rows.length)}
              sub={rows.length ? `${rows.reduce((a, r) => a + r.sampleSize, 0).toLocaleString()} birds weighed` : "—"} />
      </div>

      {/* ---- Growth curve ------------------------------------------------ */}
      <Card>
        <CardContent className="p-4">
          <h2 className="text-base font-semibold text-slate-900">Average weight by age</h2>
          <p className="mb-3 text-xs text-slate-500">Each point is one weigh-in. Hover a point for the details.</p>
          {rowsLoading ? (
            <div className="flex h-64 items-center justify-center text-slate-500"><Loader2 className="h-5 w-5 animate-spin" /></div>
          ) : rows.length === 0 ? (
            <div className="flex h-40 items-center justify-center rounded-md border border-dashed text-sm text-slate-500">
              {selected ? "No weigh-ins for this flock yet." : "Choose a flock."}
            </div>
          ) : (
            <GrowthChart rows={rows} />
          )}
        </CardContent>
      </Card>

      {/* ---- The weigh-ins ------------------------------------------------ */}
      {rows.length > 0 && (
        <Card>
          <CardContent className="p-0">
            <div className="hidden overflow-x-auto md:block">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
                  <tr>
                    <th className="px-4 py-2">Date</th>
                    <th className="px-4 py-2 text-right">Age (days)</th>
                    <th className="px-4 py-2 text-right">Birds weighed</th>
                    <th className="px-4 py-2 text-right">Average</th>
                    <th className="px-4 py-2 text-right">Gain / day</th>
                    <th className="px-4 py-2 text-right">Uniformity</th>
                    <th className="px-4 py-2 text-right">CV</th>
                    <th className="px-4 py-2 text-right">Lightest – heaviest</th>
                    <th className="px-4 py-2" />
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {[...rows].reverse().map((r) => (
                    <tr key={r.weighInId} className="hover:bg-slate-50">
                      <td className="px-4 py-2">
                        {fmtDate(r.weighDate)}
                        {r.notes && <div className="text-xs text-slate-500">{r.notes}</div>}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{r.ageInDays}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{r.sampleSize.toLocaleString()}</td>
                      <td className="px-4 py-2 text-right font-medium tabular-nums">{formatWeight(r.avgWeightG)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{r.dailyGainG != null ? `${Number(r.dailyGainG).toFixed(1)} g` : "—"}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{fmtPct(r.uniformityPct)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{fmtPct(r.cvPct, 2)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">
                        {r.minWeightG != null && r.maxWeightG != null ? `${formatWeight(r.minWeightG)} – ${formatWeight(r.maxWeightG)}` : "—"}
                      </td>
                      <td className="px-4 py-2 text-right">
                        <RowActions disabled={isClosed} onEdit={() => setEditing(r)} onDelete={() => setDeleting(r)} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {/* Phone: one card per weigh-in. */}
            <div className="divide-y md:hidden">
              {[...rows].reverse().map((r) => (
                <div key={r.weighInId} className="flex items-start justify-between gap-3 p-4">
                  <div className="min-w-0 space-y-0.5 text-sm">
                    <div className="font-semibold text-slate-900">{formatWeight(r.avgWeightG)} <span className="font-normal text-slate-500">· day {r.ageInDays}</span></div>
                    <div className="text-slate-600">{fmtDate(r.weighDate)} · {r.sampleSize} birds</div>
                    <div className="text-xs text-slate-500">
                      Gain {r.dailyGainG != null ? `${Number(r.dailyGainG).toFixed(1)} g/day` : "—"} · Uniformity {fmtPct(r.uniformityPct)}
                    </div>
                  </div>
                  <RowActions disabled={isClosed} onEdit={() => setEditing(r)} onDelete={() => setDeleting(r)} />
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {editing && selected && (
        <WeighInDialog
          flocks={openFlocks}
          defaultFlockId={selected.flockId}
          existing={editing === "new" ? null : editing}
          maxDate={businessDate}
          onClose={() => setEditing(null)}
          onSaved={async (flockId) => {
            setEditing(null)
            if (flockId !== selectedId) selectFlock(flockId)
            else await loadRows()
          }}
        />
      )}

      <ReasonDialog
        open={!!deleting}
        onOpenChange={(v) => { if (!v) setDeleting(null) }}
        title="Delete this weigh-in?"
        description={deleting ? `${formatWeight(deleting.avgWeightG)} on ${fmtDate(deleting.weighDate)}. It is kept in the record as deleted, with your reason.` : ""}
        confirmLabel="Delete weigh-in"
        busy={deleteBusy}
        destructive
        options={WEIGH_IN_DELETE_REASONS}
        onConfirm={confirmDelete}
      />
    </Shell>
  )
}

function Tile({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs font-medium uppercase tracking-wide text-slate-500">{label}</div>
        <div className="mt-1 text-2xl font-semibold tabular-nums text-slate-900">{value}</div>
        <div className="mt-0.5 text-xs text-slate-500">{sub}</div>
      </CardContent>
    </Card>
  )
}

function RowActions({ disabled, onEdit, onDelete }: { disabled: boolean; onEdit: () => void; onDelete: () => void }) {
  return (
    <div className="flex shrink-0 justify-end gap-1">
      <Button variant="ghost" size="icon" className="h-8 w-8" disabled={disabled} onClick={onEdit} aria-label="Edit weigh-in">
        <Pencil className="h-4 w-4" />
      </Button>
      <Button variant="ghost" size="icon" className="h-8 w-8 text-red-600 hover:text-red-700" disabled={disabled} onClick={onDelete} aria-label="Delete weigh-in">
        <Trash2 className="h-4 w-4" />
      </Button>
    </div>
  )
}

// One series, one axis: average weight (g) against age (days). Thin line,
// visible points, recessive grid; the table above is the data view.
const LINE = "#ea580c"   // orange-600, the poultry accent

function GrowthChart({ rows }: { rows: FlockWeighIn[] }) {
  const data = rows.map((r) => ({ age: r.ageInDays, avg: Number(r.avgWeightG), row: r }))
  return (
    <div className="h-64 w-full" role="img" aria-label="Average weight by age in days">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: 0 }}>
          <CartesianGrid stroke="#e2e8f0" strokeDasharray="3 3" vertical={false} />
          <XAxis dataKey="age" type="number" domain={["dataMin", "dataMax"]} allowDecimals={false}
                 tick={{ fill: "#64748b", fontSize: 12 }} tickLine={false} axisLine={{ stroke: "#cbd5e1" }}
                 label={{ value: "Age (days)", position: "insideBottom", offset: -4, fill: "#64748b", fontSize: 12 }} />
          <YAxis tick={{ fill: "#64748b", fontSize: 12 }} tickLine={false} axisLine={false} width={64}
                 tickFormatter={(g: number) => (g >= 1000 ? `${(g / 1000).toFixed(1)} kg` : `${g} g`)} />
          <Tooltip cursor={{ stroke: "#94a3b8", strokeWidth: 1 }} content={<GrowthTooltip />} />
          <Line type="monotone" dataKey="avg" stroke={LINE} strokeWidth={2} isAnimationActive={false}
                dot={{ r: 4, fill: LINE, stroke: "#fff", strokeWidth: 2 }}
                activeDot={{ r: 6, fill: LINE, stroke: "#fff", strokeWidth: 2 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

function GrowthTooltip({ active, payload }: { active?: boolean; payload?: Array<{ payload: { row: FlockWeighIn } }> }) {
  if (!active || !payload?.length) return null
  const r = payload[0].payload.row
  return (
    <div className="rounded-md border border-slate-200 bg-white px-3 py-2 text-xs shadow-md">
      <div className="font-semibold text-slate-900">Day {r.ageInDays} · {fmtDate(r.weighDate)}</div>
      <div className="mt-1 text-slate-700">Average <b className="tabular-nums">{formatWeight(r.avgWeightG)}</b></div>
      {r.dailyGainG != null && <div className="text-slate-600">Gain {Number(r.dailyGainG).toFixed(1)} g/day</div>}
      <div className="text-slate-600">{r.sampleSize} birds{r.uniformityPct != null ? ` · uniformity ${Number(r.uniformityPct).toFixed(1)}%` : ""}</div>
    </div>
  )
}

// ---------------------------------------------------------------- the form

type Mode = "birds" | "summary"

function WeighInDialog({
  flocks, defaultFlockId, existing, maxDate, onClose, onSaved,
}: {
  flocks: Flock[]
  defaultFlockId: number
  existing: FlockWeighIn | null
  maxDate: string
  onClose: () => void
  onSaved: (flockId: number) => void | Promise<void>
}) {
  const { toast } = useToast()
  const [flockId, setFlockId] = useState(existing?.flockId ?? defaultFlockId)
  const [date, setDate] = useState(existing?.weighDate?.slice(0, 10) ?? maxDate)
  const [mode, setMode] = useState<Mode>(existing && !existing.weightsG?.length ? "summary" : "birds")
  const [unit, setUnit] = useState<WeightUnit>("g")
  const [weightsText, setWeightsText] = useState(existing?.weightsG?.join(" ") ?? "")
  const [sample, setSample] = useState(existing && !existing.weightsG?.length ? String(existing.sampleSize) : "")
  const [avg, setAvg] = useState(existing && !existing.weightsG?.length ? String(existing.avgWeightG) : "")
  const [uniformity, setUniformity] = useState(existing?.uniformityPct != null && !existing.weightsG?.length ? String(existing.uniformityPct) : "")
  const [cv, setCv] = useState(existing?.cvPct != null && !existing.weightsG?.length ? String(existing.cvPct) : "")
  const [minW, setMinW] = useState(existing?.minWeightG != null && !existing.weightsG?.length ? String(existing.minWeightG) : "")
  const [maxW, setMaxW] = useState(existing?.maxWeightG != null && !existing.weightsG?.length ? String(existing.maxWeightG) : "")
  const [notes, setNotes] = useState(existing?.notes ?? "")
  const [saving, setSaving] = useState(false)

  const parsed = useMemo(() => parseWeights(weightsText, unit), [weightsText, unit])
  const preview = useMemo(() => computeWeighInStats(parsed.weightsG), [parsed])
  const flock = flocks.find((f) => f.flockId === flockId)
  const minDate = flock?.startDate?.slice(0, 10)

  const num = (s: string) => (s.trim() === "" ? null : Number(s))
  const problem = (() => {
    if (!flockId) return "Choose the flock."
    if (!date) return "Choose the date."
    if (mode === "birds") {
      if (parsed.invalid.length) return `Not a weight: ${parsed.invalid.slice(0, 3).join(", ")}${parsed.invalid.length > 3 ? "…" : ""}`
      if (!parsed.weightsG.length) return "Enter each bird's weight."
    } else {
      if (!(Number(sample) >= 1)) return "Enter how many birds were weighed."
      if (!(Number(avg) > 0)) return "Enter the average weight in grams."
    }
    return null
  })()

  const save = async () => {
    if (problem) return
    setSaving(true)
    try {
      const input = mode === "birds"
        ? { flockId, weighDate: date, weightsG: parsed.weightsG, notes: notes || null }
        : {
            flockId, weighDate: date, sampleSize: Number(sample), avgWeightG: Number(avg),
            uniformityPct: num(uniformity), cvPct: num(cv), minWeightG: num(minW), maxWeightG: num(maxW),
            notes: notes || null,
          }
      if (existing) await updateWeighIn(existing.weighInId, input)
      else await createWeighIn(input)
      toast({ title: existing ? "Weigh-in updated" : "Weigh-in saved" })
      await onSaved(flockId)
    } catch (e) {
      toast({ title: "Not saved", description: e instanceof Error ? e.message : String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open onOpenChange={(v) => { if (!v && !saving) onClose() }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Scale} color="amber">{existing ? "Edit weigh-in" : "New weigh-in"}</FormDialogTitle>
          <DialogDescription>Weigh a sample of birds spread across the house, not just the ones nearest the door.</DialogDescription>
        </DialogHeader>

        <FormSection title="Flock & date" color="orange" tinted stackOnMobile>
          <div className="space-y-1.5">
            <Label>Flock</Label>
            <Select value={String(flockId)} onValueChange={(v) => setFlockId(Number(v))} disabled={saving}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {flocks.map((f) => (
                  <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}{isBroilerFlock(f) ? " · Broiler" : ""}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="wi-date">Date weighed</Label>
            <Input id="wi-date" type="date" value={date} min={minDate} max={maxDate} onChange={(e) => setDate(e.target.value)} disabled={saving} />
          </div>
        </FormSection>

        <FormSection
          title="Weights"
          color="amber"
          tinted
          columns={1}
          action={
            <div role="radiogroup" aria-label="How to enter weights" className="flex rounded-md bg-white/20 p-0.5 text-xs">
              {([["birds", "Bird by bird"], ["summary", "Summary only"]] as const).map(([m, label]) => (
                <button key={m} type="button" role="radio" aria-checked={mode === m} onClick={() => setMode(m)} disabled={saving}
                        className={cn("rounded px-2 py-1 font-medium", mode === m ? "bg-white text-amber-700" : "text-white")}>
                  {label}
                </button>
              ))}
            </div>
          }
        >
          {mode === "birds" ? (
            <div className="space-y-3">
              <div className="flex flex-wrap items-end justify-between gap-2">
                <Label htmlFor="wi-weights">One weight per bird</Label>
                <div role="radiogroup" aria-label="Unit" className="flex rounded-md border border-slate-200 bg-white p-0.5 text-xs">
                  {(["g", "kg"] as const).map((u) => (
                    <button key={u} type="button" role="radio" aria-checked={unit === u} onClick={() => setUnit(u)} disabled={saving}
                            className={cn("rounded px-2 py-1 font-medium", unit === u ? "bg-amber-500 text-white" : "text-slate-600")}>
                      {u === "g" ? "grams" : "kilograms"}
                    </button>
                  ))}
                </div>
              </div>
              <Textarea id="wi-weights" rows={5} value={weightsText} onChange={(e) => setWeightsText(e.target.value)} disabled={saving}
                        placeholder={unit === "g" ? "1850 1920 1780 2010 …" : "1.85 1.92 1.78 2.01 …"} className="font-mono" />
              <p className="text-xs text-slate-500">Separate birds with spaces, commas or new lines.{unit === "kg" ? " Use a point for decimals (1.85)." : ""}</p>
              {preview && (
                <div className="grid grid-cols-2 gap-2 rounded-md border border-amber-200 bg-white p-3 text-sm sm:grid-cols-4">
                  <Fig label="Birds" value={String(preview.sampleSize)} />
                  <Fig label="Average" value={formatWeight(preview.avgWeightG)} />
                  <Fig label="Uniformity" value={fmtPct(preview.uniformityPct)} />
                  <Fig label="CV" value={fmtPct(preview.cvPct, 2)} />
                </div>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
              <Field id="wi-n" label="Birds weighed *" value={sample} onChange={setSample} disabled={saving} step="1" />
              <Field id="wi-avg" label="Average (g) *" value={avg} onChange={setAvg} disabled={saving} />
              <Field id="wi-u" label="Uniformity (%)" value={uniformity} onChange={setUniformity} disabled={saving} />
              <Field id="wi-cv" label="CV (%)" value={cv} onChange={setCv} disabled={saving} />
              <Field id="wi-min" label="Lightest (g)" value={minW} onChange={setMinW} disabled={saving} />
              <Field id="wi-max" label="Heaviest (g)" value={maxW} onChange={setMaxW} disabled={saving} />
            </div>
          )}
        </FormSection>

        <FormSection title="Notes" color="slate" tinted columns={1}>
          <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} disabled={saving}
                    placeholder="Anything unusual: feed change, heat, a sick pen…" />
        </FormSection>

        {problem && (weightsText || sample || avg) && <p className="text-sm text-amber-700">{problem}</p>}

        <FormDialogFooter onCancel={onClose} cancelDisabled={saving}>
          <Button onClick={save} disabled={saving || !!problem} className={FORM_DIALOG_PRIMARY.amber}>
            {saving && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}
            {existing ? "Save changes" : "Save weigh-in"}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function Fig({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-slate-500">{label}</div>
      <div className="font-semibold tabular-nums text-slate-900">{value}</div>
    </div>
  )
}

function Field({ id, label, value, onChange, disabled, step = "any" }: {
  id: string; label: string; value: string; onChange: (v: string) => void; disabled?: boolean; step?: string
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{label}</Label>
      <Input id={id} type="number" inputMode="decimal" min="0" step={step} value={value}
             onChange={(e) => onChange(e.target.value)} disabled={disabled} />
    </div>
  )
}

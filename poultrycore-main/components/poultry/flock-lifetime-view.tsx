"use client"

// Flock lifetime performance + closeout history + Reopen (migrations 338/339).
//
// ONE component, two layouts, so the quick-look dialog and the full page can
// never show different figures:
//
// Both open with a headline summary card (profit, revenue, cost, birds,
// mortality, eggs), then the six figure sections as cards:
//
//   layout="dialog"  the house read-modal (max-w-2xl): everything stacked.
//   layout="page"    sections two-up, history and Reopen in a side column on
//                    wide screens.
//
// Every figure is fnflock_lifetimesummary's. Figures the data cannot support
// are shown as "—" with the reason, never as zero: a flock with no eggs has no
// feed-per-dozen, and a flock whose opening losses were never broken down has
// no lifetime mortality rate.

import { useEffect, useState, type ComponentType, type ReactNode } from "react"
import {
  AlertCircle, Bird, CalendarDays, Egg, HeartPulse, History, Loader2, Receipt, RotateCcw, Tag, TrendingUp, Wallet,
} from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { cn } from "@/lib/utils"
import { formatCurrency } from "@/lib/utils/currency"
import { getUserContext } from "@/lib/utils/user-context"
import {
  getFlockCloseoutHistory,
  getFlockLifetimeSummaries,
  reopenFlock,
  type FlockCloseoutRecord,
  type FlockLifetimeSummary,
} from "@/lib/api/flock-closeout"

export interface FlockLifetimeViewProps {
  flockId: number | null
  layout?: "dialog" | "page"
  /** Shows the Reopen action (poultry.flock-closeout.approve). */
  canReopen?: boolean
  onReopened?: () => void
  /** Lets a host show the flock's name in its own title. */
  onLoaded?: (summary: FlockLifetimeSummary | null) => void
  /** Bump to force a reload (the dialog does this each time it opens). */
  reloadKey?: number
}

const n = (v: number | null | undefined) => (v == null ? "—" : Number(v).toLocaleString())
const pct = (v: number | null | undefined) => (v == null ? "—" : `${(Number(v) * 100).toFixed(2)}%`)
const money = (v: number | null | undefined) => (v == null ? "—" : formatCurrency(Number(v)))

function Figure({ label, value, tone, hint }: { label: string; value: string; tone?: string; hint?: string }) {
  return (
    <div className="rounded-md border border-slate-100 bg-slate-50 px-3 py-2.5" title={hint}>
      <div className="text-xs leading-tight text-slate-500">{label}</div>
      <div className={cn("mt-0.5 text-lg font-semibold tabular-nums leading-snug text-slate-900", tone)}>{value}</div>
      {hint && <div className="mt-0.5 text-[11px] leading-tight text-slate-400">{hint}</div>}
    </div>
  )
}

type Icon = ComponentType<{ className?: string }>

/** A section as a white card with an icon header. */
function Panel({ title, icon: I, iconTone, note, children }: {
  title: ReactNode; icon?: Icon; iconTone?: string; note?: string; children: ReactNode
}) {
  return (
    <section className="flex flex-col rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
      <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-slate-800">
        {I && (
          <span className={cn("flex h-7 w-7 items-center justify-center rounded-lg", iconTone ?? "bg-slate-100 text-slate-600")}>
            <I className="h-4 w-4" />
          </span>
        )}
        {title}
      </h3>
      <div className="flex-1">{children}</div>
      {note && <p className="mt-3 text-xs leading-snug text-slate-500">{note}</p>}
    </section>
  )
}

/** A headline number in the summary card. */
function Headline({ label, value, tone, sub, big }: { label: string; value: string; tone?: string; sub?: string; big?: boolean }) {
  return (
    <div className="min-w-0 bg-white px-4 py-3">
      <div className="text-xs font-medium text-slate-500">{label}</div>
      <div className={cn("mt-1 truncate font-semibold tabular-nums text-slate-900", big ? "text-2xl" : "text-xl", tone)} title={value}>{value}</div>
      {sub && <div className="mt-0.5 truncate text-xs text-slate-400">{sub}</div>}
    </div>
  )
}

export function FlockLifetimeView({
  flockId, layout = "dialog", canReopen = false, onReopened, onLoaded, reloadKey = 0,
}: FlockLifetimeViewProps) {
  const page = layout === "page"
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [summary, setSummary] = useState<FlockLifetimeSummary | null>(null)
  const [history, setHistory] = useState<FlockCloseoutRecord[]>([])
  const [reopening, setReopening] = useState(false)
  const [reopenReason, setReopenReason] = useState("")
  const [reopenOpen, setReopenOpen] = useState(false)
  // 339: reversing the closeout's sales is the default -- a reopen almost always
  // means the close was wrong. Untick it only when the birds really were sold.
  const [reverseSales, setReverseSales] = useState(true)
  const [reopenMessage, setReopenMessage] = useState<{ ok: boolean; text: string; warnings?: string[] } | null>(null)

  const load = async () => {
    if (flockId == null) return
    const { farmId } = getUserContext()
    if (!farmId) return
    setLoading(true)
    setError("")
    const [s, h] = await Promise.all([
      getFlockLifetimeSummaries(farmId, { flockId }),
      getFlockCloseoutHistory(flockId, farmId),
    ])
    if (!s.success) setError(s.message || "Could not load this flock's performance.")
    else if (!s.data?.length) setError("This flock was not found on the current company.")
    const row = s.data?.[0] ?? null
    setSummary(row)
    setHistory(h.success && h.data ? h.data : [])
    setLoading(false)
    onLoaded?.(row)
  }

  useEffect(() => {
    if (flockId == null) return
    setReopenOpen(false)
    setReopenReason("")
    setReverseSales(true)
    setReopenMessage(null)
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [flockId, reloadKey])

  const doReopen = async () => {
    if (flockId == null) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    setReopening(true)
    const res = await reopenFlock(flockId, userId, farmId, reopenReason.trim(), reverseSales)
    setReopening(false)
    if (res.success && res.data?.success) {
      setReopenMessage({ ok: true, text: res.data.message, warnings: res.data.warnings })
      setReopenOpen(false)
      setReopenReason("")
      await load()
      onReopened?.()
    } else {
      setReopenMessage({ ok: false, text: res.data?.message || res.message || "The flock could not be reopened." })
    }
  }

  const s = summary
  const isClosed = s?.status === "Closed"

  if (loading && !s) {
    return (
      <div className="flex items-center justify-center gap-2 py-10 text-slate-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading…
      </div>
    )
  }

  const messages = (
    <>
      {error && (
        <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertDescription>{error}</AlertDescription></Alert>
      )}
      {reopenMessage && (
        <Alert className={reopenMessage.ok ? "border-emerald-200 bg-emerald-50" : "border-rose-200 bg-rose-50"}>
          <AlertDescription className={reopenMessage.ok ? "text-emerald-900" : "text-rose-900"}>
            {reopenMessage.text}
            {reopenMessage.warnings?.map((w) => <div key={w} className="mt-1 text-amber-800">{w}</div>)}
          </AlertDescription>
        </Alert>
      )}
    </>
  )

  if (!s) return <div className="space-y-3">{messages}</div>

  const mortalityRate = s.lifetimeMortalityRate ?? s.trackedMortalityRate

  // The flock's identity strip over its six headline numbers. The 1px grid gap
  // over a slate background draws the dividers at every column count.
  const summaryCard = (
    <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-slate-100 bg-slate-50/70 px-4 py-3 text-sm text-slate-600">
        <Badge variant="outline" className={isClosed ? "border-slate-400 bg-slate-100 text-slate-800" : "border-emerald-300 bg-emerald-50 text-emerald-800"}>
          {s.status}
        </Badge>
        <span className="inline-flex items-center gap-1.5">
          <CalendarDays className="h-4 w-4 text-slate-400" />
          {s.startDate.slice(0, 10)} → {s.closedDate ? s.closedDate.slice(0, 10) : "today"}
          <span className="text-slate-400">({n(s.daysInProduction)} days)</span>
        </span>
        {s.breed && <span className="inline-flex items-center gap-1.5"><Bird className="h-4 w-4 text-slate-400" />{s.breed}</span>}
        {s.batchCode && <span className="inline-flex items-center gap-1.5"><Tag className="h-4 w-4 text-slate-400" />Batch {s.batchCode}</span>}
        {s.houseName && <span>House: {s.houseName}</span>}
      </div>
      <div className={cn("grid gap-px bg-slate-100 grid-cols-2 sm:grid-cols-3", page && "lg:grid-cols-6")}>
        <Headline big={page} label="Profit" value={money(s.profit)} tone={s.profit >= 0 ? "text-emerald-700" : "text-rose-700"}
          sub={`${money(s.profitPerOriginalBird)} per bird placed`} />
        <Headline big={page} label="Total revenue" value={money(s.totalRevenue)} tone="text-emerald-700" />
        <Headline big={page} label="Total cost" value={money(s.totalCost)} tone="text-rose-700" />
        <Headline big={page} label={isClosed ? "Final birds" : "Current birds"} value={n(s.finalBirds)} sub={`of ${n(s.originallyPlaced)} placed`} />
        <Headline big={page} label="Mortality" value={pct(mortalityRate)}
          sub={s.lifetimeMortalityRate != null ? "Lifetime rate" : "Tracked rate"} />
        <Headline big={page} label="Total eggs" value={n(s.totalEggs)} sub={`${n(s.productionDays)} production days`} />
      </div>
    </section>
  )

  const four = page ? "grid grid-cols-2 gap-2.5" : "grid grid-cols-2 sm:grid-cols-4 gap-2.5"

  const sections = [
    <Panel key="birds" icon={Bird} iconTone="bg-sky-50 text-sky-600" title="Birds">
      <div className={four}>
        <Figure label="Originally placed" value={n(s.originallyPlaced)} />
        <Figure label={isClosed ? "Final birds" : "Current birds"} value={n(s.finalBirds)} />
        <Figure label="Sold" value={n(s.birdsSold)} tone="text-emerald-700" />
        <Figure label="Culled / transferred" value={`${n(s.birdsCulled)} / ${n(s.birdsTransferred)}`} />
      </div>
    </Panel>,
    <Panel key="mortality" icon={HeartPulse} iconTone="bg-rose-50 text-rose-600" title="Mortality">
      <div className={four}>
        <Figure label="Recorded here" value={n(s.recordedMortality)} tone="text-rose-700" />
        <Figure label="Tracked rate" value={pct(s.trackedMortalityRate)}
          hint={s.hasOpeningPosition ? "Of the opening position" : "Of birds placed"} />
        <Figure label="Before tracking"
          value={!s.hasOpeningPosition ? "—" : s.historyKnown ? n(s.openingMortality) : "—"}
          hint={!s.hasOpeningPosition ? "Tracked from placement" : s.historyKnown ? "Opening historical mortality" : "History not recorded"} />
        <Figure label="Lifetime rate" value={pct(s.lifetimeMortalityRate)}
          hint={s.lifetimeMortalityRate == null ? "Opening losses unknown" : undefined} />
      </div>
    </Panel>,
    <Panel key="production" icon={Egg} iconTone="bg-amber-50 text-amber-600" title="Production">
      <div className={four}>
        <Figure label="Total eggs" value={n(s.totalEggs)} />
        <Figure label="Production days" value={n(s.productionDays)} />
        <Figure label="Feed consumed" value={`${n(Math.round(Number(s.feedConsumedKg)))} kg`} />
        <Figure label="Feed per dozen" value={s.feedKgPerDozenEggs == null ? "—" : `${Number(s.feedKgPerDozenEggs).toFixed(3)} kg`}
          hint={s.feedKgPerDozenEggs == null ? "No eggs recorded" : undefined} />
      </div>
    </Panel>,
    <Panel key="revenue" icon={TrendingUp} iconTone="bg-emerald-50 text-emerald-600" title="Revenue"
      note="Sales recorded against this flock. Sales entered without a flock are not attributed to it.">
      <div className={four}>
        <Figure label="Eggs" value={money(s.eggRevenue)} />
        <Figure label="Bird sales" value={money(s.birdSaleRevenue)} />
        <Figure label="Other" value={money(s.otherRevenue)} />
        <Figure label="Total revenue" value={money(s.totalRevenue)} tone="text-emerald-700" />
      </div>
    </Panel>,
    <Panel key="cost" icon={Receipt} iconTone="bg-orange-50 text-orange-600" title="Attributable cost"
      note="Untagged payroll and overheads are not spread across flocks — there is no rule to split them by.">
      <div className={"grid grid-cols-2 sm:grid-cols-3 gap-2.5"}>
        <Figure label="Feed issued" value={money(s.feedCost)} />
        <Figure label="Medication" value={money(s.medicationCost)} />
        <Figure label="Bird cost" value={money(s.birdCost)} hint={s.birdCostRecorded ? "Share of batch cost" : "Batch has no cost"} />
        <Figure label="Labour (tagged)" value={money(s.laborCost)} />
        <Figure label="Other (tagged)" value={money(s.otherDirectCost)} />
        <Figure label="Total cost" value={money(s.totalCost)} tone="text-rose-700" />
      </div>
    </Panel>,
    <Panel key="result" icon={Wallet} iconTone="bg-violet-50 text-violet-600" title="Result">
      <div className={page ? "grid grid-cols-1 gap-2.5" : "grid grid-cols-1 sm:grid-cols-3 gap-2.5"}>
        <Figure label="Profit" value={money(s.profit)} tone={s.profit >= 0 ? "text-emerald-700" : "text-rose-700"} />
        <div className={page ? "grid grid-cols-2 gap-2.5" : "contents"}>
          <Figure label="Per original bird" value={money(s.profitPerOriginalBird)} />
          <Figure label="Revenue per bird" value={money(s.revenuePerOriginalBird)} />
        </div>
      </div>
    </Panel>,
  ]

  const historyBlock = history.length > 0 && (
    <Panel icon={History} title="Closeout history">
      <div className="space-y-2">
        {history.map((h) => (
          <div key={h.closeoutId} className={cn("rounded-md border p-3 text-sm", h.reopenedAt ? "border-slate-200 bg-white" : "border-blue-200 bg-blue-50/60")}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="font-medium">Closed {h.closedDate.slice(0, 10)} — {h.reason}</span>
              <Badge variant="outline">{h.reopenedAt ? "Reopened" : "Current"}</Badge>
            </div>
            <div className="mt-1 text-xs text-slate-600">
              {n(h.liveBirdsAtCloseout)} standing at close: {n(h.disposedSold)} sold, {n(h.disposedCulled)} culled,{" "}
              {n(h.disposedTransferred)} transferred. Closed by {h.closedBy}.
              {h.correction !== 0 && <> Count corrections of {h.correction > 0 ? "+" : ""}{n(h.correction)} were on record.</>}
            </div>
            {h.dispositions.filter((d) => d.disposition === "Sale").map((d) => (
              <div key={d.dispositionId} className="mt-1 text-xs text-slate-600">
                Sale #{d.saleId}: {n(d.quantity)} birds{d.totalAmount != null ? ` for ${money(d.totalAmount)}` : ""}
                {d.customerName ? ` to ${d.customerName}` : ""}
                {d.saleReversedAt
                  ? ` — reversed on reopen ${d.saleReversedAt.slice(0, 10)} (payments reversed, sale removed)`
                  : d.paid === false ? " (balance outstanding)" : ""}
              </div>
            ))}
            {h.dispositions.filter((d) => d.disposition === "Transfer").map((d) => (
              <div key={d.dispositionId} className="mt-1 text-xs text-slate-600">Transferred {n(d.quantity)} to {d.destination}</div>
            ))}
            {h.reopenedAt && (
              <div className="mt-1 text-xs text-slate-600">
                Reopened {h.reopenedAt.slice(0, 10)} by {h.reopenedBy}: {h.reopenReason}
              </div>
            )}
          </div>
        ))}
      </div>
    </Panel>
  )

  const reopenBlock = isClosed && canReopen && (
    <Panel icon={RotateCcw} iconTone="bg-amber-50 text-amber-600" title="Reopen this flock">
      <p className="mb-3 text-xs text-slate-500">Closed in error? Reopening makes the flock active again.</p>
      {!reopenOpen ? (
        <Button variant="outline" onClick={() => setReopenOpen(true)}>
          <RotateCcw className="h-4 w-4 mr-1" /> Reopen flock
        </Button>
      ) : (
        <div className="rounded-md border border-amber-200 bg-amber-50 p-3 space-y-2">
          <p className="text-sm text-amber-900">
            Reopening makes the flock active again and undoes its culls and transfers. This is recorded.
          </p>
          {(history.find((h) => !h.reopenedAt)?.dispositions ?? []).some((d) => d.disposition === "Sale") && (
            <label className="flex items-start gap-2 text-sm text-amber-900">
              <Checkbox checked={reverseSales} onCheckedChange={(v) => setReverseSales(v === true)} className="mt-0.5" />
              <span>
                <span className="font-medium">Also reverse the closeout sales.</span>{" "}
                {reverseSales
                  ? "Their payments are reversed (kept on record as Reversed), the money is taken back out of the cash account, the sales are removed and the birds return to the flock."
                  : "The sales stay — use this only if the birds really were sold. They can then be edited on the Sales page."}
              </span>
            </label>
          )}
          <Label className="text-xs">Reason for reopening</Label>
          <Textarea rows={2} value={reopenReason} onChange={(e) => setReopenReason(e.target.value)} />
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => setReopenOpen(false)} disabled={reopening}>Cancel</Button>
            <Button size="sm" onClick={doReopen} disabled={reopening || !reopenReason.trim()}>
              {reopening && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Reopen
            </Button>
          </div>
        </div>
      )}
    </Panel>
  )

  if (!page) {
    return (
      <div className="space-y-4">
        {messages}
        {summaryCard}
        {sections}
        {reopenBlock}
        {historyBlock}
      </div>
    )
  }

  // Full page: the sections two-up, with history + reopen beside them on wide
  // screens. On a phone or narrow window it simply stacks.
  return (
    <div className="space-y-6">
      {messages}
      {summaryCard}
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div className="grid content-start gap-4 md:grid-cols-2">{sections}</div>
        <aside className="space-y-4">
          {reopenBlock}
          {historyBlock || (
            <div className="rounded-xl border border-dashed border-slate-300 bg-white/60 p-5 text-sm text-slate-500">
              <History className="mb-2 h-5 w-5 text-slate-400" />
              {isClosed ? "No closeout history." : "This flock has not been closed yet. Use Close flock at the top of the page when its life is over."}
            </div>
          )}
        </aside>
      </div>
    </div>
  )
}

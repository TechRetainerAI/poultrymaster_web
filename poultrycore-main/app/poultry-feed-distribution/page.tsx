"use client"

// Distribute Feed (migration 335): one feed product to many flocks for one
// business date, in one post.
//
// Posting adds a feed line to each flock's production record for the day,
// through the same update an individual edit uses — so stock (FIFO / LIFO /
// HIFO), costing, the consumption expense and feed usage come out exactly as
// if each flock had been edited by hand. Flocks without exactly one production
// record for the date are shown but locked: record production first.
//
// Suggested Feed is only a suggestion. Actual is what posts, always typed by
// the farmer. Suggestions come from the farm's own rate (g/bird/day) or, only
// when chosen, each flock's recent average — never from a built-in figure.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { AlertTriangle, ChevronDown, ChevronUp, Loader2, Lock, RotateCcw, Wheat } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useBusinessDate } from "@/hooks/use-business-date"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { useFmt } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { listPoultryRawMaterialItems, type PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"
import { isFinishedFeedCategory } from "@/lib/utils/feed-item-ledger"
import {
  InsufficientFeedError,
  getFeedAvailability,
  getFeedDistributionCandidates,
  getFeedDistributionLines,
  listFeedDistributions,
  postFeedDistribution,
  reverseFeedDistribution,
  type FeedAvailability,
  type FeedDistribution,
  type FeedDistributionLine,
} from "@/lib/api/feed-distribution"
import {
  DEFAULT_RATE_UNIT,
  RATE_UNITS,
  distributionTotals,
  fromGramsPerBird,
  isRateUnit,
  manualFeedWarning,
  rateUnitLabel,
  toGramsPerBird,
  type RateUnit,
  parseKg,
  postBlocker,
  rowState,
  suggestionFor,
  type DistributionCandidate,
  type SuggestionBasis,
} from "@/lib/production/feed-distribution"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { toBusinessDate } from "@/lib/activity/completeness"
import { ReasonDialog } from "@/components/closing/daily-closing-dialogs"

const kg = (n: number | null | undefined) =>
  n == null ? "—" : `${Number(n).toLocaleString(undefined, { maximumFractionDigits: 3 })} kg`

function Stat({ label, value, tone }: { label: string; value: string; tone?: "bad" | "good" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("font-semibold tabular-nums", tone === "bad" ? "text-rose-700" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>
        {value}
      </div>
    </div>
  )
}

function FeedDistributionInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()
  const { fmtInstant } = useCompanyDateTime()
  const { businessDate: today } = useBusinessDate()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  // ?date= is the one source for the day (see Daily Closing for why).
  const picked = toBusinessDate(searchParams.get("date"))
  const date = picked && picked < today ? picked : today
  const setDate = (d: string) => {
    const v = toBusinessDate(d)
    router.replace(v && v < today ? `/poultry-feed-distribution?date=${v}` : "/poultry-feed-distribution", { scroll: false })
  }

  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [itemId, setItemId] = useState<number | null>(null)
  const [avail, setAvail] = useState<FeedAvailability | null>(null)
  const [cands, setCands] = useState<DistributionCandidate[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [basis, setBasis] = useState<SuggestionBasis>("Rate")
  // The rate as typed, in the unit the farm picked. Converted to grams per
  // bird per day for the suggestion and for storage.
  const [rateText, setRateText] = useState("")
  const [rateUnit, setRateUnit] = useState<RateUnit>(DEFAULT_RATE_UNIT)
  const [saveRate, setSaveRate] = useState(false)
  const [actual, setActual] = useState<Record<number, string>>({})
  const [notes, setNotes] = useState<Record<number, string>>({})
  const [docNotes, setDocNotes] = useState("")
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [posting, setPosting] = useState(false)
  // What was just posted, shown until the next distribution is started.
  const [lastPosted, setLastPosted] = useState<string | null>(null)
  const [tab, setTab] = useState("distribute")
  const [history, setHistory] = useState<FeedDistribution[] | null>(null)
  const [openDoc, setOpenDoc] = useState<number | null>(null)
  const [docLines, setDocLines] = useState<Record<number, FeedDistributionLine[]>>({})
  const [reverseDoc, setReverseDoc] = useState<FeedDistribution | null>(null)
  const [reversing, setReversing] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  // Feed products: finished feed, the same set the production forms offer.
  useEffect(() => {
    if (!activeFarmId) return
    listPoultryRawMaterialItems()
      .then((all) => setItems((Array.isArray(all) ? all : []).filter((i) => isFinishedFeedCategory(i.category) && i.isActive !== false)))
      .catch(() => setItems([]))
  }, [activeFarmId])

  const load = useCallback(async () => {
    if (!itemId) { setAvail(null); setCands(null); return }
    setLoading(true)
    setError(null)
    try {
      const [a, c] = await Promise.all([getFeedAvailability(itemId), getFeedDistributionCandidates(date, itemId)])
      setAvail(a)
      setCands(c)
      const unit = isRateUnit(a.rateUnit) ? a.rateUnit : DEFAULT_RATE_UNIT
      setRateUnit(unit)
      const shown = fromGramsPerBird(a.gramsPerBirdPerDay, unit)
      setRateText(shown != null ? String(shown) : "")
      setSaveRate(false)
      setActual({})
      setNotes({})
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load this feed.")
    } finally {
      setLoading(false)
    }
  }, [itemId, date])

  useEffect(() => { void load() }, [load])

  const loadHistory = useCallback(async () => {
    try { setHistory(await listFeedDistributions()) }
    catch (e) { toast({ title: "Could not load distributions", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
  }, [toast])
  useEffect(() => { if (tab === "history" && activeFarmId) void loadHistory() }, [tab, activeFarmId, loadHistory])

  const grams = toGramsPerBird(parseKg(rateText), rateUnit)
  // Switching unit keeps the same physical rate: 112.5 g/bird becomes 11.25 kg/100 birds.
  const changeRateUnit = (next: string) => {
    if (!isRateUnit(next)) return
    const converted = fromGramsPerBird(grams, next)
    setRateUnit(next)
    if (converted != null) setRateText(String(converted))
  }
  const rows = useMemo(() => (cands ?? []).map((c) => ({
    c,
    state: rowState(c),
    suggested: suggestionFor(c, basis, grams),
    actualText: actual[c.flockId] ?? "",
  })), [cands, basis, grams, actual])
  const totals = useMemo(() => distributionTotals(avail?.availableKg ?? 0, rows), [avail, rows])
  const blocker = postBlocker(totals, rows)
  // Nothing typed yet is a starting point, not an error: grey, not red.
  const nothingEntered = rows.every((r) => r.actualText.trim() === "")

  const fillFromSuggestions = () => {
    setLastPosted(null)
    const next: Record<number, string> = { ...actual }
    for (const r of rows) {
      if (r.state === "ok" && r.suggested != null) next[r.c.flockId] = String(r.suggested)
    }
    setActual(next)
  }

  const doPost = async () => {
    if (!itemId || !avail) return
    setPosting(true)
    try {
      const lines = rows
        .filter((r) => r.state === "ok" && (parseKg(r.actualText) ?? 0) > 0)
        .map((r) => ({
          flockId: r.c.flockId,
          actualKg: parseKg(r.actualText)!,
          suggestedKg: r.suggested,
          birds: r.c.birds,
          notes: notes[r.c.flockId]?.trim() || null,
        }))
      const anySuggestionUsed = lines.some((l) => l.suggestedKg != null)
      await postFeedDistribution({
        businessDate: date,
        itemId,
        basis: anySuggestionUsed ? basis : "Manual",
        gramsPerBirdPerDay: basis === "Rate" ? grams : null,
        rateUnit: basis === "Rate" && grams != null ? rateUnit : null,
        saveRate: basis === "Rate" && saveRate && grams != null,
        notes: docNotes.trim() || null,
        lines,
      })
      const summary = `${kg(totals.actual)} of ${avail.itemName} to ${lines.length} flock${lines.length === 1 ? "" : "s"}`
      toast({ title: "Feed distributed", description: `${summary}.` })
      setLastPosted(`Posted: ${summary}.`)
      setConfirmOpen(false)
      setDocNotes("")
      await load()
      if (history) void loadHistory()
    } catch (e) {
      toast({
        title: e instanceof InsufficientFeedError ? "Not enough feed" : "Not posted",
        description: e instanceof Error ? e.message : "",
        variant: "destructive",
      })
      if (e instanceof InsufficientFeedError) await load()
    } finally {
      setPosting(false)
    }
  }

  const toggleDoc = async (id: number) => {
    if (openDoc === id) { setOpenDoc(null); return }
    setOpenDoc(id)
    if (!docLines[id]) {
      try { setDocLines((p) => ({ ...p, [id]: [] })); const l = await getFeedDistributionLines(id); setDocLines((p) => ({ ...p, [id]: l })) }
      catch { /* shown as empty */ }
    }
  }

  const doReverse = async (reason: string) => {
    if (!reverseDoc) return
    setReversing(true)
    try {
      await reverseFeedDistribution(reverseDoc.poultryFeedDistributionId, reason)
      toast({ title: "Distribution reversed", description: "The feed went back into stock and off the flocks' records." })
      setReverseDoc(null)
      await loadHistory()
      void load()
    } catch (e) {
      toast({ title: "Not reversed", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  const eligibleCount = rows.filter((r) => r.state === "ok").length
  const recognition = avail?.costRecognitionMethod === "EXPENSE_WHEN_CONSUMED"
    ? "Expensed when consumed — posting records the feed cost as an expense."
    : "Expensed when purchased — posting moves stock only; the cost was expensed at purchase."

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-100">
                <Wheat className="h-5 w-5 text-amber-700" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Distribute Feed</h1>
                <p className="text-sm text-slate-600">
                  Give one feed to many flocks at once. Each flock gets the feed on its production record for the day,
                  exactly as if entered one by one.
                </p>
              </div>
            </div>

            <Tabs value={tab} onValueChange={setTab}>
              <TabsList>
                <TabsTrigger value="distribute">Distribute</TabsTrigger>
                <TabsTrigger value="history">Posted distributions</TabsTrigger>
              </TabsList>

              {/* ------------------------------------------------ distribute */}
              <TabsContent value="distribute" className="mt-4 space-y-4">
                <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                  <CardContent className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4">
                    <div className="space-y-1">
                      <Label htmlFor="fd-date" className="text-xs text-slate-500">Business date</Label>
                      <Input id="fd-date" type="date" value={date} max={today} onChange={(e) => { setLastPosted(null); setDate(e.target.value) }} />
                    </div>
                    <div className="space-y-1 lg:col-span-2">
                      <Label className="text-xs text-slate-500">Feed product</Label>
                      <Select value={itemId ? String(itemId) : ""} onValueChange={(v) => { setLastPosted(null); setItemId(Number(v) || null) }}>
                        <SelectTrigger><SelectValue placeholder={items.length ? "Choose feed" : "No finished feed items"} /></SelectTrigger>
                        <SelectContent>
                          {items.map((i) => (
                            <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>
                              {i.itemName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs text-slate-500">Source</Label>
                      <div className="flex h-9 items-center rounded-md border border-slate-200 bg-slate-50 px-3 text-sm text-slate-600">
                        {avail ? `${avail.lotCount} stock lot${avail.lotCount === 1 ? "" : "s"} · ${avail.usageMethod}` : "—"}
                      </div>
                    </div>
                  </CardContent>
                </Card>

                {error && <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>}
                {loading && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading flocks…</p>}
                {!itemId && <p className="text-sm text-slate-500">Choose a feed product to see the flocks for {formatLongDate(date)}.</p>}

                {avail && cands && !loading && (
                  <>
                    {/* -------------------------------- suggestion + totals */}
                    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                      <CardContent className="space-y-3 p-4">
                        <div className="flex flex-wrap items-end gap-3">
                          <div className="space-y-1">
                            <Label className="text-xs text-slate-500">Suggest by</Label>
                            <div className="inline-flex rounded-md border border-slate-200 bg-slate-50 p-0.5 text-sm">
                              {(["Rate", "RecentAverage"] as const).map((b) => (
                                <button key={b} type="button" onClick={() => setBasis(b)}
                                  className={cn("rounded px-3 py-1", basis === b ? "bg-white font-medium text-slate-900 shadow-sm" : "text-slate-600")}>
                                  {b === "Rate" ? "Feed rate" : "Recent average (7 days)"}
                                </button>
                              ))}
                            </div>
                          </div>
                          {basis === "Rate" && (
                            <>
                              <div className="space-y-1">
                                <Label htmlFor="fd-rate" className="text-xs text-slate-500">Feed rate</Label>
                                <Input id="fd-rate" type="number" min={0} step="any" className="w-32" value={rateText}
                                  onChange={(e) => setRateText(e.target.value)} />
                              </div>
                              <div className="space-y-1">
                                <Label className="text-xs text-slate-500">Unit</Label>
                                <Select value={rateUnit} onValueChange={changeRateUnit}>
                                  <SelectTrigger className="w-56"><SelectValue /></SelectTrigger>
                                  <SelectContent>
                                    {RATE_UNITS.map((u) => <SelectItem key={u.key} value={u.key}>{u.label}</SelectItem>)}
                                  </SelectContent>
                                </Select>
                              </div>
                              <label className="flex items-center gap-2 pb-2 text-sm text-slate-700">
                                <Checkbox checked={saveRate} disabled={grams == null} onCheckedChange={(v) => setSaveRate(v === true)} />
                                Save as this feed&apos;s rate
                              </label>
                            </>
                          )}
                          <Button variant="outline" size="sm" className="mb-0.5" onClick={fillFromSuggestions}
                            disabled={!rows.some((r) => r.state === "ok" && r.suggested != null)}>
                            Fill Actual from suggestions
                          </Button>
                        </div>
                        {basis === "Rate" && grams == null && (
                          <p className="text-xs text-slate-500">
                            No feed rate is set for {avail.itemName}. Type the farm&apos;s own rate, in whichever unit you use, to get suggestions — none is assumed.
                          </p>
                        )}
                        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                          <Stat label="Available inventory" value={kg(totals.available)} />
                          <Stat label="Suggested total" value={kg(totals.suggested)} />
                          <Stat label="Actual distribution" value={kg(totals.actual)} />
                          <Stat label="Remaining inventory" value={kg(totals.remaining)} tone={totals.remaining < 0 ? "bad" : undefined} />
                        </div>
                        <p className="text-xs text-slate-500">{recognition}</p>
                      </CardContent>
                    </Card>

                    {/* ----------------------------------------- flock grid */}
                    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                      <CardContent className="p-0">
                        <div className="overflow-x-auto">
                          <table className="w-full min-w-[46rem] text-sm">
                            <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                              <tr>
                                <th className="px-3 py-2 font-medium">Flock</th>
                                <th className="px-3 py-2 font-medium">House/Pen</th>
                                <th className="px-3 py-2 text-right font-medium">Current Birds</th>
                                <th className="px-3 py-2 text-right font-medium">Suggested Feed</th>
                                <th className="px-3 py-2 font-medium">Actual Feed (kg)</th>
                                <th className="px-3 py-2 font-medium">Notes</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                              {rows.length === 0 && (
                                <tr><td colSpan={6} className="px-3 py-4 text-slate-500">No active flocks are expected to report on this date.</td></tr>
                              )}
                              {rows.map((r) => {
                                const locked = r.state !== "ok"
                                const warn = manualFeedWarning(r.c, parseKg(r.actualText))
                                const invalid = r.actualText.trim() !== "" && parseKg(r.actualText) == null
                                return (
                                  <tr key={r.c.flockId} className={cn(locked && "bg-slate-50 text-slate-500")}>
                                    <td className="px-3 py-2">
                                      <div className="font-medium text-slate-900">{r.c.flockName}</div>
                                      {r.c.thisItemKg > 0 && <div className="text-xs text-slate-500">Already {kg(r.c.thisItemKg)} of this feed today</div>}
                                      {warn && <div className="flex items-start gap-1 text-xs text-amber-700"><AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" />{warn}</div>}
                                    </td>
                                    <td className="px-3 py-2">{r.c.houseName ?? "—"}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{r.c.birds?.toLocaleString() ?? "—"}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">
                                      {locked ? "—" : kg(r.suggested)}
                                      {!locked && basis === "RecentAverage" && r.c.recentAvgDays != null && r.c.recentAvgDays > 0 && (
                                        <div className="text-[11px] text-slate-400">avg of {r.c.recentAvgDays} day{r.c.recentAvgDays === 1 ? "" : "s"}</div>
                                      )}
                                    </td>
                                    <td className="px-3 py-2">
                                      {locked ? (
                                        <span className="inline-flex items-center gap-1 text-xs">
                                          <Lock className="h-3.5 w-3.5" />
                                          {r.state === "noRecord" ? (
                                            <>No production record — <Link className="text-sky-700 underline"
                                              href={`/production-records/new?flockId=${r.c.flockId}&date=${date}`}>record it first</Link></>
                                          ) : (
                                            <>{r.c.recordCount} records for this day — <Link className="text-sky-700 underline"
                                              href={`/production-records?date=${date}`}>fix the duplicate</Link></>
                                          )}
                                        </span>
                                      ) : (
                                        <Input type="number" min={0} step="0.1" inputMode="decimal"
                                          className={cn("h-9 w-32 tabular-nums", invalid && "border-rose-400")}
                                          value={r.actualText}
                                          onChange={(e) => { setLastPosted(null); setActual((p) => ({ ...p, [r.c.flockId]: e.target.value })) }} />
                                      )}
                                    </td>
                                    <td className="px-3 py-2">
                                      {!locked && (
                                        <Input className="h-9 min-w-[10rem]" value={notes[r.c.flockId] ?? ""}
                                          onChange={(e) => setNotes((p) => ({ ...p, [r.c.flockId]: e.target.value }))} />
                                      )}
                                    </td>
                                  </tr>
                                )
                              })}
                            </tbody>
                          </table>
                        </div>
                      </CardContent>
                    </Card>

                    <div className="sticky bottom-0 z-20 -mx-4 border-t border-slate-200 bg-white/95 px-4 py-3 pb-16 backdrop-blur sm:-mx-6 sm:px-6 lg:pb-3">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        {lastPosted && nothingEntered ? (
                          <p className="text-sm text-emerald-700">
                            {lastPosted}{" "}
                            <button type="button" className="underline" onClick={() => setTab("history")}>View in Posted distributions</button>
                          </p>
                        ) : nothingEntered ? (
                          <p className="text-sm text-slate-500">Type the feed amounts for the flocks you&apos;re feeding.</p>
                        ) : (
                          <p className={cn("text-sm", blocker ? "text-rose-700" : "text-slate-600")}>
                            {blocker ?? `${kg(totals.actual)} to ${rows.filter((r) => r.state === "ok" && (parseKg(r.actualText) ?? 0) > 0).length} of ${eligibleCount} flocks · ${kg(totals.remaining)} left`}
                          </p>
                        )}
                        <Button className="bg-emerald-600 text-white hover:bg-emerald-700" disabled={!!blocker || posting}
                          onClick={() => setConfirmOpen(true)}>
                          Post Feed Distribution
                        </Button>
                      </div>
                    </div>
                  </>
                )}
              </TabsContent>

              {/* --------------------------------------------------- history */}
              <TabsContent value="history" className="mt-4">
                <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                  <CardContent className="p-0">
                    {!history ? (
                      <p className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
                    ) : history.length === 0 ? (
                      <p className="p-4 text-sm text-slate-500">No feed has been distributed yet.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[46rem] text-sm">
                          <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                            <tr>
                              <th className="px-3 py-2 font-medium">Date</th>
                              <th className="px-3 py-2 font-medium">Feed</th>
                              <th className="px-3 py-2 text-right font-medium">Flocks</th>
                              <th className="px-3 py-2 text-right font-medium">Total</th>
                              <th className="px-3 py-2 text-right font-medium">Cost</th>
                              <th className="px-3 py-2 font-medium">Status</th>
                              <th className="px-3 py-2 text-right font-medium">Action</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-100">
                            {history.map((h) => {
                              const isOpen = openDoc === h.poultryFeedDistributionId
                              return (
                                <FragmentRow key={h.poultryFeedDistributionId}>
                                  <tr className="cursor-pointer hover:bg-slate-50" onClick={() => void toggleDoc(h.poultryFeedDistributionId)}>
                                    <td className="px-3 py-2 font-medium text-slate-900">
                                      <span className="mr-1.5 inline-flex align-middle text-slate-500">
                                        {isOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                                      </span>
                                      {formatLongDate(h.businessDate)}
                                    </td>
                                    <td className="px-3 py-2">{h.itemName ?? "—"}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{h.flockCount}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{kg(h.totalActualKg)}</td>
                                    <td className="px-3 py-2 text-right tabular-nums">{h.totalCost != null ? fmt(h.totalCost) : "—"}</td>
                                    <td className="px-3 py-2">
                                      <span className={cn("rounded-full px-2 py-0.5 text-xs",
                                        h.status === "Posted" ? "bg-emerald-100 text-emerald-700" : "bg-slate-200 text-slate-600")}>
                                        {h.status}
                                      </span>
                                    </td>
                                    <td className="px-3 py-2 text-right">
                                      {h.status === "Posted" && (
                                        <Button size="sm" variant="outline" className="h-7 gap-1 px-2.5 text-xs"
                                          onClick={(e) => { e.stopPropagation(); setReverseDoc(h) }}>
                                          <RotateCcw className="h-3.5 w-3.5" /> Reverse
                                        </Button>
                                      )}
                                    </td>
                                  </tr>
                                  {isOpen && (
                                    <tr className="bg-slate-50/80">
                                      <td colSpan={7} className="px-3 py-3 pl-9 text-xs text-slate-600">
                                        <p>
                                          Posted by {h.postedBy ?? "unknown"} · {fmtInstant(h.postedAtUtc)}
                                          {h.basis !== "Manual" && ` · suggested by ${h.basis === "Rate"
                                            ? `rate ${fromGramsPerBird(h.gramsPerBirdPerDay, h.rateUnit ?? DEFAULT_RATE_UNIT) ?? "?"} ${rateUnitLabel(h.rateUnit ?? DEFAULT_RATE_UNIT)}`
                                            : "recent average"}`}
                                          {h.notes ? ` · “${h.notes}”` : ""}
                                        </p>
                                        {h.status === "Reversed" && (
                                          <p className="text-rose-700">Reversed by {h.reversedBy ?? "unknown"} · {fmtInstant(h.reversedAtUtc)} — {h.reversalReason}</p>
                                        )}
                                        <table className="mt-2 w-full">
                                          <tbody>
                                            {(docLines[h.poultryFeedDistributionId] ?? []).map((l) => (
                                              <tr key={l.poultryFeedDistributionLineId}>
                                                <td className="py-0.5 pr-3 text-slate-800">{l.flockName}</td>
                                                <td className="py-0.5 pr-3 tabular-nums">{kg(l.actualKg)}{l.suggestedKg != null && ` (suggested ${kg(l.suggestedKg)})`}</td>
                                                <td className="py-0.5 pr-3 tabular-nums">{l.totalCost != null ? fmt(l.totalCost) : ""}</td>
                                                <td className="py-0.5">{l.notes ?? ""}{l.reversalNote ? ` · ${l.reversalNote}` : ""}</td>
                                              </tr>
                                            ))}
                                          </tbody>
                                        </table>
                                      </td>
                                    </tr>
                                  )}
                                </FragmentRow>
                              )
                            })}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Post feed distribution?</DialogTitle>
            <DialogDescription>
              {kg(totals.actual)} of {avail?.itemName} on {formatLongDate(date)}, to{" "}
              {rows.filter((r) => r.state === "ok" && (parseKg(r.actualText) ?? 0) > 0).length} flocks. Stock is checked
              again when you post. Each flock&apos;s production record gets the feed as a stock line.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1">
            <Label htmlFor="fd-notes" className="text-xs text-slate-500">Notes (optional)</Label>
            <Input id="fd-notes" value={docNotes} onChange={(e) => setDocNotes(e.target.value)} placeholder="e.g. Morning feeding" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmOpen(false)} disabled={posting}>Cancel</Button>
            <Button onClick={() => void doPost()} disabled={posting} className="bg-emerald-600 text-white hover:bg-emerald-700">
              {posting && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Post
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ReasonDialog
        open={!!reverseDoc} onOpenChange={(v) => { if (!v) setReverseDoc(null) }} busy={reversing} destructive
        title="Reverse this feed distribution?"
        description="The feed comes off each flock's production record and goes back into stock. The distribution stays in the history, marked Reversed."
        confirmLabel="Reverse" onConfirm={(r) => void doReverse(r)} />
    </div>
  )
}

/** Two table rows under one key. */
function FragmentRow({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}

export default function FeedDistributionPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <FeedDistributionInner />
    </Suspense>
  )
}

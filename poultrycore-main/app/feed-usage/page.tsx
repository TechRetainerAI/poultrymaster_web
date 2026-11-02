"use client"

// Feed Usage (migration 389). Feed comes out of inventory: an entry picks the
// feed from stock and adds it as feed lines to each flock's production record
// for the day -- the one place feed leaves stock. Before 389 this page saved a
// label and a kg figure that never touched stock, and its production-record
// "sync" made the same feed count twice.
//
// Feed log: every feed line on the farm's production records, whichever screen
// entered it (this page, the production form, Distribute Feed, batch
// production). Entries: what was recorded here, with reversal.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { ChevronDown, ChevronUp, Loader2, Plus, RotateCcw, Wheat } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { DataPagination } from "@/components/ui/data-pagination"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { usePagination } from "@/hooks/use-pagination"
import { useBusinessDate } from "@/hooks/use-business-date"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { useFmt } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { STOCK_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonDialog } from "@/components/closing/daily-closing-dialogs"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { shiftBusinessDate } from "@/lib/activity/completeness"
import { RecordFeedUsageDialog } from "@/components/feed-usage/record-feed-usage-dialog"
import {
  getFeedUsageEntryLines, getFeedUsageLog, listFeedUsageEntries, reverseFeedUsage,
  type FeedUsageEntry, type FeedUsageEntryLine, type FeedUsageLogRow,
} from "@/lib/api/feed-usage-entries"

const kg = (n: number) => `${(Math.round(n * 1000) / 1000).toLocaleString()} kg`

/** Which screen put a feed line on its record. */
function sourceLabel(r: FeedUsageLogRow): string {
  if (r.recordSource === "Legacy") return "Old entry (not from stock)"
  if (r.entryId) return "Feed Usage"
  if (r.distributionId) return "Distribute Feed"
  if (r.recordSource === "BatchAllocation") return "Batch production"
  return "Production record"
}

function FeedUsageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()
  const permissions = usePermissions()
  const { fmtInstant } = useCompanyDateTime()
  const { businessDate: today } = useBusinessDate()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [tab, setTab] = useState("log")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [flockFilter, setFlockFilter] = useState("ALL")
  const [search, setSearch] = useState("")
  const [log, setLog] = useState<FeedUsageLogRow[] | null>(null)
  const [entries, setEntries] = useState<FeedUsageEntry[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [recordOpen, setRecordOpen] = useState(false)
  const [openEntry, setOpenEntry] = useState<number | null>(null)
  const [entryLines, setEntryLines] = useState<Record<number, FeedUsageEntryLine[]>>({})
  const [reverseEntry, setReverseEntry] = useState<FeedUsageEntry | null>(null)
  const [reversing, setReversing] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  // Last 30 days by default, once the company's date is known.
  useEffect(() => {
    if (today && !to) { setTo(today); setFrom(shiftBusinessDate(today, -29) ?? today) }
  }, [today, to])

  // /feed-usage?record=1 (the old "new" page and quick links) opens the form.
  useEffect(() => {
    if (searchParams.get("record") === "1" && today) {
      setRecordOpen(true)
      router.replace("/feed-usage", { scroll: false })
    }
  }, [searchParams, today, router])

  const load = useCallback(async () => {
    if (!from || !to) return
    setLoading(true); setError(null)
    try {
      const [l, e] = await Promise.all([getFeedUsageLog(from, to), listFeedUsageEntries(from, to)])
      setLog(l); setEntries(e); setEntryLines({})
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load feed usage.")
    } finally {
      setLoading(false)
    }
  }, [from, to])

  useEffect(() => { if (activeFarmId) void load() }, [activeFarmId, load])

  const flocks = useMemo(() => {
    const m = new Map<number, string>()
    for (const r of log ?? []) m.set(r.flockId, r.flockName ?? `Flock ${r.flockId}`)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [log])

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    return (log ?? []).filter((r) =>
      (flockFilter === "ALL" || String(r.flockId) === flockFilter)
      && (!q || `${r.flockName ?? ""} ${r.itemName ?? ""} ${sourceLabel(r)}`.toLowerCase().includes(q)))
  }, [log, flockFilter, search])
  const totals = useMemo(() => ({
    kg: shown.reduce((a, r) => a + r.quantityKg, 0),
    cost: shown.reduce((a, r) => a + (r.totalCost ?? 0), 0),
    feedOnly: new Set(shown.filter((r) => r.feedOnly).map((r) => r.productionRecordId)).size,
  }), [shown])
  const pg = usePagination(shown, 20)
  const pgE = usePagination(entries ?? [], 10)

  const toggleEntry = async (id: number) => {
    if (openEntry === id) { setOpenEntry(null); return }
    setOpenEntry(id)
    if (!entryLines[id]) {
      try {
        const lines = await getFeedUsageEntryLines(id)
        setEntryLines((m) => ({ ...m, [id]: lines }))
      } catch (e) {
        toast({ title: "Could not load the entry", description: e instanceof Error ? e.message : "", variant: "destructive" })
      }
    }
  }

  const doReverse = async (reason: string) => {
    if (!reverseEntry) return
    setReversing(true)
    try {
      await reverseFeedUsage(reverseEntry.poultryFeedUsageEntryId, reason)
      toast({ title: "Feed usage reversed", description: "The feed is back in stock." })
      setReverseEntry(null)
      await load()
    } catch (e) {
      toast({ title: "Not reversed", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-4">
          <div className="space-y-4">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-100">
                  <Wheat className="h-5 w-5 text-amber-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-2xl font-bold text-slate-900">Feed Usage</h1>
                  <p className="text-sm text-slate-600">Feed taken from stock for each flock. It also shows on the flock&apos;s production record.</p>
                </div>
              </div>
              {permissions.canCreate && (
                <Button className="gap-1.5 bg-emerald-600 text-white hover:bg-emerald-700" onClick={() => setRecordOpen(true)} disabled={!today}>
                  <Plus className="h-4 w-4" /> Record feed usage
                </Button>
              )}
            </div>

            <div className="flex flex-wrap items-end gap-3">
              <div className="space-y-1">
                <Label htmlFor="fu-from" className="text-xs text-slate-500">From</Label>
                <Input id="fu-from" type="date" className="w-40" value={from} max={to || undefined} onChange={(e) => setFrom(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="fu-to" className="text-xs text-slate-500">To</Label>
                <Input id="fu-to" type="date" className="w-40" value={to} min={from || undefined} max={today || undefined} onChange={(e) => setTo(e.target.value)} />
              </div>
              {tab === "log" && (
                <>
                  <div className="space-y-1">
                    <Label className="text-xs text-slate-500">Flock</Label>
                    <Select value={flockFilter} onValueChange={setFlockFilter}>
                      <SelectTrigger className="w-44" aria-label="Flock filter"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="ALL">All flocks</SelectItem>
                        {flocks.map(([id, name]) => <SelectItem key={id} value={String(id)}>{name}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1">
                    <Label htmlFor="fu-search" className="text-xs text-slate-500">Search</Label>
                    <Input id="fu-search" className="w-48" placeholder="Flock or feed" value={search} onChange={(e) => setSearch(e.target.value)} />
                  </div>
                </>
              )}
              {loading && <Loader2 className="mb-2.5 h-4 w-4 animate-spin text-slate-400" />}
            </div>

            {error && <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>}

            <Tabs value={tab} onValueChange={setTab}>
              <TabsList>
                <TabsTrigger value="log">Feed log</TabsTrigger>
                <TabsTrigger value="entries">Entries</TabsTrigger>
              </TabsList>

              <TabsContent value="log" className="mt-4 space-y-3">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <Stat label="Feed used" value={kg(totals.kg)} />
                  <Stat label="Feed cost" value={fmt(totals.cost)} />
                  <Stat label="Feed only, production not filled" value={String(totals.feedOnly)} tone={totals.feedOnly > 0 ? "warn" : undefined} />
                </div>
                <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                  <CardContent className="p-0">
                    {!log ? (
                      <p className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
                    ) : shown.length === 0 ? (
                      <p className="p-4 text-sm text-slate-500">No feed used in this period.</p>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full min-w-[52rem] text-sm">
                          <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                            <tr>
                              <th className="px-3 py-2 font-medium">Date</th>
                              <th className="px-3 py-2 font-medium">Flock</th>
                              <th className="px-3 py-2 font-medium">Feed</th>
                              <th className="px-3 py-2 text-right font-medium">Quantity</th>
                              <th className="px-3 py-2 text-right font-medium">Cost</th>
                              <th className="px-3 py-2 font-medium">Entered from</th>
                              <th className="px-3 py-2 font-medium">Production record</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-100">
                            {pg.pageItems.map((r, i) => (
                              <tr key={`${r.productionRecordId ?? "l" + r.legacyFeedUsageId}-${r.itemId ?? "x"}-${i}`} className="hover:bg-slate-50">
                                <td className="whitespace-nowrap px-3 py-2">{formatLongDate(r.usageDate.slice(0, 10))}</td>
                                <td className="px-3 py-2 font-medium text-slate-900">{r.flockName ?? `Flock ${r.flockId}`}</td>
                                <td className="px-3 py-2">{r.itemName ?? "—"}</td>
                                <td className="px-3 py-2 text-right tabular-nums">{kg(r.quantityKg)}</td>
                                <td className="px-3 py-2 text-right tabular-nums">{r.totalCost != null ? fmt(r.totalCost) : "—"}</td>
                                <td className={cn("px-3 py-2", r.recordSource === "Legacy" && "text-slate-400")}>{sourceLabel(r)}</td>
                                <td className="px-3 py-2">
                                  {r.productionRecordId ? (
                                    <div className="flex flex-wrap items-center gap-2">
                                      {r.feedOnly && <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-medium text-amber-800">Production not filled</span>}
                                      <Link href={`/production-records/${r.productionRecordId}`} className="text-sm font-medium text-sky-700 hover:underline">
                                        {r.feedOnly ? "Fill in production" : "Open"}
                                      </Link>
                                    </div>
                                  ) : "—"}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </CardContent>
                </Card>
                {shown.length > 0 && <DataPagination {...pg.paginationProps} />}
                <p className="text-xs text-slate-500">
                  To change feed on a day, open its production record, or reverse the Feed Usage entry. Old entries typed in before feed came from stock are shown for reference only.
                </p>
              </TabsContent>

              <TabsContent value="entries" className="mt-4 space-y-3">
                <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                  <CardContent className="p-0">
                    {!entries ? (
                      <p className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
                    ) : entries.length === 0 ? (
                      <p className="p-4 text-sm text-slate-500">Nothing recorded from this page in this period.</p>
                    ) : (
                      <ul className="divide-y divide-slate-100">
                        {pgE.pageItems.map((e) => {
                          const isOpen = openEntry === e.poultryFeedUsageEntryId
                          return (
                            <li key={e.poultryFeedUsageEntryId} className="p-3">
                              <div className="flex flex-wrap items-center justify-between gap-2">
                                <button type="button" className="flex min-w-0 items-start gap-2 text-left" onClick={() => void toggleEntry(e.poultryFeedUsageEntryId)}>
                                  {isOpen ? <ChevronUp className="mt-0.5 h-4 w-4 text-slate-400" /> : <ChevronDown className="mt-0.5 h-4 w-4 text-slate-400" />}
                                  <div className="min-w-0">
                                    <p className="font-medium text-slate-900">
                                      {formatLongDate(e.businessDate.slice(0, 10))} · {e.scope === "Batch" ? `${e.batchName ?? "Batch"} (${e.flockCount} flocks)` : "1 flock"} · {kg(e.totalKg)}
                                      {e.totalCost != null && <> · {fmt(e.totalCost)}</>}
                                    </p>
                                    <p className="text-xs text-slate-500">
                                      #{e.poultryFeedUsageEntryId} · by {e.postedBy ?? "unknown"} · {fmtInstant(e.postedAtUtc)}
                                      {e.notes ? ` · “${e.notes}”` : ""}
                                      {e.feedOnlyRecords > 0 ? ` · made ${e.feedOnlyRecords} feed-only record${e.feedOnlyRecords === 1 ? "" : "s"}` : ""}
                                    </p>
                                    {e.status === "Reversed" && (
                                      <p className="text-xs text-rose-700">Reversed by {e.reversedBy ?? "unknown"} ({fmtInstant(e.reversedAtUtc)}): {e.reversalReason}</p>
                                    )}
                                  </div>
                                </button>
                                <div className="flex items-center gap-2">
                                  <span className={cn("rounded-full px-2 py-0.5 text-xs",
                                    e.status === "Posted" ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600")}>{e.status}</span>
                                  {e.status === "Posted" && permissions.canDelete && (
                                    <Button size="sm" variant="outline" className="gap-1.5 text-rose-700" onClick={() => setReverseEntry(e)}>
                                      <RotateCcw className="h-3.5 w-3.5" /> Reverse
                                    </Button>
                                  )}
                                </div>
                              </div>
                              {isOpen && (
                                <div className="mt-2 overflow-x-auto pl-6">
                                  {!entryLines[e.poultryFeedUsageEntryId] ? (
                                    <p className="text-xs text-slate-500">Loading…</p>
                                  ) : (
                                    <table className="w-full min-w-[36rem] text-sm">
                                      <thead className="text-left text-xs uppercase tracking-wider text-slate-500">
                                        <tr>
                                          <th className="py-1 pr-3 font-medium">Flock</th>
                                          <th className="py-1 pr-3 font-medium">Feed</th>
                                          <th className="py-1 pr-3 text-right font-medium">Quantity</th>
                                          <th className="py-1 pr-3 text-right font-medium">Cost</th>
                                          <th className="py-1 font-medium">Record</th>
                                        </tr>
                                      </thead>
                                      <tbody>
                                        {entryLines[e.poultryFeedUsageEntryId].map((l) => (
                                          <tr key={l.poultryFeedUsageLineId} className="border-t border-slate-100">
                                            <td className="py-1 pr-3">{l.flockName}</td>
                                            <td className="py-1 pr-3">{l.itemName}</td>
                                            <td className="py-1 pr-3 text-right tabular-nums">{kg(l.quantityKg)}</td>
                                            <td className="py-1 pr-3 text-right tabular-nums">{l.totalCost != null ? fmt(l.totalCost) : "—"}</td>
                                            <td className="py-1 text-xs text-slate-500">
                                              <Link href={`/production-records/${l.productionRecordId}`} className="font-medium text-sky-700 hover:underline">#{l.productionRecordId}</Link>
                                              {l.createdRecord && " · made feed-only"}
                                              {l.reversalNote && ` · ${l.reversalNote}`}
                                            </td>
                                          </tr>
                                        ))}
                                      </tbody>
                                    </table>
                                  )}
                                </div>
                              )}
                            </li>
                          )
                        })}
                      </ul>
                    )}
                  </CardContent>
                </Card>
                {(entries?.length ?? 0) > 0 && <DataPagination {...pgE.paginationProps} />}
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {today && (
        <RecordFeedUsageDialog open={recordOpen} onOpenChange={setRecordOpen} today={today} onSaved={() => void load()} />
      )}

      <ReasonDialog
        open={!!reverseEntry} onOpenChange={(v) => { if (!v) setReverseEntry(null) }} busy={reversing} destructive
        title="Reverse this feed usage?"
        options={STOCK_REVERSAL_REASONS}
        description="The feed comes off each flock's production record and goes back into stock. A feed-only record left empty is removed. The entry stays in the history, marked Reversed."
        confirmLabel="Reverse" onConfirm={(r) => void doReverse(r)} />
    </div>
  )
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "warn" }) {
  return (
    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
      <CardContent className="p-4">
        <p className="text-xs font-medium uppercase tracking-wider text-slate-500">{label}</p>
        <p className={cn("mt-1 text-xl font-bold", tone === "warn" ? "text-amber-700" : "text-slate-900")}>{value}</p>
      </CardContent>
    </Card>
  )
}

export default function FeedUsagePage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <FeedUsageInner />
    </Suspense>
  )
}

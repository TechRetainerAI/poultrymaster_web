"use client"

// Daily Closing -- the poultry Daily Closing for livestock. Check the day
// (each group's animals, deaths, produce and feed; sales; money per account),
// deal with what is missing, and close it. A closed day cannot be changed
// until it is reopened, with a reason.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { AlertTriangle, CalendarCheck, CheckCircle2, Lock, Unlock } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { closeDay, getDaySummary, listDays, reopenDay, type DayListItem, type DaySummary } from "@/lib/api/livestock"
import { AMBER_BUTTON, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"
import { cn } from "@/lib/utils"

const yesterday = () => { const d = new Date(); d.setDate(d.getDate() - 1); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function LivestockDailyClosingPage() {
  const { toast } = useToast()
  const [date, setDate] = useState(yesterday())
  const [days, setDays] = useState<DayListItem[]>([])
  const [s, setS] = useState<DaySummary | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [reopening, setReopening] = useState(false)

  const load = useCallback(async () => {
    setError(null); setS(null)
    try {
      const [sum, list] = await Promise.all([getDaySummary(date), listDays(30)])
      setS(sum); setDays(list)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [date])
  useEffect(() => { load(); setNotes("") }, [load])

  const close = async () => {
    setSaving(true)
    try {
      await closeDay(date, (s?.problems.length ?? 0) > 0, notes.trim() || null)
      toast({ title: `${fmtDate(date)} closed` }); load()
    } catch (e: any) { toast({ title: "Not closed", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <LivestockPage title="Daily closing" description="Check each day and close it, so its records are kept as they are." icon={CalendarCheck}>
      <div className="flex gap-1 overflow-x-auto pb-1">
        {days.slice(0, 14).map((d) => (
          <button key={d.date} onClick={() => setDate(d.date)}
            className={cn("shrink-0 rounded-md border px-2 py-1 text-xs text-center min-w-16",
              d.date === date ? "border-amber-600 bg-amber-50" : "border-stone-200 bg-white hover:border-stone-300")}>
            <div className="font-medium">{new Date(d.date + "T00:00:00").toLocaleDateString(undefined, { day: "2-digit", month: "short" })}</div>
            <div className={d.status === "Closed" ? "text-emerald-700" : d.status === "Reopened" ? "text-amber-700" : "text-stone-400"}>
              {d.status === "Closed" ? "Closed" : d.status === "Reopened" ? "Reopened" : "Open"}
            </div>
          </button>
        ))}
        <Input type="date" className="w-40 shrink-0" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} aria-label="Day" />
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !s ? <Loading /> : (
        <>
          {s.isClosed ? (
            <div className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900 flex items-center justify-between gap-3 flex-wrap">
              <span className="flex items-center gap-2"><Lock className="h-4 w-4" />Closed by {s.closing?.closedBy} {s.closing?.closedAt && `on ${fmtDate(s.closing.closedAt)}`}{s.closing?.notes ? ` · ${s.closing.notes}` : ""}</span>
              <Button variant="outline" size="sm" onClick={() => setReopening(true)}><Unlock className="h-4 w-4 mr-1" />Reopen</Button>
            </div>
          ) : s.closing?.status === "Reopened" && (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">Reopened by {s.closing.reopenedBy}: {s.closing.reopenReason}</div>
          )}

          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
            <StatCard label="Animals at day end" value={fmtNum(s.totals.head)} tone="amber" />
            <StatCard label="Died" value={fmtNum(s.totals.deaths)} tone={s.totals.deaths ? "rose" : "stone"} />
            {s.totals.eggs != null && <StatCard label="Eggs" value={fmtNum(s.totals.eggs)} />}
            {s.totals.milk != null && <StatCard label="Milk (L)" value={fmtNum(s.totals.milk)} />}
            <StatCard label="Sales" value={fmtMoney(s.totals.sales)} hint={`${s.totals.salesCount} sale(s)`} />
          </div>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Animals</CardTitle></CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Group</TableHead><TableHead className="text-right">Start</TableHead><TableHead className="text-right">Born</TableHead><TableHead className="text-right">Died</TableHead><TableHead className="text-right">Culled</TableHead><TableHead className="text-right">Sold</TableHead><TableHead className="text-right">End</TableHead><TableHead className="text-right">Produce</TableHead><TableHead className="text-right">Feed</TableHead><TableHead>Record</TableHead></TableRow></TableHeader>
                <TableBody>
                  {s.groups.map((g) => (
                    <TableRow key={g.groupId}>
                      <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link></TableCell>
                      <TableCell className="text-right">{fmtNum(g.headStart)}</TableCell>
                      <TableCell className="text-right">{g.born || ""}</TableCell>
                      <TableCell className={`text-right ${g.deaths ? "text-rose-700" : ""}`}>{g.deaths || ""}</TableCell>
                      <TableCell className="text-right">{g.culls || ""}</TableCell>
                      <TableCell className="text-right">{g.sold || ""}</TableCell>
                      <TableCell className="text-right font-medium">{fmtNum(g.headEnd)}</TableCell>
                      <TableCell className="text-right">{[g.eggs != null && `${g.eggs} eggs`, g.milk != null && `${g.milk} L`].filter(Boolean).join(", ")}</TableCell>
                      <TableCell className="text-right">{g.feedCost ? fmtMoney(g.feedCost) : ""}</TableCell>
                      <TableCell>{g.recordId
                        ? <Link className="text-emerald-700 hover:underline" href={`/livestock-production-records/${g.recordId}`}><CheckCircle2 className="inline h-4 w-4" /></Link>
                        : !s.isClosed && <Link className="text-rose-700 hover:underline text-sm" href={`/livestock-production-records/new?groupId=${g.groupId}&date=${date}`}>Add</Link>}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Money</CardTitle></CardHeader>
            <CardContent>
              <Table>
                <TableHeader><TableRow><TableHead>Account</TableHead><TableHead className="text-right">Start of day</TableHead><TableHead className="text-right">In</TableHead><TableHead className="text-right">Out</TableHead><TableHead className="text-right">End of day</TableHead></TableRow></TableHeader>
                <TableBody>
                  {s.money.map((m) => (
                    <TableRow key={m.accountId}>
                      <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-cash-accounts/${m.accountId}`}>{m.name}</Link></TableCell>
                      <TableCell className="text-right">{fmtMoney(m.opening)}</TableCell>
                      <TableCell className="text-right text-emerald-700">{m.moneyIn ? fmtMoney(m.moneyIn) : ""}</TableCell>
                      <TableCell className="text-right text-rose-700">{m.moneyOut ? fmtMoney(m.moneyOut) : ""}</TableCell>
                      <TableCell className={`text-right font-medium ${m.closing < 0 ? "text-rose-700" : ""}`}>{fmtMoney(m.closing)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              <p className="text-xs text-stone-500 mt-2">Count the cash box against "End of day" on <Link className="underline" href="/livestock-cash-reconciliation">Count the money</Link> before closing.</p>
            </CardContent>
          </Card>

          {!s.isClosed && (
            <Card className={s.problems.length ? "border-amber-300" : "border-emerald-300"}>
              <CardContent className="p-4 space-y-3">
                {s.problems.length > 0 ? (
                  <>
                    <div className="font-medium text-amber-900 flex items-center gap-2"><AlertTriangle className="h-4 w-4" />Before closing</div>
                    <ul className="list-disc pl-5 text-sm text-stone-700">{s.problems.map((p, i) => <li key={i}>{p.message}</li>)}</ul>
                    <div>
                      <Label htmlFor="dc-notes">Fix these, or say why the day is being closed anyway</Label>
                      <Textarea id="dc-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
                    </div>
                  </>
                ) : <div className="text-sm text-emerald-800 flex items-center gap-2"><CheckCircle2 className="h-4 w-4" />Everything for the day is recorded.</div>}
                <Button className={AMBER_BUTTON} disabled={saving || date > todayIso() || (s.problems.length > 0 && !notes.trim())} onClick={close}>
                  <Lock className="h-4 w-4 mr-1" />{saving ? "Closing…" : s.problems.length ? "Close anyway" : `Close ${fmtDate(date)}`}
                </Button>
              </CardContent>
            </Card>
          )}
          {s.isClosed && s.closing?.acknowledged && (
            <div className="text-sm text-stone-600">Closed with: {s.closing.acknowledged.map((p) => p.message).join(" ")} <Badge variant="outline">acknowledged</Badge></div>
          )}
        </>
      )}
      <PromptDialog open={reopening} onOpenChange={setReopening} title={`Reopen ${fmtDate(date)}?`}
        description="Its records can then be changed. Close it again when done." label="Why" confirmLabel="Reopen"
        onSubmit={async (r) => { await reopenDay(date, r); setReopening(false); load() }} />
    </LivestockPage>
  )
}

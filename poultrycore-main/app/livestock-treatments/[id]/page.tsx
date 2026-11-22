"use client"

// One treatment campaign: the groups and their dose, record a day (each
// group's quantity suggested from its head), the days recorded, and complete
// or cancel. A day can be reversed; its medicine goes back into stock.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams } from "next/navigation"
import { Pill } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { closeTreatment, getTreatment, postTreatmentDay, reverseTreatmentDay, type Treatment, type TreatmentDay } from "@/lib/api/livestock"
import { TREATMENT_STATUS } from "@/components/livestock/labels"
import {
  AMBER_BUTTON, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"

const BASIS = { PerAnimal: "per animal", Per100Animals: "per 100 animals", PerGroup: "per group" } as const

export default function LivestockTreatmentPage() {
  const { id } = useParams<{ id: string }>()
  const treatmentId = Number(id)
  const { toast } = useToast()
  const [t, setT] = useState<Treatment | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [date, setDate] = useState(todayIso())
  const [qty, setQty] = useState<Record<number, string>>({})
  const [posting, setPosting] = useState(false)
  const [reversing, setReversing] = useState<TreatmentDay | null>(null)
  const [closing, setClosing] = useState<null | "Complete" | "Cancel">(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const x = await getTreatment(treatmentId)
      setT(x)
      setQty(Object.fromEntries(x.groups.map((g) => [g.groupId, String(g.suggested)])))
      const today = todayIso()
      setDate(today < x.startDate ? x.startDate : today > x.endDate ? x.endDate : today)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [treatmentId])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-treatments", label: "Treatment campaigns" }
  if (error) return <LivestockPage title="Treatment" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!t) return <LivestockPage title="Treatment" back={back}><Loading /></LivestockPage>

  const open = t.lifecycle === "Open"
  const already = t.days.some((d) => !d.reversedAt && d.date === date)
  const post = async () => {
    setPosting(true)
    try {
      await postTreatmentDay(treatmentId, date, t.groups.map((g) => ({ groupId: g.groupId, quantity: Number(qty[g.groupId] ?? 0) })), null)
      toast({ title: `${fmtDate(date)} recorded` })
      load()
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setPosting(false) }
  }

  return (
    <LivestockPage
      title={<>{t.name} <Badge className={`ml-2 align-middle ${TREATMENT_STATUS[t.status].cls}`}>{TREATMENT_STATUS[t.status].label}</Badge></>}
      description={`${t.itemName} · ${fmtNum(t.doseQuantity)} ${t.unit} ${BASIS[t.doseBasis]} a day · ${fmtDate(t.startDate)} – ${fmtDate(t.endDate)}`}
      icon={Pill}
      back={back}
      actions={open ? (
        <>
          <Button variant="outline" onClick={() => setClosing("Complete")}>Mark completed</Button>
          <Button variant="outline" className="text-rose-700" onClick={() => setClosing("Cancel")}>Cancel</Button>
        </>
      ) : undefined}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <StatCard label="Days given" value={`${t.postedDays} of ${t.plannedDays}`} tone="amber" />
        <StatCard label="Medicine used" value={`${fmtNum(t.totalQuantity)} ${t.unit}`} />
        <StatCard label="Cost" value={fmtMoney(t.totalCost)} />
        <StatCard label="Withdrawal" value={[t.meatWithdrawalDays != null && `meat ${t.meatWithdrawalDays}d`,
          t.milkWithdrawalDays != null && `milk ${t.milkWithdrawalDays}d`, t.eggWithdrawalDays != null && `eggs ${t.eggWithdrawalDays}d`].filter(Boolean).join(", ") || "None"} />
      </div>

      {open && (
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Record a day</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="w-48">
              <Label htmlFor="td-date">Date</Label>
              <Input id="td-date" type="date" min={t.startDate} max={t.endDate < todayIso() ? t.endDate : todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            {already ? <p className="text-sm text-amber-800">{fmtDate(date)} is already recorded.</p> : (
              <>
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Group</TableHead><TableHead className="text-right">Animals</TableHead><TableHead className="w-40">Given ({t.unit})</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {t.groups.map((g) => (
                      <TableRow key={g.groupId}>
                        <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link>{g.status !== "Active" && " (closed)"}</TableCell>
                        <TableCell className="text-right">{fmtNum(g.head)}</TableCell>
                        <TableCell>
                          <Input type="number" min={0} step="any" value={qty[g.groupId] ?? ""} disabled={g.status !== "Active"}
                            onChange={(e) => setQty((q) => ({ ...q, [g.groupId]: e.target.value }))} />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <p className="text-xs text-stone-500">0 skips a group that day.</p>
                <Button className={AMBER_BUTTON} disabled={posting} onClick={post}>{posting ? "Saving…" : `Record ${fmtDate(date)}`}</Button>
              </>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Days recorded</CardTitle></CardHeader>
        <CardContent>
          {t.days.length === 0 ? <p className="text-sm text-stone-500">No day recorded yet.</p> : (
            <ul className="divide-y text-sm">
              {t.days.map((d) => (
                <li key={d.dayId} className={`py-2 flex items-center justify-between gap-3 ${d.reversedAt ? "opacity-50" : ""}`}>
                  <div>
                    <span className="font-medium">{fmtDate(d.date)}</span>
                    {d.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                    <div className="text-stone-600">{d.lines.map((l) => `${l.groupName} ${fmtNum(l.quantity)} ${t.unit}`).join(" · ")}</div>
                    {d.reverseReason && <div className="text-xs">Reversed: {d.reverseReason}</div>}
                  </div>
                  {!d.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(d)}>Reverse</Button>}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title={reversing ? `Reverse ${fmtDate(reversing.date)}?` : ""}
        description="The medicine goes back into stock."
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseTreatmentDay(reversing!.dayId, reason); setReversing(null); load() }}
      />
      <PromptDialog
        open={!!closing}
        onOpenChange={(o) => !o && setClosing(null)}
        title={closing === "Cancel" ? "Cancel this treatment?" : "Mark this treatment completed?"}
        description={closing === "Cancel" ? "Days already recorded stay recorded." : "No more days can be recorded after this."}
        label={closing === "Cancel" ? "Why" : "Note (optional)"}
        allowEmpty={closing !== "Cancel"}
        confirmLabel={closing === "Cancel" ? "Cancel treatment" : "Mark completed"}
        confirmVariant={closing === "Cancel" ? "destructive" : "default"}
        onSubmit={async (reason) => { await closeTreatment(treatmentId, closing!, reason || null); setClosing(null); load() }}
      />
    </LivestockPage>
  )
}

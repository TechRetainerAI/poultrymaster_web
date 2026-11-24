"use client"

// Treatment Campaigns -- one medicine for several groups over several days
// (poultry 339 for livestock), and the groups still under a withdrawal period.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Pill, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import {
  createTreatment, listGroups, listItems, listTreatments, listWithdrawals,
  type DoseBasis, type LivestockGroup, type LivestockItem, type Treatment, type TreatmentInput, type Withdrawal,
} from "@/lib/api/livestock"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import { TREATMENT_STATUS } from "@/components/livestock/labels"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"

export default function LivestockTreatmentsPage() {
  const router = useRouter()
  const [rows, setRows] = useState<Treatment[] | null>(null)
  const [withdrawals, setWithdrawals] = useState<Withdrawal[]>([])
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [t, w] = await Promise.all([listTreatments(), listWithdrawals().catch(() => [])])
      setRows(t); setWithdrawals(w)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])
  const pg = usePagination(rows ?? [], 10)

  return (
    <LivestockPage
      title="Treatment campaigns"
      description="One medicine for several groups over several days, and when their meat, milk or eggs can be sold again."
      icon={Pill}
      actions={<Button className={AMBER_BUTTON} onClick={() => setCreating(true)}><Plus className="h-4 w-4 mr-1" /> New treatment</Button>}
    >
      {withdrawals.length > 0 && (
        <div className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900 space-y-1">
          <div className="font-medium">Do not sell yet</div>
          {withdrawals.map((w) => (
            <div key={`${w.groupId}-${w.treatmentId}`}>
              {w.groupName}: {[w.meatUntil && w.meatUntil >= todayIso() && `meat until ${fmtDate(w.meatUntil)}`,
                w.milkUntil && w.milkUntil >= todayIso() && `milk until ${fmtDate(w.milkUntil)}`,
                w.eggsUntil && w.eggsUntil >= todayIso() && `eggs until ${fmtDate(w.eggsUntil)}`].filter(Boolean).join(", ")}
              <span className="text-rose-700"> ({w.itemName})</span>
            </div>
          ))}
        </div>
      )}

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title="No treatments yet">Use a treatment when one medicine goes to several groups for several days.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Treatment</TableHead><TableHead>Medicine</TableHead><TableHead>Dates</TableHead>
                <TableHead>Groups</TableHead><TableHead className="text-right">Days given</TableHead>
                <TableHead className="text-right">Cost</TableHead><TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((t) => (
                <TableRow key={t.treatmentId} className="cursor-pointer hover:bg-amber-50/60" onClick={() => router.push(`/livestock-treatments/${t.treatmentId}`)}>
                  <TableCell className="font-medium"><Link href={`/livestock-treatments/${t.treatmentId}`} onClick={(e) => e.stopPropagation()} className="hover:underline">{t.name}</Link></TableCell>
                  <TableCell>{t.itemName}</TableCell>
                  <TableCell className="whitespace-nowrap">{fmtDate(t.startDate)} – {fmtDate(t.endDate)}</TableCell>
                  <TableCell>{t.groups.map((g) => g.name).join(", ")}</TableCell>
                  <TableCell className="text-right">{t.postedDays} of {t.plannedDays}</TableCell>
                  <TableCell className="text-right">{fmtMoney(t.totalCost)}</TableCell>
                  <TableCell><Badge className={TREATMENT_STATUS[t.status].cls}>{TREATMENT_STATUS[t.status].label}</Badge></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}

      {creating && <CreateTreatmentDialog onClose={() => setCreating(false)} onCreated={(id) => router.push(`/livestock-treatments/${id}`)} />}
    </LivestockPage>
  )
}

function CreateTreatmentDialog({ onClose, onCreated }: { onClose: () => void; onCreated: (id: number) => void }) {
  const { toast } = useToast()
  const features = useLivestockFeatures()
  const [items, setItems] = useState<LivestockItem[]>([])
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [f, setF] = useState<TreatmentInput>({
    name: "", itemId: 0, reason: null, startDate: todayIso(), endDate: todayIso(), doseQuantity: 0, doseBasis: "PerAnimal",
    meatWithdrawalDays: null, milkWithdrawalDays: null, eggWithdrawalDays: null, notes: null, groupIds: [],
  })
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    listItems("Health").then(setItems).catch(() => setItems([]))
    listGroups().then(setGroups).catch(() => setGroups([]))
  }, [])
  const item = items.find((i) => i.itemId === f.itemId)
  const usableGroups = groups.filter((g) => !item?.speciesCode || g.speciesCode === item.speciesCode)
  const set = <K extends keyof TreatmentInput>(k: K, v: TreatmentInput[K]) => setF((s) => ({ ...s, [k]: v }))
  const num = (v: string) => (v === "" ? null : Number(v))
  const perDay = usableGroups.filter((g) => f.groupIds.includes(g.groupId)).reduce((s, g) =>
    s + (f.doseBasis === "PerAnimal" ? f.doseQuantity * g.head : f.doseBasis === "Per100Animals" ? f.doseQuantity * g.head / 100 : f.doseQuantity), 0)

  const save = async () => {
    setSaving(true)
    try { const r = await createTreatment(f); toast({ title: "Treatment created" }); onCreated(r.treatmentId) }
    catch (e: any) { toast({ title: "Not created", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  const canSave = f.name.trim() && f.itemId && f.doseQuantity > 0 && f.groupIds.length > 0 && f.endDate >= f.startDate

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader><DialogTitle>New treatment</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="t-name">Name</Label>
              <Input id="t-name" value={f.name} onChange={(e) => set("name", e.target.value)} placeholder="Coccidiosis treatment" />
            </div>
            <div>
              <Label>Medicine or vaccine</Label>
              <Select value={f.itemId ? String(f.itemId) : ""} onValueChange={(v) => setF((s) => ({ ...s, itemId: Number(v), groupIds: [] }))}>
                <SelectTrigger><SelectValue placeholder={items.length ? "Choose" : "Add it under Feed & stock first"} /></SelectTrigger>
                <SelectContent>{items.map((i) => <SelectItem key={i.itemId} value={String(i.itemId)}>{i.name} · {fmtNum(i.stock)} {i.unit} left</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="t-start">First day</Label><Input id="t-start" type="date" value={f.startDate} onChange={(e) => set("startDate", e.target.value)} /></div>
            <div><Label htmlFor="t-end">Last day</Label><Input id="t-end" type="date" min={f.startDate} value={f.endDate} onChange={(e) => set("endDate", e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label htmlFor="t-dose">Dose each day{item ? ` (${item.unit})` : ""}</Label>
              <Input id="t-dose" type="number" min={0} step="any" value={f.doseQuantity || ""} onChange={(e) => set("doseQuantity", Number(e.target.value))} />
            </div>
            <div>
              <Label>Per</Label>
              <Select value={f.doseBasis} onValueChange={(v) => set("doseBasis", v as DoseBasis)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="PerAnimal">Animal</SelectItem>
                  <SelectItem value="Per100Animals">100 animals</SelectItem>
                  <SelectItem value="PerGroup">Group</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div>
            <Label>Groups</Label>
            <div className="grid grid-cols-2 gap-1 mt-1 rounded-md border p-2 max-h-40 overflow-y-auto">
              {usableGroups.map((g) => (
                <label key={g.groupId} className="flex items-center gap-2 text-sm">
                  <Checkbox checked={f.groupIds.includes(g.groupId)}
                    onCheckedChange={(c) => set("groupIds", c ? [...f.groupIds, g.groupId] : f.groupIds.filter((x) => x !== g.groupId))} />
                  {g.name} <span className="text-stone-500">· {g.head}</span>
                </label>
              ))}
            </div>
            {perDay > 0 && item && <p className="text-xs text-stone-500 mt-1">About {fmtNum(Math.round(perDay * 1000) / 1000)} {item.unit} a day; {fmtNum(item.stock)} in stock.</p>}
          </div>
          <div>
            <Label>Withdrawal: days after the last dose before selling</Label>
            <div className="grid grid-cols-3 gap-3 mt-1">
              <Input type="number" min={0} placeholder="Meat" value={f.meatWithdrawalDays ?? ""} onChange={(e) => set("meatWithdrawalDays", num(e.target.value))} aria-label="Meat withdrawal days" />
              {features.milk && <Input type="number" min={0} placeholder="Milk" value={f.milkWithdrawalDays ?? ""} onChange={(e) => set("milkWithdrawalDays", num(e.target.value))} aria-label="Milk withdrawal days" />}
              {features.eggs && <Input type="number" min={0} placeholder="Eggs" value={f.eggWithdrawalDays ?? ""} onChange={(e) => set("eggWithdrawalDays", num(e.target.value))} aria-label="Egg withdrawal days" />}
            </div>
          </div>
          <div>
            <Label htmlFor="t-reason">Reason</Label>
            <Textarea id="t-reason" rows={2} value={f.reason ?? ""} onChange={(e) => set("reason", e.target.value || null)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>{saving ? "Saving…" : "Create"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

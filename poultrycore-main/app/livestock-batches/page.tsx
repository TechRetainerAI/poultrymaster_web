"use client"

// Intake Batches -- the poultry Flock Batch page for livestock: animals bought
// or brought in together, then divided into groups (poultry's Divide Into
// Flocks). A batch shows how many of its animals are not in a group yet.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Package, Pencil, Plus, Split, Trash2, Warehouse, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  deleteBatch, divideBatch, listBatches, listPens, saveBatch,
  type BatchInput, type DivideGroupInput, type IntakeSource, type LivestockBatch, type LivestockPen,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"
import { AgeTextInput, BreedSelect } from "@/components/livestock/breed-age-inputs"
import { QuickPensDialog } from "@/components/livestock/quick-pens-dialog"
import { usePermissions } from "@/hooks/use-permissions"

const NONE = "__none"

export default function LivestockBatchesPage() {
  const { toast } = useToast()
  const router = useRouter()
  const { kept, byCode, loaded } = useLivestockSpecies()
  const [batches, setBatches] = useState<LivestockBatch[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<{ id?: number; input: BatchInput } | null>(null)
  const [saving, setSaving] = useState(false)
  const [dividing, setDividing] = useState<LivestockBatch | null>(null)
  const [deleting, setDeleting] = useState<LivestockBatch | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setBatches(await listBatches()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  const blank = (): BatchInput => ({
    batchCode: null, speciesCode: kept[0]?.speciesCode ?? "", breed: null, quantity: 0, intakeDate: todayIso(),
    source: "Purchased", supplierId: null, costPerHead: null, totalCost: null, ageAtIntake: null, notes: null,
  })
  const set = <K extends keyof BatchInput>(k: K, v: BatchInput[K]) =>
    setEditing((e) => (e ? { ...e, input: { ...e.input, [k]: v } } : e))

  const save = async () => {
    if (!editing) return
    setSaving(true)
    try {
      const { batchId } = await saveBatch(editing.input, editing.id)
      toast({ title: editing.id ? "Batch updated" : "Batch recorded" })
      const wasNew = !editing.id
      setEditing(null)
      await load()
      if (wasNew) {
        const fresh = (await listBatches()).find((b) => b.batchId === batchId)
        if (fresh) setDividing(fresh)
      }
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <LivestockPage
      title="Intake batches"
      description="Animals bought or brought in together, then divided into groups."
      icon={Package}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-purchases/new?animals=1">Buy animals</Link></Button>
          <Button className={AMBER_BUTTON} disabled={loaded && kept.length === 0} onClick={() => setEditing({ input: blank() })}>
            <Plus className="h-4 w-4 mr-1" /> Record intake
          </Button>
        </>
      }
    >
      {error ? <LoadError message={error} onRetry={load} /> : !batches ? <Loading /> : batches.length === 0 ? (
        <EmptyState title="No intake batches yet">
          When you buy or bring in animals, record them here, then divide them into groups.
          {loaded && kept.length === 0 && <> First <Link className="underline" href="/livestock-animals-kept">choose the animals you keep</Link>.</>}
        </EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Batch</TableHead>
                <TableHead>Animal</TableHead>
                <TableHead>Came in</TableHead>
                <TableHead className="text-right">Animals</TableHead>
                <TableHead className="text-right">Not in a group</TableHead>
                <TableHead className="text-right">Total cost</TableHead>
                <TableHead>Groups</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {batches.map((b) => (
                <TableRow key={b.batchId}>
                  <TableCell className="font-medium">{b.batchCode}{b.breed && <div className="text-xs text-stone-500">{b.breed}</div>}</TableCell>
                  <TableCell>{b.speciesName}</TableCell>
                  <TableCell className="whitespace-nowrap">{fmtDate(b.intakeDate)}</TableCell>
                  <TableCell className="text-right">{fmtNum(b.quantity)}</TableCell>
                  <TableCell className={`text-right ${b.unallocated > 0 ? "text-amber-800 font-medium" : "text-stone-400"}`}>{fmtNum(b.unallocated)}</TableCell>
                  <TableCell className="text-right">{fmtMoney(b.totalCost)}</TableCell>
                  <TableCell className="text-sm">
                    {b.groups.length === 0 ? "—" : b.groups.map((g, i) => (
                      <span key={g.groupId}>{i > 0 && ", "}<Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link></span>
                    ))}
                  </TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    {b.unallocated > 0 && (
                      <Button variant="outline" size="sm" onClick={() => setDividing(b)}><Split className="h-4 w-4 mr-1" />Divide</Button>
                    )}
                    <Button variant="ghost" size="icon" aria-label={`Edit ${b.batchCode}`} onClick={() => setEditing({ id: b.batchId, input: {
                      batchCode: b.batchCode, speciesCode: b.speciesCode, breed: b.breed, quantity: b.quantity, intakeDate: b.intakeDate,
                      source: b.source, supplierId: b.supplierId, costPerHead: b.costPerHead, totalCost: b.totalCost,
                      ageAtIntake: b.ageAtIntake, notes: b.notes } })}>
                      <Pencil className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="icon" aria-label={`Delete ${b.batchCode}`} onClick={() => setDeleting(b)}>
                      <Trash2 className="h-4 w-4 text-rose-600" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>{editing?.id ? "Edit intake batch" : "Record an intake"}</DialogTitle></DialogHeader>
          {editing && (
            <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label>Animal</Label>
                  <Select value={editing.input.speciesCode} onValueChange={(v) => setEditing((s) => s && ({ ...s, input: { ...s.input, speciesCode: v, breed: null } }))}>
                    <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                    <SelectContent>{kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                <div>
                  <Label htmlFor="b-code">Batch code</Label>
                  <Input id="b-code" value={editing.input.batchCode ?? ""} placeholder="Made for you"
                    onChange={(e) => set("batchCode", e.target.value || null)} />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label htmlFor="b-qty">How many animals</Label>
                  <Input id="b-qty" type="number" min={1} inputMode="numeric" value={editing.input.quantity || ""}
                    onChange={(e) => set("quantity", Number(e.target.value))} />
                </div>
                <div>
                  <Label htmlFor="b-date">Date they came in</Label>
                  <Input id="b-date" type="date" max={todayIso()} value={editing.input.intakeDate} onChange={(e) => set("intakeDate", e.target.value)} />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label>Came from</Label>
                  <Select value={editing.input.source} onValueChange={(v) => set("source", v as IntakeSource)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Purchased">Bought</SelectItem>
                      <SelectItem value="Gift">Gift</SelectItem>
                      <SelectItem value="Transfer">Another farm of ours</SelectItem>
                      <SelectItem value="Other">Other</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label htmlFor="b-age">Age when they came</Label>
                  <AgeTextInput key={editing.id ?? "new"} id="b-age" value={editing.input.ageAtIntake} onChange={(v) => set("ageAtIntake", v)} />
                </div>
              </div>
              {editing.input.source === "Purchased" && (
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <Label htmlFor="b-cph">Cost per animal</Label>
                    <Input id="b-cph" type="number" min={0} step="0.01" value={editing.input.costPerHead ?? ""}
                      onChange={(e) => setEditing((s) => s && ({ ...s, input: { ...s.input,
                        costPerHead: e.target.value === "" ? null : Number(e.target.value), totalCost: null } }))} />
                  </div>
                  <div>
                    <Label htmlFor="b-total">Total cost</Label>
                    <Input id="b-total" type="number" min={0} step="0.01"
                      value={editing.input.totalCost ?? (editing.input.costPerHead != null && editing.input.quantity
                        ? Math.round(editing.input.costPerHead * editing.input.quantity * 100) / 100 : "")}
                      onChange={(e) => setEditing((s) => s && ({ ...s, input: { ...s.input,
                        totalCost: e.target.value === "" ? null : Number(e.target.value), costPerHead: null } }))} />
                  </div>
                </div>
              )}
              <div>
                <Label htmlFor="b-breed">Breed</Label>
                <BreedSelect id="b-breed" speciesCode={editing.input.speciesCode} value={editing.input.breed} onChange={(v) => set("breed", v)} />
              </div>
              <div>
                <Label htmlFor="b-notes">Notes</Label>
                <Textarea id="b-notes" rows={2} value={editing.input.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditing(null)}>Cancel</Button>
            <Button className={AMBER_BUTTON} disabled={saving || !editing?.input.speciesCode || !(editing?.input.quantity > 0)} onClick={save}>
              {saving ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {dividing && (
        <DivideDialog batch={dividing} groupTerm={byCode.get(dividing.speciesCode)?.groupTerm ?? "Group"}
          penTerm={byCode.get(dividing.speciesCode)?.penTerm ?? "Pen"}
          onClose={() => setDividing(null)}
          onDone={(ids) => { setDividing(null); load(); if (ids.length === 1) router.push(`/livestock-groups/${ids[0]}`) }} />
      )}

      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete intake batch?"
        itemLabel={deleting?.batchCode}
        onConfirm={() => deleteBatch(deleting!.batchId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </LivestockPage>
  )
}

function DivideDialog({ batch, groupTerm, penTerm, onClose, onDone }: {
  batch: LivestockBatch
  groupTerm: string
  penTerm: string
  onClose: () => void
  onDone: (groupIds: number[]) => void
}) {
  const { toast } = useToast()
  const [pens, setPens] = useState<LivestockPen[]>([])
  const [startDate, setStartDate] = useState(batch.intakeDate)
  const [rows, setRows] = useState<DivideGroupInput[]>([
    { name: `${batch.batchCode} ${groupTerm} 1`, penId: null, quantity: batch.unallocated, purpose: "Meat", notes: null },
  ])
  const [saving, setSaving] = useState(false)
  const [addingPens, setAddingPens] = useState(false)
  const { isAdmin } = usePermissions()

  const loadPens = useCallback(async () => {
    try {
      const p = await listPens()
      setPens(p.filter((x) => x.isActive && (!x.speciesCode || x.speciesCode === batch.speciesCode)))
    } catch { setPens([]) }
  }, [batch.speciesCode])
  useEffect(() => { loadPens() }, [loadPens])

  // New pens fill the groups that have no pen yet, in order; any pens left
  // over each get a new group, so "add 4 hutches" gives 4 groups to fill.
  const pensCreated = async (penIds: number[]) => {
    setAddingPens(false)
    await loadPens()
    setRows((rs) => {
      const queue = [...penIds]
      const next = rs.map((r) => (r.penId == null && queue.length ? { ...r, penId: queue.shift()! } : r))
      for (const penId of queue) {
        next.push({ name: `${batch.batchCode} ${groupTerm} ${next.length + 1}`, penId, quantity: 0, purpose: "Meat", notes: null })
      }
      return next
    })
  }

  const total = rows.reduce((s, r) => s + (Number(r.quantity) || 0), 0)
  const left = batch.unallocated - total
  const setRow = (i: number, patch: Partial<DivideGroupInput>) => setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...patch } : r)))

  const save = async () => {
    setSaving(true)
    try {
      const ids = await divideBatch(batch.batchId, startDate, rows)
      toast({ title: `${ids.length} group(s) created` })
      onDone(ids)
    } catch (e: any) {
      toast({ title: "Not divided", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader><DialogTitle>Divide {batch.batchCode} into groups</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-stone-600">{batch.unallocated} of {batch.quantity} {batch.speciesName.toLowerCase()} are not in a group yet.</p>
          <div className="w-48">
            <Label htmlFor="d-date">Groups start on</Label>
            <Input id="d-date" type="date" min={batch.intakeDate} max={todayIso()} value={startDate} onChange={(e) => setStartDate(e.target.value)} />
          </div>
          <div className="space-y-2">
            {rows.map((r, i) => (
              <div key={i} className="grid grid-cols-[1fr_7rem_10rem_auto] gap-2 items-end">
                <div>
                  {i === 0 && <Label>Name</Label>}
                  <Input value={r.name} onChange={(e) => setRow(i, { name: e.target.value })} />
                </div>
                <div>
                  {i === 0 && <Label>Animals</Label>}
                  <Input type="number" min={1} inputMode="numeric" value={r.quantity || ""} onChange={(e) => setRow(i, { quantity: Number(e.target.value) })} />
                </div>
                <div>
                  {i === 0 && <Label>Pen</Label>}
                  <Select value={r.penId ? String(r.penId) : NONE} onValueChange={(v) => setRow(i, { penId: v === NONE ? null : Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={NONE}>No pen</SelectItem>
                      {pens.map((p) => <SelectItem key={p.penId} value={String(p.penId)}>{p.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <Button variant="ghost" size="icon" aria-label="Remove row" disabled={rows.length === 1}
                  onClick={() => setRows((rs) => rs.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
              </div>
            ))}
          </div>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 flex-wrap w-full">
            <Button variant="outline" size="sm" onClick={() => setRows((rs) => [...rs, {
              name: `${batch.batchCode} ${groupTerm} ${rs.length + 1}`, penId: null, quantity: Math.max(left, 0), purpose: "Meat", notes: null }])}>
              <Plus className="h-4 w-4 mr-1" /> Add a group
            </Button>
            {isAdmin && (
              <Button variant="outline" size="sm" onClick={() => setAddingPens(true)}>
                <Warehouse className="h-4 w-4 mr-1" /> Quickly add {penTerm.toLowerCase()}s
              </Button>
            )}
            <span className={`ml-auto text-sm ${left < 0 ? "text-rose-700 font-medium" : "text-stone-600"}`}>
              {left < 0 ? `${-left} more than the batch has` : `${left} left over`}
            </span>
            </div>
          </div>
          {pens.length === 0 && (
            <p className="text-xs text-stone-500">No {penTerm.toLowerCase()}s for {batch.speciesName.toLowerCase()} yet.{isAdmin ? ` Use "Quickly add ${penTerm.toLowerCase()}s" to make some now.` : " Ask the owner to add them on Setup → Pens."}</p>
          )}
        </div>
        {addingPens && (
          <QuickPensDialog speciesCode={batch.speciesCode} speciesName={batch.speciesName} penTerm={penTerm}
            existing={pens} onClose={() => setAddingPens(false)} onCreated={pensCreated} />
        )}
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || left < 0 || total === 0 || rows.some((r) => !r.name.trim() || !(r.quantity > 0))} onClick={save}>
            {saving ? "Saving…" : "Create groups"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

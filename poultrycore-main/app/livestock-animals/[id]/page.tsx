"use client"

// One tagged animal: details, parents and offspring, where it has been, and
// the jobs done on it -- mark sold / died / culled (or back to alive), move to
// another group, edit, delete a tag entered by mistake.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { Baby, MoreHorizontal, Pencil, Scale, Shuffle, Tag, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  deleteAnimal, getAnimal, listAnimalWeights, listBreeding, listGroups, moveAnimal, setAnimalStatus,
  type AnimalStatus, type BreedingEvent, type LivestockAnimalDetail, type LivestockGroup,
} from "@/lib/api/livestock"
import { AnimalFormDialog } from "@/components/livestock/animal-form-dialog"
import { MOVEMENT_LABEL, breedingSummary } from "@/components/livestock/labels"
import { BreedingDialog } from "@/components/livestock/breeding-dialog"
import { WeighInDialog } from "@/components/livestock/growth-panel"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import {
  AMBER_BUTTON, LivestockPage, LoadError, Loading, fmtAge, fmtDate, fmtMoney, todayIso,
} from "@/components/livestock/livestock-page"

const STATUS_LABEL: Record<AnimalStatus, string> = { Active: "Alive", Sold: "Sold", Dead: "Died", Culled: "Culled" }

export default function LivestockAnimalPage() {
  const { id } = useParams<{ id: string }>()
  const animalId = Number(id)
  const router = useRouter()
  const { toast } = useToast()
  const [a, setA] = useState<LivestockAnimalDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [dialog, setDialog] = useState<null | "edit" | "status" | "move" | "delete" | "breeding" | "weigh">(null)
  const [weights, setWeights] = useState<{ weighInId: number; date: string; avgWeightKg: number; notes: string | null }[]>([])
  const [breeding, setBreeding] = useState<BreedingEvent[]>([])
  const { byCode } = useLivestockSpecies()

  const load = useCallback(async () => {
    setError(null)
    try {
      const [x, w, b] = await Promise.all([getAnimal(animalId), listAnimalWeights(animalId).catch(() => []), listBreeding({ damId: animalId }).catch(() => [])])
      setA(x); setWeights(w); setBreeding(b)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [animalId])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-animals", label: "Animal register" }
  if (error) return <LivestockPage title="Animal" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!a) return <LivestockPage title="Animal" back={back}><Loading /></LivestockPage>

  const alive = a.status === "Active"
  return (
    <LivestockPage
      title={<>Tag {a.tagNumber}{a.name ? ` · ${a.name}` : ""} <Badge variant={alive ? "default" : "outline"} className={alive ? "ml-2 bg-amber-700" : "ml-2"}>{STATUS_LABEL[a.status]}</Badge></>}
      description={[a.speciesName, a.sex !== "Unknown" && a.sex, a.breed].filter(Boolean).join(" · ")}
      icon={Tag}
      back={back}
      actions={
        <>
          {alive
            ? <Button className={AMBER_BUTTON} onClick={() => setDialog("status")}>Sold, died or culled</Button>
            : <Button variant="outline" onClick={async () => {
                try { await setAnimalStatus(animalId, "Active", null, "Set back to alive"); toast({ title: "Back to alive" }); load() }
                catch (e: any) { toast({ title: "Not changed", description: e?.message, variant: "destructive" }) }
              }}>Mark alive again</Button>}
          <DropdownMenu>
            <DropdownMenuTrigger asChild><Button variant="outline" size="icon" aria-label="More"><MoreHorizontal className="h-4 w-4" /></Button></DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => setDialog("edit")}><Pencil className="h-4 w-4 mr-2" />Edit details</DropdownMenuItem>
              {alive && <DropdownMenuItem onClick={() => setDialog("move")}><Shuffle className="h-4 w-4 mr-2" />Move to another group</DropdownMenuItem>}
              {alive && <DropdownMenuItem onClick={() => setDialog("weigh")}><Scale className="h-4 w-4 mr-2" />Record weight</DropdownMenuItem>}
              {alive && byCode.get(a.speciesCode)?.breedsOnFarm && a.sex !== "Male" && <DropdownMenuItem onClick={() => setDialog("breeding")}><Baby className="h-4 w-4 mr-2" />Record breeding</DropdownMenuItem>}
              <DropdownMenuSeparator />
              <DropdownMenuItem className="text-rose-700" onClick={() => setDialog("delete")}><Trash2 className="h-4 w-4 mr-2" />Delete tag</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </>
      }
    >
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-2">
          <CardHeader className="pb-2"><CardTitle className="text-base">Details</CardTitle></CardHeader>
          <CardContent>
            <dl className="grid grid-cols-2 sm:grid-cols-3 gap-x-4 gap-y-3 text-sm">
              <Field label="Group"><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${a.groupId}`}>{a.groupName}</Link></Field>
              <Field label="Pen">{a.penName ?? "—"}</Field>
              <Field label="Age">{fmtAge(a.ageDays)}</Field>
              <Field label="Born">{fmtDate(a.birthDate)}</Field>
              <Field label="Came from">{{ OnFarm: "Already on farm", Purchased: "Bought", BornOnFarm: "Born on farm", Other: "Other" }[a.source]}</Field>
              <Field label="Arrived">{fmtDate(a.acquiredDate)}</Field>
              <Field label="Mother">{a.damId ? <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${a.damId}`}>{a.damTag}</Link> : "—"}</Field>
              <Field label="Father">{a.sireId ? <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${a.sireId}`}>{a.sireTag}</Link> : "—"}</Field>
              {a.purchaseCost != null && <Field label="Price paid">{fmtMoney(a.purchaseCost)}</Field>}
              {!alive && <Field label={STATUS_LABEL[a.status]}>{fmtDate(a.statusDate)}{a.statusNotes ? ` · ${a.statusNotes}` : ""}</Field>}
            </dl>
            {a.notes && <p className="text-sm text-stone-600 mt-3 whitespace-pre-wrap">{a.notes}</p>}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Offspring ({a.offspring.length})</CardTitle></CardHeader>
          <CardContent className="text-sm">
            {a.offspring.length === 0 ? <p className="text-stone-500">None recorded.</p> : (
              <ul className="space-y-1">
                {a.offspring.map((o) => (
                  <li key={o.animalId} className="flex justify-between">
                    <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${o.animalId}`}>{o.tagNumber}</Link>
                    <span className="text-stone-500">{o.sex !== "Unknown" ? o.sex : ""} {fmtDate(o.birthDate)}{o.status !== "Active" ? ` · ${STATUS_LABEL[o.status]}` : ""}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      {(breeding.length > 0 || weights.length > 0) && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {breeding.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Breeding</CardTitle></CardHeader>
              <CardContent className="text-sm">
                <ul className="divide-y">
                  {breeding.map((e) => (
                    <li key={e.eventId} className="py-2 flex justify-between gap-3">
                      <span>{fmtDate(e.date)} · {breedingSummary(e).what}</span>
                      <span className="text-stone-500 text-right">{breedingSummary(e).details}</span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          )}
          {weights.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Weights</CardTitle></CardHeader>
              <CardContent className="text-sm">
                <ul className="divide-y">
                  {weights.map((w) => (
                    <li key={w.weighInId} className="py-2 flex justify-between gap-3">
                      <span>{fmtDate(w.date)}</span><span className="font-medium">{w.avgWeightKg} kg</span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">History</CardTitle></CardHeader>
        <CardContent className="text-sm">
          {a.movements.length === 0 ? <p className="text-stone-500">Tagged while already counted in its group; nothing has moved since.</p> : (
            <ul className="divide-y">
              {a.movements.map((m) => (
                <li key={m.movementId} className={`py-2 flex justify-between gap-3 ${m.reversedAt ? "opacity-50" : ""}`}>
                  <span>{fmtDate(m.date)} · {MOVEMENT_LABEL[m.type]} · {m.groupName}{m.reversedAt ? " (reversed)" : ""}</span>
                  <span className="text-stone-500 truncate">{m.notes}</span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <BreedingDialog open={dialog === "breeding"} onOpenChange={(o) => !o && setDialog(null)} preset={{ damId: animalId }} onSaved={load} />
      {dialog === "weigh" && <WeighInDialog target={{ animalId, label: `tag ${a.tagNumber}` }} onClose={() => setDialog(null)} onDone={() => { setDialog(null); load() }} />}
      <AnimalFormDialog open={dialog === "edit"} onOpenChange={(o) => !o && setDialog(null)} animal={a} onSaved={load} />
      {dialog === "status" && <StatusDialog animal={a} onClose={() => setDialog(null)} onDone={() => { setDialog(null); load() }} />}
      {dialog === "move" && <MoveDialog animal={a} onClose={() => setDialog(null)} onDone={() => { setDialog(null); load() }} />}
      <ConfirmDeleteDialog
        open={dialog === "delete"}
        onOpenChange={(o) => !o && setDialog(null)}
        title={`Delete tag ${a.tagNumber}?`}
        description="Only for a tag entered by mistake. An animal that was sold or died should be marked so instead, to keep its history."
        onConfirm={() => deleteAnimal(animalId)}
        onSuccess={() => router.push("/livestock-animals")}
      />
    </LivestockPage>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><dt className="text-xs text-stone-500">{label}</dt><dd className="text-stone-900">{children}</dd></div>
}

function StatusDialog({ animal, onClose, onDone }: { animal: LivestockAnimalDetail; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [status, setStatus] = useState<AnimalStatus>("Sold")
  const [date, setDate] = useState(todayIso())
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const save = async () => {
    setSaving(true)
    try {
      await setAnimalStatus(animal.animalId, status, date, notes.trim() || null)
      toast({ title: `Tag ${animal.tagNumber} marked ${STATUS_LABEL[status].toLowerCase()}` })
      onDone()
    } catch (e: any) {
      toast({ title: "Not changed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Tag {animal.tagNumber} left the farm</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>What happened</Label>
              <Select value={status} onValueChange={(v) => setStatus(v as AnimalStatus)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Sold">Sold</SelectItem>
                  <SelectItem value="Dead">Died</SelectItem>
                  <SelectItem value="Culled">Culled</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="s-date">Date</Label>
              <Input id="s-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>
          <div>
            <Label htmlFor="s-notes">{status === "Dead" ? "Cause" : "Notes"}</Label>
            <Textarea id="s-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          <p className="text-xs text-stone-500">{animal.groupName} goes down by one.</p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !date} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function MoveDialog({ animal, onClose, onDone }: { animal: LivestockAnimalDetail; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [to, setTo] = useState("")
  const [date, setDate] = useState(todayIso())
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    listGroups().then((gs) => setGroups(gs.filter((g) => g.speciesCode === animal.speciesCode && g.groupId !== animal.groupId)))
      .catch(() => setGroups([]))
  }, [animal.speciesCode, animal.groupId])
  const save = async () => {
    setSaving(true)
    try { await moveAnimal(animal.animalId, Number(to), date); toast({ title: "Moved" }); onDone() }
    catch (e: any) { toast({ title: "Not moved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Move tag {animal.tagNumber}</DialogTitle></DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>To group</Label>
            <Select value={to} onValueChange={setTo}>
              <SelectTrigger><SelectValue placeholder={groups.length ? "Choose" : "No other group"} /></SelectTrigger>
              <SelectContent>{groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div>
            <Label htmlFor="m-date">Date</Label>
            <Input id="m-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !to} onClick={save}>{saving ? "Saving…" : "Move"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

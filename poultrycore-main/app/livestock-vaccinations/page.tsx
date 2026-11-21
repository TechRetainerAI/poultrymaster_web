"use client"

// Vaccinations & Deworming -- what each group is due for, from the plan its
// kind of animal follows, and the plans themselves. The poultry vaccination
// schedule for livestock. Marking a step given saves a health record.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Copy, Pencil, Plus, Syringe, Trash2, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  copyPlan, deletePlan, listDueSteps, listPlans, savePlan, setPlanInUse,
  type DueStep, type PlanStep, type PlanStepKind, type VaccinePlan,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { HealthDialog } from "@/components/livestock/health-dialog"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtAge, fmtDate,
} from "@/components/livestock/livestock-page"

const NONE = "__none"
const STATUS: Record<DueStep["status"], { label: string; cls: string }> = {
  Overdue: { label: "Overdue", cls: "bg-rose-600" },
  DueSoon: { label: "This week", cls: "bg-amber-600" },
  Upcoming: { label: "Coming", cls: "bg-stone-400" },
}

export default function LivestockVaccinationsPage() {
  const { kept } = useLivestockSpecies()
  const { toast } = useToast()
  const [due, setDue] = useState<DueStep[] | null>(null)
  const [plans, setPlans] = useState<VaccinePlan[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [giving, setGiving] = useState<DueStep | null>(null)
  const [editing, setEditing] = useState<VaccinePlan | null>(null)
  const [deleting, setDeleting] = useState<VaccinePlan | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [d, p] = await Promise.all([listDueSteps(60), listPlans()])
      setDue(d); setPlans(p)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  const bySpecies = useMemo(() => kept.map((s) => ({
    species: s,
    plans: (plans ?? []).filter((p) => p.speciesCode === s.speciesCode),
  })), [kept, plans])

  const act = async (fn: () => Promise<unknown>, ok: string) => {
    try { await fn(); toast({ title: ok }); load() }
    catch (e: any) { toast({ title: "Not done", description: e?.message ?? String(e), variant: "destructive" }) }
  }

  return (
    <LivestockPage title="Vaccinations & deworming" description="What each group is due for, and the plans behind it." icon={Syringe}>
      {error ? <LoadError message={error} onRetry={load} /> : !due || !plans ? <Loading /> : (
        <Tabs defaultValue="due">
          <TabsList>
            <TabsTrigger value="due">Due ({due.filter((d) => d.status !== "Upcoming").length})</TabsTrigger>
            <TabsTrigger value="plans">Plans</TabsTrigger>
          </TabsList>

          <TabsContent value="due" className="pt-3 space-y-3">
            <p className="text-sm text-stone-600">
              Dates come from each group's age. Set a group's age on its start date (Edit details) if the animals were not newborn.
            </p>
            {due.length === 0 ? <EmptyState title="Nothing due in the next 60 days" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Due</TableHead><TableHead>Group</TableHead><TableHead>What</TableHead>
                      <TableHead>Age then</TableHead><TableHead>Last given</TableHead><TableHead /><TableHead />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {due.map((d) => (
                      <TableRow key={`${d.groupId}-${d.stepId}`}>
                        <TableCell className="whitespace-nowrap">{fmtDate(d.due)}</TableCell>
                        <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${d.groupId}`}>{d.groupName}</Link></TableCell>
                        <TableCell>{d.name}<div className="text-xs text-stone-500">{[d.method, d.repeatDays && `every ${d.repeatDays} days`].filter(Boolean).join(" · ")}</div></TableCell>
                        <TableCell>{fmtAge(d.ageOnDue)}</TableCell>
                        <TableCell>{d.lastGiven ? fmtDate(d.lastGiven) : "—"}</TableCell>
                        <TableCell><Badge className={STATUS[d.status].cls}>{STATUS[d.status].label}</Badge></TableCell>
                        <TableCell className="text-right"><Button variant="outline" size="sm" onClick={() => setGiving(d)}>Mark given</Button></TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </TabsContent>

          <TabsContent value="plans" className="pt-3 space-y-4">
            {bySpecies.map(({ species, plans: ps }) => {
              const inUse = ps.find((p) => p.inUse)
              return (
                <Card key={species.speciesCode}>
                  <CardHeader className="pb-2 flex-row items-center justify-between gap-3 space-y-0 flex-wrap">
                    <CardTitle className="text-base">{species.name}</CardTitle>
                    <div className="flex items-center gap-2">
                      <span className="text-sm text-stone-600">Groups follow</span>
                      <Select value={inUse ? String(inUse.planId) : NONE}
                        onValueChange={(v) => act(() => setPlanInUse(species.speciesCode, v === NONE ? null : Number(v)), "Plan chosen")}>
                        <SelectTrigger className="w-64"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value={NONE}>No plan</SelectItem>
                          {ps.map((p) => <SelectItem key={p.planId} value={String(p.planId)}>{p.name}</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    {ps.map((p) => (
                      <div key={p.planId} className="rounded-md border p-3">
                        <div className="flex items-center justify-between gap-2 flex-wrap">
                          <div className="font-medium text-stone-900">
                            {p.name}
                            {p.isSuggested && <Badge variant="outline" className="ml-2">Suggested</Badge>}
                            {p.inUse && <Badge className="ml-2 bg-amber-700">In use</Badge>}
                          </div>
                          <div className="flex gap-1">
                            <Button variant="ghost" size="sm" onClick={() => act(() => copyPlan(p.planId), "Copied: you can change your copy")}><Copy className="h-4 w-4 mr-1" />Copy</Button>
                            {!p.isSuggested && <Button variant="ghost" size="sm" onClick={() => setEditing(p)}><Pencil className="h-4 w-4 mr-1" />Edit</Button>}
                            {!p.isSuggested && <Button variant="ghost" size="sm" onClick={() => setDeleting(p)}><Trash2 className="h-4 w-4 text-rose-600" /></Button>}
                          </div>
                        </div>
                        {p.notes && <p className="text-xs text-stone-500 mt-1">{p.notes}</p>}
                        <ul className="mt-2 text-sm text-stone-700 space-y-0.5">
                          {p.steps.map((s) => (
                            <li key={s.stepId}>
                              <span className="text-stone-500 inline-block w-24">Day {s.dayOfAge}</span>
                              {s.name}{s.method ? ` · ${s.method}` : ""}{s.repeatDays ? ` · then every ${s.repeatDays} days` : ""}
                            </li>
                          ))}
                        </ul>
                      </div>
                    ))}
                  </CardContent>
                </Card>
              )
            })}
          </TabsContent>
        </Tabs>
      )}

      <HealthDialog
        open={!!giving}
        onOpenChange={(o) => !o && setGiving(null)}
        title={giving ? `${giving.name}: ${giving.groupName}` : undefined}
        preset={giving ? { groupId: giving.groupId, kind: giving.kind === "Treatment" ? "Treatment" : giving.kind, stepId: giving.stepId, action: giving.name } : undefined}
        onSaved={load}
      />
      {editing && <PlanEditor plan={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title={`Delete ${deleting?.name}?`}
        onConfirm={() => deletePlan(deleting!.planId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </LivestockPage>
  )
}

function PlanEditor({ plan, onClose, onSaved }: { plan: VaccinePlan; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [name, setName] = useState(plan.name)
  const [steps, setSteps] = useState<PlanStep[]>(plan.steps)
  const [saving, setSaving] = useState(false)
  const setStep = (i: number, patch: Partial<PlanStep>) => setSteps((ss) => ss.map((s, j) => (j === i ? { ...s, ...patch } : s)))
  const save = async () => {
    setSaving(true)
    try { await savePlan({ name, notes: plan.notes, steps }, plan.planId); toast({ title: "Plan saved" }); onSaved() }
    catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-3xl">
        <DialogHeader><DialogTitle>Edit plan</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div>
            <Label htmlFor="pl-name">Name</Label>
            <Input id="pl-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="grid grid-cols-[1fr_8rem_6rem_7rem_8rem_auto] gap-2 text-xs font-medium text-stone-500">
            <span>Step</span><span>Kind</span><span>Day of age</span><span>Repeat (days)</span><span>How</span><span />
          </div>
          {steps.map((s, i) => (
            <div key={s.stepId ?? `new-${i}`} className="grid grid-cols-[1fr_8rem_6rem_7rem_8rem_auto] gap-2">
              <Input value={s.name} onChange={(e) => setStep(i, { name: e.target.value })} />
              <Select value={s.kind} onValueChange={(v) => setStep(i, { kind: v as PlanStepKind })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Vaccination">Vaccination</SelectItem>
                  <SelectItem value="Deworming">Deworming</SelectItem>
                  <SelectItem value="Treatment">Treatment</SelectItem>
                </SelectContent>
              </Select>
              <Input type="number" min={0} value={s.dayOfAge} onChange={(e) => setStep(i, { dayOfAge: Number(e.target.value) })} />
              <Input type="number" min={1} value={s.repeatDays ?? ""} placeholder="Once" onChange={(e) => setStep(i, { repeatDays: e.target.value === "" ? null : Number(e.target.value) })} />
              <Input value={s.method ?? ""} onChange={(e) => setStep(i, { method: e.target.value || null })} />
              <Button variant="ghost" size="icon" aria-label="Remove step" onClick={() => setSteps((ss) => ss.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
            </div>
          ))}
          <Button variant="outline" size="sm" onClick={() => setSteps((ss) => [...ss, { name: "", kind: "Vaccination", dayOfAge: 0, repeatDays: null, method: null, notes: null }])}>
            <Plus className="h-4 w-4 mr-1" /> Add step
          </Button>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !name.trim()} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

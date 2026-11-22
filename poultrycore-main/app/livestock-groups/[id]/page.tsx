"use client"

// One animal group: its count and where every change came from (the head
// ledger), its tagged animals, and the jobs done on it -- change the count,
// tag an animal, edit, close or reopen, delete a mistake.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { BarChart3, ClipboardList, Layers, MoreHorizontal, Pencil, Plus, RotateCcw, Tag, Tags, Trash2, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  closeGroup, deleteGroup, getGroup, listAnimals, listBreeding, listProductionRecords, listWithdrawals, reopenGroup, reverseHeadChange,
  type Withdrawal, type BreedingEvent, type HeadMovement, type LivestockAnimal, type LivestockGroupDetail, type ProductionRecord,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { MOVEMENT_LABEL, breedingSummary } from "@/components/livestock/labels"
import { GrowthPanel } from "@/components/livestock/growth-panel"
import { BreedingDialog } from "@/components/livestock/breeding-dialog"
import { GroupFormDialog } from "@/components/livestock/group-form-dialog"
import { HeadChangeDialog } from "@/components/livestock/head-change-dialog"
import { AnimalFormDialog } from "@/components/livestock/animal-form-dialog"
import { TagManyDialog } from "@/components/livestock/tag-many-dialog"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtAge, fmtDate, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"

export default function LivestockGroupPage() {
  const { id } = useParams<{ id: string }>()
  const groupId = Number(id)
  const router = useRouter()
  const { toast } = useToast()
  const { byCode } = useLivestockSpecies()
  const [group, setGroup] = useState<LivestockGroupDetail | null>(null)
  const [animals, setAnimals] = useState<LivestockAnimal[]>([])
  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [breeding, setBreeding] = useState<BreedingEvent[]>([])
  const [withdrawals, setWithdrawals] = useState<Withdrawal[]>([])
  const [error, setError] = useState<string | null>(null)
  const [dialog, setDialog] = useState<null | "edit" | "change" | "tag" | "tagMany" | "close" | "delete" | "breeding">(null)
  const [reversing, setReversing] = useState<HeadMovement | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [g, a, r, b, w] = await Promise.all([
        getGroup(groupId), listAnimals({ groupId, status: "All" }),
        listProductionRecords({ groupId }).catch(() => []), listBreeding({ groupId }).catch(() => []),
        listWithdrawals(groupId).catch(() => []),
      ])
      setGroup(g); setAnimals(a); setRecords(r); setBreeding(b); setWithdrawals(w)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [groupId])
  useEffect(() => { load() }, [load])

  const species = group ? byCode.get(group.speciesCode) : undefined
  const isActive = group?.status === "Active"

  const reopen = async () => {
    try { await reopenGroup(groupId); toast({ title: "Reopened" }); load() }
    catch (e: any) { toast({ title: "Not reopened", description: e?.message, variant: "destructive" }) }
  }

  if (error) return <LivestockPage title="Group" back={{ href: "/livestock-groups", label: "Animal groups" }}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!group) return <LivestockPage title="Group" back={{ href: "/livestock-groups", label: "Animal groups" }}><Loading /></LivestockPage>

  const live = group.movements.filter((m) => !m.reversedAt)
  return (
    <LivestockPage
      title={<>{group.name} {!isActive && <Badge variant="outline" className="ml-2 align-middle">Closed</Badge>}</>}
      description={[group.speciesName, group.penName && `in ${group.penName}`, group.breed, `kept for ${group.purpose.toLowerCase()}`]
        .filter(Boolean).join(" · ")}
      icon={Layers}
      back={{ href: "/livestock-groups", label: "Animal groups" }}
      actions={
        <>
          {isActive && (
            <>
              <Button asChild className={AMBER_BUTTON}>
                <Link href={`/livestock-production-records/new?groupId=${groupId}`}><ClipboardList className="h-4 w-4 mr-1" /> Daily record</Link>
              </Button>
              <Button variant="outline" onClick={() => setDialog("change")}>
                <Plus className="h-4 w-4 mr-1" /> Change count
              </Button>
            </>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild><Button variant="outline" size="icon" aria-label="More"><MoreHorizontal className="h-4 w-4" /></Button></DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem asChild><Link href={`/livestock/reports/group-summary?groupId=${groupId}`}><BarChart3 className="h-4 w-4 mr-2" />Whole-life summary</Link></DropdownMenuItem>
              <DropdownMenuItem onClick={() => setDialog("edit")}><Pencil className="h-4 w-4 mr-2" />Edit details</DropdownMenuItem>
              {isActive && <DropdownMenuItem onClick={() => setDialog("tag")}><Tag className="h-4 w-4 mr-2" />Tag an animal</DropdownMenuItem>}
              {isActive && <DropdownMenuItem onClick={() => setDialog("tagMany")}><Tags className="h-4 w-4 mr-2" />Tag several animals</DropdownMenuItem>}
              {isActive && species?.breedsOnFarm && <DropdownMenuItem onClick={() => setDialog("breeding")}><Plus className="h-4 w-4 mr-2" />Record breeding</DropdownMenuItem>}
              {isActive
                ? <DropdownMenuItem onClick={() => setDialog("close")}><Undo2 className="h-4 w-4 mr-2" />Close group</DropdownMenuItem>
                : <DropdownMenuItem onClick={reopen}><RotateCcw className="h-4 w-4 mr-2" />Reopen group</DropdownMenuItem>}
              <DropdownMenuSeparator />
              <DropdownMenuItem className="text-rose-700" onClick={() => setDialog("delete")}><Trash2 className="h-4 w-4 mr-2" />Delete group</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </>
      }
    >
      {withdrawals.length > 0 && (
        <div className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">
          {withdrawals.map((w) => (
            <div key={w.treatmentId}>
              Do not sell {[w.meatUntil && w.meatUntil >= todayIso() && `meat until ${fmtDate(w.meatUntil)}`,
                w.milkUntil && w.milkUntil >= todayIso() && `milk until ${fmtDate(w.milkUntil)}`,
                w.eggsUntil && w.eggsUntil >= todayIso() && `eggs until ${fmtDate(w.eggsUntil)}`].filter(Boolean).join(", ")}{" "}
              <Link className="underline" href={`/livestock-treatments/${w.treatmentId}`}>({w.itemName})</Link>
            </div>
          ))}
        </div>
      )}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <StatCard label="Animals now" value={fmtNum(group.head)} tone="amber"
          hint={group.penCapacity ? `${group.penName} holds ${group.penCapacity}` : undefined} />
        <StatCard label="Placed" value={fmtNum(group.placed)} hint={group.batchCode ? `From batch ${group.batchCode}` : undefined} />
        <StatCard label="Deaths" value={fmtNum(group.deaths)} tone={group.deaths > 0 ? "rose" : "stone"}
          hint={group.placed > 0 ? `${((group.deaths / group.placed) * 100).toFixed(1)}% of placed` : undefined} />
        <StatCard label="Age of group" value={fmtAge(group.ageDays)} hint={`Started ${fmtDate(group.startDate)}`} />
      </div>

      <Tabs defaultValue="history">
        <TabsList>
          <TabsTrigger value="history">Count history ({live.length})</TabsTrigger>
          <TabsTrigger value="animals">Tagged animals ({group.tagged})</TabsTrigger>
          <TabsTrigger value="records">Daily records ({records.length})</TabsTrigger>
          <TabsTrigger value="growth">Growth</TabsTrigger>
          {species?.breedsOnFarm && <TabsTrigger value="breeding">Breeding ({breeding.length})</TabsTrigger>}
        </TabsList>

        <TabsContent value="history" className="pt-3">
          <div className="rounded-md border bg-white overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>What</TableHead>
                  <TableHead className="text-right">Change</TableHead>
                  <TableHead>Details</TableHead>
                  <TableHead>By</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {group.movements.length === 0 && (
                  <TableRow><TableCell colSpan={6} className="text-center text-stone-500 py-6">Nothing recorded yet.</TableCell></TableRow>
                )}
                {group.movements.map((m) => {
                  const manual = !m.sourceType && !m.animalId && m.type !== "Opening" && m.type !== "Intake"
                  return (
                    <TableRow key={m.movementId} className={m.reversedAt ? "opacity-50" : undefined}>
                      <TableCell className="whitespace-nowrap">{fmtDate(m.date)}</TableCell>
                      <TableCell>
                        {MOVEMENT_LABEL[m.type]}
                        {m.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                      </TableCell>
                      <TableCell className={`text-right font-medium ${m.quantity < 0 ? "text-rose-700" : "text-emerald-700"}`}>
                        {m.quantity > 0 ? `+${m.quantity}` : m.quantity}
                      </TableCell>
                      <TableCell className="text-sm text-stone-600">
                        {m.tagNumber ? (
                          <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${m.animalId}`}>Tag {m.tagNumber}</Link>
                        ) : null}
                        {m.tagNumber && m.notes ? " · " : ""}{m.notes}
                        {m.reverseReason && <div className="text-xs">Reversed: {m.reverseReason}</div>}
                      </TableCell>
                      <TableCell className="text-sm text-stone-500">{m.createdBy ?? "—"}</TableCell>
                      <TableCell className="text-right">
                        {manual && !m.reversedAt && (
                          <Button variant="ghost" size="sm" onClick={() => setReversing(m)}>Reverse</Button>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
        </TabsContent>

        <TabsContent value="animals" className="pt-3 space-y-3">
          {isActive && (
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialog("tag")}><Tag className="h-4 w-4 mr-1" /> Tag an animal</Button>
              <Button variant="outline" onClick={() => setDialog("tagMany")}><Tags className="h-4 w-4 mr-1" /> Tag several</Button>
            </div>
          )}
          {animals.length === 0 ? (
            <EmptyState title="No tagged animals">
              {species?.defaultTracking === "Individual"
                ? `${species.name} are usually tagged one by one. Tag each animal to follow its births, health and sale.`
                : "Tag animals you want to follow one by one, such as breeding stock."}
            </EmptyState>
          ) : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Tag</TableHead><TableHead>Sex</TableHead><TableHead>Age</TableHead>
                    <TableHead>Mother</TableHead><TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {animals.map((a) => (
                    <TableRow key={a.animalId} className="cursor-pointer hover:bg-amber-50/60" onClick={() => router.push(`/livestock-animals/${a.animalId}`)}>
                      <TableCell className="font-medium">{a.tagNumber}{a.name ? ` · ${a.name}` : ""}</TableCell>
                      <TableCell>{a.sex === "Unknown" ? "—" : a.sex}</TableCell>
                      <TableCell>{fmtAge(a.ageDays)}</TableCell>
                      <TableCell>{a.damTag ?? "—"}</TableCell>
                      <TableCell>{a.status === "Active" ? "Alive" : a.status}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </TabsContent>

        <TabsContent value="records" className="pt-3">
          {records.length === 0 ? (
            <EmptyState title="No daily records yet">Record the group's deaths, produce and feed each day.</EmptyState>
          ) : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead><TableHead className="text-right">Animals</TableHead>
                    <TableHead className="text-right">Died</TableHead>
                    {species?.producesEggs && <TableHead className="text-right">Eggs</TableHead>}
                    {species?.producesMilk && <TableHead className="text-right">Milk (L)</TableHead>}
                    <TableHead className="text-right">Feed</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {records.map((r) => (
                    <TableRow key={r.recordId} className="cursor-pointer hover:bg-amber-50/60" onClick={() => router.push(`/livestock-production-records/${r.recordId}`)}>
                      <TableCell>{fmtDate(r.date)}</TableCell>
                      <TableCell className="text-right">{fmtNum(r.headEndOfDay)}</TableCell>
                      <TableCell className="text-right">{fmtNum(r.deaths + r.culls)}</TableCell>
                      {species?.producesEggs && <TableCell className="text-right">{r.eggsCollected ?? "—"}</TableCell>}
                      {species?.producesMilk && <TableCell className="text-right">{r.milkLitres ?? "—"}</TableCell>}
                      <TableCell className="text-right">{r.feedKg != null ? `${fmtNum(r.feedKg)} kg` : "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </TabsContent>

        <TabsContent value="growth" className="pt-3">
          <GrowthPanel groupId={groupId} groupStart={group.startDate} canRecord={isActive} />
        </TabsContent>

        {species?.breedsOnFarm && (
          <TabsContent value="breeding" className="pt-3">
            {breeding.length === 0 ? <EmptyState title="No births or weaning recorded for this group" /> : (
              <ul className="rounded-md border bg-white divide-y text-sm">
                {breeding.map((e) => (
                  <li key={e.eventId} className="px-4 py-2 flex justify-between gap-3">
                    <span>{fmtDate(e.date)} · {breedingSummary(e).what}{e.damTag ? ` · ${e.damTag}` : ""}</span>
                    <span className="text-stone-500">{breedingSummary(e).details}</span>
                  </li>
                ))}
              </ul>
            )}
          </TabsContent>
        )}
      </Tabs>

      <BreedingDialog open={dialog === "breeding"} onOpenChange={(o) => !o && setDialog(null)} preset={{ groupId }} onSaved={load} />
      <GroupFormDialog open={dialog === "edit"} onOpenChange={(o) => !o && setDialog(null)} group={group} onSaved={load} />
      {dialog === "change" && <HeadChangeDialog open onOpenChange={(o) => !o && setDialog(null)} group={group} onSaved={load} />}
      <TagManyDialog open={dialog === "tagMany"} onOpenChange={(o) => !o && setDialog(null)} presetGroupId={groupId} onSaved={load} />
      <AnimalFormDialog open={dialog === "tag"} onOpenChange={(o) => !o && setDialog(null)} presetGroupId={groupId} onSaved={load} />
      <PromptDialog
        open={dialog === "close"}
        onOpenChange={(o) => !o && setDialog(null)}
        title={`Close ${group.name}?`}
        description={group.head > 0
          ? `It still has ${group.head} animal(s). Record where they went first (sold, died, moved).`
          : `Closing keeps its history and takes it off the daily lists. Closing date: ${fmtDate(todayIso())}.`}
        label="Reason (optional)"
        allowEmpty
        confirmLabel="Close group"
        onSubmit={async (reason) => { await closeGroup(groupId, todayIso(), reason || null); setDialog(null); load() }}
      />
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this change?"
        description={reversing ? `${MOVEMENT_LABEL[reversing.type]} of ${Math.abs(reversing.quantity)} on ${fmtDate(reversing.date)}. A move is reversed in both groups.` : undefined}
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseHeadChange(reversing!.movementId, reason); setReversing(null); load() }}
      />
      <ConfirmDeleteDialog
        open={dialog === "delete"}
        onOpenChange={(o) => !o && setDialog(null)}
        title={`Delete ${group.name}?`}
        description="Only a group made by mistake can be deleted: one with nothing recorded on it but its starting animals. Animals from a batch go back to the batch."
        onConfirm={() => deleteGroup(groupId)}
        onSuccess={() => router.push("/livestock-groups")}
      />
    </LivestockPage>
  )
}

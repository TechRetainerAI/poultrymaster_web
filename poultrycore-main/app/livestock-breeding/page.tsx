"use client"

// Breeding & Births -- who is due to give birth, and the breeding history.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Baby, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import {
  deleteBreeding, listBreeding, listBreedingDue,
  type BreedingEvent, type BreedingInput, type DueBreeding,
} from "@/lib/api/livestock"
import { BreedingDialog } from "@/components/livestock/breeding-dialog"
import { breedingSummary } from "@/components/livestock/labels"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate,
} from "@/components/livestock/livestock-page"

export default function LivestockBreedingPage() {
  const [due, setDue] = useState<DueBreeding[] | null>(null)
  const [events, setEvents] = useState<BreedingEvent[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [dialog, setDialog] = useState<{ event?: BreedingEvent; preset?: Partial<BreedingInput> } | null>(null)
  const [deleting, setDeleting] = useState<BreedingEvent | null>(null)
  const duePg = usePagination(due ?? [], 10)
  const eventsPg = usePagination(events ?? [], 10)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [d, e] = await Promise.all([listBreedingDue(), listBreeding()])
      setDue(d); setEvents(e)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage
      title="Breeding & births"
      description="Matings, who is due, births and weaning."
      icon={Baby}
      actions={<Button className={AMBER_BUTTON} onClick={() => setDialog({})}><Plus className="h-4 w-4 mr-1" /> Record breeding</Button>}
    >
      {error ? <LoadError message={error} onRetry={load} /> : !due || !events ? <Loading /> : (
        <Tabs defaultValue="due">
          <TabsList>
            <TabsTrigger value="due">Due to give birth ({due.length})</TabsTrigger>
            <TabsTrigger value="history">History ({events.length})</TabsTrigger>
          </TabsList>

          <TabsContent value="due" className="pt-3">
            {due.length === 0 ? (
              <EmptyState title="Nobody is due">Record a mating and the female appears here until she gives birth.</EmptyState>
            ) : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Female</TableHead><TableHead>Animal</TableHead><TableHead>Mated</TableHead>
                      <TableHead>Male</TableHead><TableHead>Due</TableHead><TableHead>Confirmed</TableHead><TableHead />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {duePg.pageItems.map((d) => (
                      <TableRow key={d.eventId}>
                        <TableCell className="font-medium"><Link className="text-amber-800 hover:underline" href={`/livestock-animals/${d.damId}`}>{d.damTag}</Link></TableCell>
                        <TableCell>{d.speciesName}</TableCell>
                        <TableCell>{fmtDate(d.date)}</TableCell>
                        <TableCell>{d.sireTag ?? "—"}</TableCell>
                        <TableCell className={d.daysToDue != null && d.daysToDue <= 7 ? "text-amber-800 font-medium" : ""}>
                          {fmtDate(d.expectedBirth)}
                          {d.daysToDue != null && <span className="text-xs text-stone-500 ml-1">
                            ({d.daysToDue < 0 ? `${-d.daysToDue} days overdue` : d.daysToDue === 0 ? "today" : `in ${d.daysToDue} days`})
                          </span>}
                        </TableCell>
                        <TableCell>{d.pregnancyConfirmed ? <Badge className="bg-amber-700">Pregnant</Badge> : "Not checked"}</TableCell>
                        <TableCell className="text-right whitespace-nowrap">
                          {!d.pregnancyConfirmed && (
                            <Button variant="ghost" size="sm" onClick={() => setDialog({ preset: { eventType: "PregnancyCheck", damId: d.damId } })}>Check</Button>
                          )}
                          <Button variant="outline" size="sm" onClick={() => setDialog({ preset: { eventType: "Birth", damId: d.damId, sireId: d.sireId } })}>
                            Record {(d.birthTerm ?? "birth").toLowerCase()}
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...duePg.paginationProps} variant="records" />
              </div>
            )}
          </TabsContent>

          <TabsContent value="history" className="pt-3">
            {events.length === 0 ? <EmptyState title="No breeding recorded yet" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Date</TableHead><TableHead>What</TableHead><TableHead>Female</TableHead><TableHead>Details</TableHead><TableHead /></TableRow>
                  </TableHeader>
                  <TableBody>
                    {eventsPg.pageItems.map((e) => (
                      <TableRow key={e.eventId}>
                        <TableCell className="whitespace-nowrap">{fmtDate(e.date)}</TableCell>
                        <TableCell>{breedingSummary(e).what}</TableCell>
                        <TableCell>{e.damId ? <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${e.damId}`}>{e.damTag}</Link> : "—"}</TableCell>
                        <TableCell className="text-sm text-stone-600">{breedingSummary(e).details}</TableCell>
                        <TableCell className="text-right whitespace-nowrap">
                          <Button variant="ghost" size="sm" onClick={() => setDialog({ event: e })}>Edit</Button>
                          <Button variant="ghost" size="sm" className="text-rose-700" onClick={() => setDeleting(e)}>Delete</Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...eventsPg.paginationProps} variant="records" />
              </div>
            )}
          </TabsContent>
        </Tabs>
      )}

      <BreedingDialog open={!!dialog} onOpenChange={(o) => !o && setDialog(null)} event={dialog?.event} preset={dialog?.preset} onSaved={load} />
      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete this breeding record?"
        description={deleting?.eventType === "Birth" ? "The live young it added come back out of the group's count." : undefined}
        onConfirm={() => deleteBreeding(deleting!.eventId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </LivestockPage>
  )
}

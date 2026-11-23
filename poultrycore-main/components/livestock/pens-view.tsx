"use client"

// Setup > Pens: the poultry Houses page for livestock. A pen can be limited
// to one kind of animal, or left open to any. Over capacity is shown, never
// refused (the rule poultry houses ended up with).

import { useCallback, useEffect, useState } from "react"
import { Pencil, Plus, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useToast } from "@/hooks/use-toast"
import { deletePen, listPens, savePen, type LivestockPen, type PenInput } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, EmptyState, LoadError, Loading, fmtNum } from "./livestock-page"

const ANY = "__any"
const blank: PenInput = { name: "", speciesCode: null, capacity: null, location: null, notes: null, isActive: true }

export function PensView() {
  const { toast } = useToast()
  const { kept } = useLivestockSpecies()
  const [pens, setPens] = useState<LivestockPen[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<{ id?: number; input: PenInput } | null>(null)
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState<LivestockPen | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setPens(await listPens()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  const save = async () => {
    if (!editing) return
    setSaving(true)
    try {
      await savePen(editing.input, editing.id)
      toast({ title: editing.id ? "Pen updated" : "Pen added" })
      setEditing(null)
      load()
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const set = <K extends keyof PenInput>(k: K, v: PenInput[K]) =>
    setEditing((e) => (e ? { ...e, input: { ...e.input, [k]: v } } : e))

  const pg = usePagination(pens ?? [], 10)

  if (error) return <LoadError message={error} onRetry={load} />
  if (!pens) return <Loading />

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <p className="text-sm text-stone-600">Pens, hutches, sties, cages and kraals your animals are kept in.</p>
        <Button className={AMBER_BUTTON} onClick={() => setEditing({ input: { ...blank } })}>
          <Plus className="h-4 w-4 mr-1" /> Add pen
        </Button>
      </div>

      {pens.length === 0 ? (
        <EmptyState title="No pens yet">Add the places your animals live so groups can be put in them.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>For</TableHead>
                <TableHead className="text-right">Capacity</TableHead>
                <TableHead className="text-right">Animals now</TableHead>
                <TableHead>Location</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((p) => {
                const over = p.capacity != null && p.head > p.capacity
                return (
                  <TableRow key={p.penId}>
                    <TableCell className="font-medium">
                      {p.name} {!p.isActive && <Badge variant="outline" className="ml-1">Unused</Badge>}
                    </TableCell>
                    <TableCell>{p.speciesName ?? <span className="text-stone-400">Any</span>}</TableCell>
                    <TableCell className="text-right">{fmtNum(p.capacity)}</TableCell>
                    <TableCell className={`text-right ${over ? "text-rose-700 font-medium" : ""}`}>
                      {fmtNum(p.head)}{over && " (over)"}
                    </TableCell>
                    <TableCell>{p.location ?? "—"}</TableCell>
                    <TableCell className="text-right whitespace-nowrap">
                      <Button variant="ghost" size="icon" aria-label={`Edit ${p.name}`}
                        onClick={() => setEditing({ id: p.penId, input: {
                          name: p.name, speciesCode: p.speciesCode, capacity: p.capacity, location: p.location,
                          notes: p.notes, isActive: p.isActive } })}>
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="icon" aria-label={`Delete ${p.name}`} onClick={() => setDeleting(p)}>
                        <Trash2 className="h-4 w-4 text-rose-600" />
                      </Button>
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>{editing?.id ? "Edit pen" : "Add pen"}</DialogTitle></DialogHeader>
          {editing && (
            <div className="space-y-3">
              <div>
                <Label htmlFor="pen-name">Name</Label>
                <Input id="pen-name" value={editing.input.name} onChange={(e) => set("name", e.target.value)} placeholder="Hutch row A" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <Label>For</Label>
                  <Select value={editing.input.speciesCode ?? ANY} onValueChange={(v) => set("speciesCode", v === ANY ? null : v)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={ANY}>Any animal</SelectItem>
                      {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label htmlFor="pen-cap">Capacity (animals)</Label>
                  <Input id="pen-cap" type="number" min={0} inputMode="numeric" value={editing.input.capacity ?? ""}
                    onChange={(e) => set("capacity", e.target.value === "" ? null : Number(e.target.value))} />
                </div>
              </div>
              <div>
                <Label htmlFor="pen-loc">Location</Label>
                <Input id="pen-loc" value={editing.input.location ?? ""} onChange={(e) => set("location", e.target.value || null)} />
              </div>
              <div>
                <Label htmlFor="pen-notes">Notes</Label>
                <Textarea id="pen-notes" rows={2} value={editing.input.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} />
              </div>
              {editing.id && (
                <label className="flex items-center gap-2 text-sm">
                  <Switch checked={editing.input.isActive} onCheckedChange={(v) => set("isActive", v)} /> In use
                </label>
              )}
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditing(null)}>Cancel</Button>
            <Button className={AMBER_BUTTON} disabled={saving || !editing?.input.name.trim()} onClick={save}>
              {saving ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete pen?"
        itemLabel={deleting?.name}
        onConfirm={() => deletePen(deleting!.penId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </div>
  )
}

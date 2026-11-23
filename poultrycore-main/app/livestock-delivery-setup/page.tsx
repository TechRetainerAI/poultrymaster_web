"use client"

// Delivery Setup -- drivers, vehicles and routes (owner/admin changes them).

import { useCallback, useEffect, useState } from "react"
import { Pencil, Plus, Truck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import { listFleet, saveFleet, type FleetItem, type FleetKind } from "@/lib/api/livestock"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading } from "@/components/livestock/livestock-page"

const FIELDS: Record<FleetKind, { key: string; label: string; required?: boolean }[]> = {
  drivers: [{ key: "name", label: "Name", required: true }, { key: "phone", label: "Phone" }, { key: "licence", label: "Licence no." }],
  vehicles: [{ key: "registration", label: "Registration", required: true }, { key: "description", label: "What it is" }, { key: "capacity", label: "Carries" }],
  routes: [{ key: "name", label: "Name", required: true }, { key: "description", label: "Stops" }],
}
const TITLE: Record<FleetKind, string> = { drivers: "driver", vehicles: "vehicle", routes: "route" }

export default function LivestockDeliverySetupPage() {
  const [kind, setKind] = useState<FleetKind>("drivers")
  const [rows, setRows] = useState<FleetItem[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<{ item?: FleetItem } | null>(null)
  const load = useCallback(async () => {
    setError(null); setRows(null)
    try { setRows(await listFleet(kind, true)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [kind])
  useEffect(() => { load() }, [load])
  const pg = usePagination(rows ?? [], 10)

  return (
    <LivestockPage title="Delivery setup" description="Drivers, vehicles and routes." icon={Truck}
      actions={<Button className={AMBER_BUTTON} onClick={() => setEditing({})}><Plus className="h-4 w-4 mr-1" /> Add {TITLE[kind]}</Button>}>
      <Tabs value={kind} onValueChange={(v) => setKind(v as FleetKind)}>
        <TabsList><TabsTrigger value="drivers">Drivers</TabsTrigger><TabsTrigger value="vehicles">Vehicles</TabsTrigger><TabsTrigger value="routes">Routes</TabsTrigger></TabsList>
      </Tabs>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title={`No ${kind} yet`} /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow>{FIELDS[kind].map((f) => <TableHead key={f.key}>{f.label}</TableHead>)}<TableHead /></TableRow></TableHeader>
            <TableBody>
              {pg.pageItems.map((r) => (
                <TableRow key={r.id} className={r.isActive ? "" : "opacity-60"}>
                  {FIELDS[kind].map((f, i) => (
                    <TableCell key={f.key} className={i === 0 ? "font-medium" : ""}>
                      {String((r as unknown as Record<string, unknown>)[f.key] ?? "—")}{i === 0 && !r.isActive && <Badge variant="outline" className="ml-2">Not used</Badge>}
                    </TableCell>
                  ))}
                  <TableCell className="text-right"><Button variant="ghost" size="icon" aria-label="Edit" onClick={() => setEditing({ item: r })}><Pencil className="h-4 w-4" /></Button></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
      {editing && <FleetDialog kind={kind} item={editing.item} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
    </LivestockPage>
  )
}

function FleetDialog({ kind, item, onClose, onSaved }: { kind: FleetKind; item?: FleetItem; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [values, setValues] = useState<Record<string, string>>(() =>
    Object.fromEntries(FIELDS[kind].map((f) => [f.key, String((item as unknown as Record<string, unknown> | undefined)?.[f.key] ?? "")])))
  const [active, setActive] = useState(item?.isActive ?? true)
  const [saving, setSaving] = useState(false)
  const save = async () => {
    setSaving(true)
    try { await saveFleet(kind, { ...values, isActive: active }, item?.id); toast({ title: "Saved" }); onSaved() }
    catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  const required = FIELDS[kind].find((f) => f.required)!
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{item ? `Edit ${TITLE[kind]}` : `Add a ${TITLE[kind]}`}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          {FIELDS[kind].map((f) => (
            <div key={f.key}><Label htmlFor={`fl-${f.key}`}>{f.label}</Label>
              <Input id={`fl-${f.key}`} value={values[f.key]} onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value }))} /></div>
          ))}
          {item && <label className="flex items-center gap-2 text-sm"><Switch checked={active} onCheckedChange={setActive} /> In use</label>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !values[required.key]?.trim()} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

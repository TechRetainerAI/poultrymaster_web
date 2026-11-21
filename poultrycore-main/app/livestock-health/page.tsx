"use client"

// Health Records -- the poultry Health page for livestock: illness, treatment,
// vaccination, deworming and vet visits, with the sick groups still open on top.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { HeartPulse, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { listHealth, type HealthKind, type HealthRecord } from "@/lib/api/livestock"
import { HealthDialog, HEALTH_KIND_LABEL } from "@/components/livestock/health-dialog"
import { deleteHealth } from "@/lib/api/livestock"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum,
} from "@/components/livestock/livestock-page"

const ALL = "__all"

export default function LivestockHealthPage() {
  const [rows, setRows] = useState<HealthRecord[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [kind, setKind] = useState(ALL)
  const [dialog, setDialog] = useState<{ record?: HealthRecord } | null>(null)
  const [deleting, setDeleting] = useState<HealthRecord | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listHealth(kind === ALL ? {} : { kind: kind as HealthKind })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [kind])
  useEffect(() => { load() }, [load])

  const open = (rows ?? []).filter((r) => r.status === "Open")
  const cost = (rows ?? []).reduce((s, r) => s + (r.cost ?? 0), 0)

  return (
    <LivestockPage
      title="Health records"
      description="Sickness, treatment, vaccination, deworming and vet visits."
      icon={HeartPulse}
      actions={<Button className={AMBER_BUTTON} onClick={() => setDialog({})}><Plus className="h-4 w-4 mr-1" /> New health record</Button>}
    >
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="Still sick" value={fmtNum(open.length)} tone={open.length ? "rose" : "stone"}
          hint={open.slice(0, 3).map((r) => r.groupName).join(", ") || undefined} />
        <StatCard label="Records" value={fmtNum(rows?.length ?? 0)} />
        <StatCard label="Medicine used (cost)" value={fmtMoney(cost)} tone="amber" />
      </div>

      <Select value={kind} onValueChange={setKind}>
        <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL}>Everything</SelectItem>
          {(Object.keys(HEALTH_KIND_LABEL) as HealthKind[]).map((k) => <SelectItem key={k} value={k}>{HEALTH_KIND_LABEL[k]}</SelectItem>)}
        </SelectContent>
      </Select>

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title="No health records">Record sickness, treatments and vet visits so each group's health history is in one place.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead><TableHead>Group</TableHead><TableHead>What</TableHead>
                <TableHead>Details</TableHead><TableHead>Medicine</TableHead><TableHead className="text-right">Cost</TableHead><TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {[...open, ...rows.filter((r) => r.status !== "Open")].map((r) => (
                <TableRow key={r.healthId}>
                  <TableCell className="whitespace-nowrap">{fmtDate(r.date)}</TableCell>
                  <TableCell>
                    <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${r.groupId}`}>{r.groupName}</Link>
                    {r.tagNumber && <div className="text-xs"><Link className="hover:underline" href={`/livestock-animals/${r.animalId}`}>Tag {r.tagNumber}</Link></div>}
                  </TableCell>
                  <TableCell>
                    {r.stepName ?? HEALTH_KIND_LABEL[r.kind]}
                    {r.status === "Open" && <Badge className="ml-2 bg-rose-600">Still sick</Badge>}
                  </TableCell>
                  <TableCell className="text-sm text-stone-600 max-w-xs">
                    {[r.affected && `${r.affected} affected`, r.diagnosis, r.signs, r.action].filter(Boolean).join(" · ") || "—"}
                  </TableCell>
                  <TableCell className="text-sm">{r.itemName ? `${r.itemName} · ${fmtNum(r.quantity)} ${r.unit}` : "—"}</TableCell>
                  <TableCell className="text-right">{r.cost ? fmtMoney(r.cost) : "—"}</TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    <Button variant="ghost" size="sm" onClick={() => setDialog({ record: r })}>{r.status === "Open" ? "Update" : "Edit"}</Button>
                    <Button variant="ghost" size="sm" className="text-rose-700" onClick={() => setDeleting(r)}>Delete</Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <HealthDialog open={!!dialog} onOpenChange={(o) => !o && setDialog(null)} record={dialog?.record} onSaved={load} />
      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete this health record?"
        description={deleting?.itemName ? "The medicine it used goes back into stock." : undefined}
        onConfirm={() => deleteHealth(deleting!.healthId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </LivestockPage>
  )
}

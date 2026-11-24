"use client"

import { useEffect, useState } from "react"
import { FolderOpen, Trash2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useToast } from "@/hooks/use-toast"
import { deleteSnapshot, listSnapshots, type SnapshotSummary } from "@/lib/api/egg-cost"

export function SaveSnapshotDialog({ open, mode, defaultName, onOpenChange, onSave }: {
  open: boolean; mode: "Recorded" | "Scenario"; defaultName: string
  onOpenChange: (o: boolean) => void; onSave: (name: string) => Promise<boolean>
}) {
  const [name, setName] = useState(defaultName)
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (open) setName(defaultName) }, [open, defaultName])
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Save {mode === "Scenario" ? "scenario" : "analysis"}</DialogTitle>
          <DialogDescription>
            Keeps the period, selection, settings, {mode === "Scenario" ? "scenario inputs " : ""}and the figures exactly as shown now.
            Saving posts nothing -- no expense, sale, cash or stock movement.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1">
          <Label htmlFor="snap-name">Name</Label>
          <Input id="snap-name" value={name} onChange={(e) => setName(e.target.value)} maxLength={200} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button disabled={saving || !name.trim()} onClick={async () => { setSaving(true); const ok = await onSave(name.trim()); setSaving(false); if (ok) onOpenChange(false) }}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export function OpenSnapshotDialog({ open, onOpenChange, onOpen }: {
  open: boolean; onOpenChange: (o: boolean) => void; onOpen: (s: SnapshotSummary) => void
}) {
  const [rows, setRows] = useState<SnapshotSummary[] | null>(null)
  const { toast } = useToast()
  const load = async () => {
    const r = await listSnapshots()
    if (!r.success) { toast({ title: "Could not load saved analyses", description: r.message, variant: "destructive" }); setRows([]); return }
    setRows(r.data ?? [])
  }
  useEffect(() => { if (open) { setRows(null); void load() } }, [open]) // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Saved analyses</DialogTitle>
          <DialogDescription>Opening one restores its period, selection and scenario, recalculates from today&apos;s records, and shows the saved figures beside them.</DialogDescription>
        </DialogHeader>
        {rows == null ? <p className="text-sm text-slate-500">Loading…</p> : rows.length === 0 ? <p className="text-sm text-slate-500">Nothing saved yet.</p> : (
          <ul className="divide-y divide-slate-100">
            {rows.map((s) => (
              <li key={s.snapshotId} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <div className="min-w-0">
                  <p className="font-medium text-slate-900">{s.name}</p>
                  <p className="text-xs text-slate-500">
                    <Badge variant="outline" className={s.mode === "Scenario" ? "mr-1 border-violet-200 bg-violet-50 text-violet-800" : "mr-1"}>{s.mode}</Badge>
                    {s.params?.startDate} → {s.params?.endDate} · {s.params?.scope?.level ?? "farm"} · saved {s.createdAt.slice(0, 10)} by {s.createdBy ?? "—"} · v{s.calcVersion}
                  </p>
                </div>
                <div className="flex gap-1">
                  <Button size="sm" variant="outline" onClick={() => { onOpen(s); onOpenChange(false) }}><FolderOpen className="mr-1 h-3.5 w-3.5" />Open</Button>
                  <Button size="sm" variant="ghost" title="Delete" onClick={async () => {
                    const r = await deleteSnapshot(s.snapshotId)
                    if (!r.success) { toast({ title: "Not deleted", description: r.message, variant: "destructive" }); return }
                    void load()
                  }}><Trash2 className="h-3.5 w-3.5 text-rose-600" /></Button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  )
}

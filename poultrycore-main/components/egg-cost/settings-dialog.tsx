"use client"

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { useToast } from "@/hooks/use-toast"
import { listEggCostAudit, saveEggCostSettings, type AuditEntry } from "@/lib/api/egg-cost"
import type { CostSettings } from "@/lib/egg-cost/engine"

/** The analyzer's costing assumptions. Owner / admin only; every save is audited and versioned. */
export function CostSettingsDialog({ open, settings, eggsPerCrate, canManage, onOpenChange, onSaved }: {
  open: boolean; settings: CostSettings; eggsPerCrate: number; canManage: boolean
  onOpenChange: (o: boolean) => void; onSaved: () => void
}) {
  const [s, setS] = useState<CostSettings>(settings)
  const [saving, setSaving] = useState(false)
  const [audit, setAudit] = useState<AuditEntry[] | null>(null)
  const [advanced, setAdvanced] = useState(false)
  const { toast } = useToast()
  useEffect(() => { if (open) { setS(settings); setAudit(null) } }, [open, settings])

  const set = <K extends keyof CostSettings>(k: K, v: CostSettings[K]) => setS((p) => ({ ...p, [k]: v }))
  async function save() {
    setSaving(true)
    const r = await saveEggCostSettings(s)
    setSaving(false)
    if (!r.success) { toast({ title: "Settings not saved", description: r.message, variant: "destructive" }); return }
    toast({ title: "Cost settings saved", description: `Version ${r.data?.version ?? ""}. The analysis is recalculated.` })
    onSaved()
  }
  async function loadAudit() {
    const r = await listEggCostAudit()
    setAudit(r.success ? (r.data ?? []).filter((x) => x.kind !== "Snapshot") : [])
  }

  const sw = (k: keyof CostSettings, label: string, help: string) => (
    <div className="flex items-start justify-between gap-3 rounded-md border border-slate-200 p-2.5">
      <div><p className="text-sm font-medium">{label}</p><p className="text-xs text-slate-500">{help}</p></div>
      <Switch checked={!!s[k]} disabled={!canManage} onCheckedChange={(v) => set(k, v as never)} />
    </div>
  )
  const basis = (k: "labourAllocation" | "overheadAllocation", label: string) => (
    <div className="space-y-1">
      <Label className="text-xs">{label}</Label>
      <Select value={s[k]} disabled={!canManage} onValueChange={(v) => set(k, v as CostSettings[typeof k])}>
        <SelectTrigger><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="BirdDays">Bird-days (birds × days, all flocks incl. rearing)</SelectItem>
          <SelectItem value="SaleableEggs">Saleable eggs (laying flocks only)</SelectItem>
        </SelectContent>
      </Select>
    </div>
  )

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[88vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Cost settings</DialogTitle>
          <DialogDescription>
            How shared costs are spread and what counts in the full cost. These change the analysis only -- never your records or P&amp;L.
            {settings.version > 0 ? ` Version ${settings.version}, last changed by ${settings.updatedBy ?? "—"} on ${settings.updatedAt?.slice(0, 10) ?? "—"}.` : " Using the defaults."}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <p className="rounded-md bg-slate-50 px-3 py-2 text-xs text-slate-600">
            Eggs per crate: <strong>{eggsPerCrate}</strong> — from the company&apos;s egg packaging settings, not set here.
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            {basis("labourAllocation", "Shared labour is allocated by")}
            {basis("overheadAllocation", "Shared utilities, overhead and depreciation by")}
          </div>
          {sw("labourInDirect", "Labour is a direct cost", "On: labour counts in the direct cost. Off: only in the full cost.")}
          {sw("includePreLaying", "Include pre-laying cost in the full cost", "Bird cost and rearing costs spread over expected lifetime eggs.")}
          {sw("includeDepreciation", "Include depreciation in the full cost", "Posted depreciation charges -- never the acquisition price.")}
          <button type="button" className="text-xs font-medium text-sky-700 hover:underline" onClick={() => setAdvanced((v) => !v)}>
            {advanced ? "Hide" : "Show"} advanced settings
          </button>
          {advanced && (
            <div className="space-y-3">
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1">
                  <Label className="text-xs">Share of shared overhead that is egg production %</Label>
                  <Input type="number" min={0} max={100} disabled={!canManage} value={s.overheadEggSharePct}
                    onChange={(e) => set("overheadEggSharePct", Math.min(100, Math.max(0, Number(e.target.value))))} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Share of depreciation that is egg production %</Label>
                  <Input type="number" min={0} max={100} disabled={!canManage} value={s.depreciationEggSharePct}
                    onChange={(e) => set("depreciationEggSharePct", Math.min(100, Math.max(0, Number(e.target.value))))} />
                </div>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Feed entered directly as an expense (not through stock)</Label>
                <Select value={s.directFeedExpenses} disabled={!canManage} onValueChange={(v) => set("directFeedExpenses", v as CostSettings["directFeedExpenses"])}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Exclude">Leave out (the feed is also in stock usage)</SelectItem>
                    <SelectItem value="Include">Count it (this feed never went through stock)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Packaging and production supplies</Label>
                <Select value={s.packagingTreatment} disabled={!canManage} onValueChange={(v) => set("packagingTreatment", v as CostSettings["packagingTreatment"])}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="PackagedOnly">Show a separate packaged cost per crate</SelectItem>
                    <SelectItem value="Exclude">Leave out</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Broken-egg sales</Label>
                <Select value={s.byproductTreatment} disabled={!canManage} onValueChange={(v) => set("byproductTreatment", v as CostSettings["byproductTreatment"])}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="None">Revenue only (never reduces cost)</SelectItem>
                    <SelectItem value="DeductBrokenEggSales">Also show a byproduct-adjusted cost</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          )}
          <div className="border-t border-slate-100 pt-2">
            {audit == null ? (
              <button type="button" className="text-xs font-medium text-sky-700 hover:underline" onClick={loadAudit}>Show change history</button>
            ) : audit.length === 0 ? <p className="text-xs text-slate-500">No changes recorded yet.</p> : (
              <ul className="max-h-40 space-y-1 overflow-y-auto text-xs text-slate-600">
                {audit.map((x) => <li key={x.auditId}>{x.changedAt.slice(0, 16).replace("T", " ")} · {x.changedBy ?? "—"} · {x.kind} {x.action}{x.refId ? ` #${x.refId}` : ""}</li>)}
              </ul>
            )}
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>{canManage ? "Cancel" : "Close"}</Button>
          {canManage && <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save settings"}</Button>}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

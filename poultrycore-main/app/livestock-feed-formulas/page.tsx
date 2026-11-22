"use client"

// Feed Formulas -- recipes that turn ingredients into a feed: what one batch
// needs, what it costs at today's prices, and how many batches the stock allows.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { FlaskConical, Pencil, Plus, Trash2, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useToast } from "@/hooks/use-toast"
import { deleteFormula, listFormulas, listItems, saveFormula, type FeedFormula, type FormulaInput, type LivestockItem } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

const ANY = "__any"

export default function LivestockFeedFormulasPage() {
  const [rows, setRows] = useState<FeedFormula[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<{ formula?: FeedFormula } | null>(null)
  const [deleting, setDeleting] = useState<FeedFormula | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listFormulas()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage
      title="Feed formulas"
      description="Recipes for the feed you mix yourself."
      icon={FlaskConical}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-feed-production">Mix feed</Link></Button>
          <Button className={AMBER_BUTTON} onClick={() => setEditing({})}><Plus className="h-4 w-4 mr-1" /> New formula</Button>
        </>
      }
    >
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title="No formulas yet">
          Add your ingredients (maize, soya, premix…) under Feed & stock as kind "Feed ingredient", and the finished feed as kind "Feed". Then write the recipe here.
        </EmptyState>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
          {rows.map((f) => (
            <Card key={f.formulaId} className={f.isActive ? "" : "opacity-60"}>
              <CardHeader className="pb-2 flex-row items-start justify-between space-y-0 gap-2">
                <div>
                  <CardTitle className="text-base">{f.name}{!f.isActive && <Badge variant="outline" className="ml-2">Unused</Badge>}</CardTitle>
                  <p className="text-sm text-stone-500">One batch makes {fmtNum(f.batchQuantity)} {f.outputUnit} of {f.outputItemName}</p>
                </div>
                <div className="flex">
                  <Button variant="ghost" size="icon" aria-label={`Edit ${f.name}`} onClick={() => setEditing({ formula: f })}><Pencil className="h-4 w-4" /></Button>
                  <Button variant="ghost" size="icon" aria-label={`Delete ${f.name}`} onClick={() => setDeleting(f)}><Trash2 className="h-4 w-4 text-rose-600" /></Button>
                </div>
              </CardHeader>
              <CardContent className="text-sm space-y-2">
                <ul className="space-y-0.5">
                  {f.lines.map((l) => (
                    <li key={l.itemId} className="flex justify-between">
                      <span>{l.itemName}</span>
                      <span className={l.stock < l.quantity ? "text-rose-700" : "text-stone-600"}>{fmtNum(l.quantity)} {l.unit}</span>
                    </li>
                  ))}
                </ul>
                <div className="flex justify-between border-t pt-2 text-stone-700">
                  <span>Batch cost today: <strong>{fmtMoney(f.batchCost)}</strong>
                    {f.batchCost != null && f.batchQuantity > 0 && <> ({fmtMoney(f.batchCost / f.batchQuantity)} per {f.outputUnit})</>}</span>
                  <span>Stock allows {fmtNum(f.batchesPossible ?? 0)} batch(es)</span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {editing && <FormulaDialog formula={editing.formula} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title={`Delete ${deleting?.name}?`}
        onConfirm={() => deleteFormula(deleting!.formulaId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </LivestockPage>
  )
}

function FormulaDialog({ formula, onClose, onSaved }: { formula?: FeedFormula; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { kept } = useLivestockSpecies()
  const [items, setItems] = useState<LivestockItem[]>([])
  const [f, setF] = useState<FormulaInput>(formula ? {
    name: formula.name, outputItemId: formula.outputItemId, batchQuantity: formula.batchQuantity, speciesCode: formula.speciesCode,
    notes: formula.notes, isActive: formula.isActive, lines: formula.lines.map((l) => ({ itemId: l.itemId, quantity: l.quantity })),
  } : { name: "", outputItemId: 0, batchQuantity: 0, speciesCode: null, notes: null, lines: [{ itemId: 0, quantity: 0 }] })
  const [saving, setSaving] = useState(false)
  useEffect(() => { listItems().then(setItems).catch(() => setItems([])) }, [])
  const feeds = items.filter((i) => i.category === "Feed")
  const ingredients = items.filter((i) => ["Ingredient", "Feed", "Medication", "Other"].includes(i.category) && i.itemId !== f.outputItemId)
  const out = items.find((i) => i.itemId === f.outputItemId)
  const set = <K extends keyof FormulaInput>(k: K, v: FormulaInput[K]) => setF((s) => ({ ...s, [k]: v }))
  const setLine = (i: number, patch: Partial<{ itemId: number; quantity: number }>) =>
    setF((s) => ({ ...s, lines: s.lines.map((l, j) => (j === i ? { ...l, ...patch } : l)) }))
  const cost = f.lines.reduce((s, l) => s + l.quantity * (items.find((i) => i.itemId === l.itemId)?.avgCost ?? 0), 0)

  const save = async () => {
    setSaving(true)
    try { await saveFormula({ ...f, lines: f.lines.filter((l) => l.itemId) }, formula?.formulaId); toast({ title: "Formula saved" }); onSaved() }
    catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader><DialogTitle>{formula ? `Edit ${formula.name}` : "New feed formula"}</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ff-name">Name</Label><Input id="ff-name" value={f.name} onChange={(e) => set("name", e.target.value)} placeholder="Goat grower mix" /></div>
            <div>
              <Label>For</Label>
              <Select value={f.speciesCode ?? ANY} onValueChange={(v) => set("speciesCode", v === ANY ? null : v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={ANY}>Any animal</SelectItem>
                  {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Makes this feed</Label>
              <Select value={f.outputItemId ? String(f.outputItemId) : ""} onValueChange={(v) => set("outputItemId", Number(v))}>
                <SelectTrigger><SelectValue placeholder={feeds.length ? "Choose" : "Add the feed under Feed & stock"} /></SelectTrigger>
                <SelectContent>{feeds.map((i) => <SelectItem key={i.itemId} value={String(i.itemId)}>{i.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="ff-batch">One batch makes{out ? ` (${out.unit})` : ""}</Label>
              <Input id="ff-batch" type="number" min={0} step="any" value={f.batchQuantity || ""} onChange={(e) => set("batchQuantity", Number(e.target.value))} />
            </div>
          </div>
          <div>
            <Label>Ingredients in one batch</Label>
            <div className="space-y-2 mt-1">
              {f.lines.map((l, i) => {
                const it = items.find((x) => x.itemId === l.itemId)
                return (
                  <div key={i} className="grid grid-cols-[1fr_8rem_auto] gap-2">
                    <Select value={l.itemId ? String(l.itemId) : ""} onValueChange={(v) => setLine(i, { itemId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                      <SelectContent>{ingredients.map((x) => <SelectItem key={x.itemId} value={String(x.itemId)}>{x.name}</SelectItem>)}</SelectContent>
                    </Select>
                    <Input type="number" min={0} step="any" placeholder={it?.unit ?? "Qty"} value={l.quantity || ""} onChange={(e) => setLine(i, { quantity: Number(e.target.value) })} />
                    <Button variant="ghost" size="icon" aria-label="Remove ingredient" disabled={f.lines.length === 1}
                      onClick={() => setF((s) => ({ ...s, lines: s.lines.filter((_, j) => j !== i) }))}><X className="h-4 w-4" /></Button>
                  </div>
                )
              })}
              <Button variant="outline" size="sm" onClick={() => setF((s) => ({ ...s, lines: [...s.lines, { itemId: 0, quantity: 0 }] }))}>
                <Plus className="h-4 w-4 mr-1" /> Add ingredient
              </Button>
            </div>
            {cost > 0 && <p className="text-xs text-stone-500 mt-2">One batch ≈ {fmtMoney(cost)} at today's average costs.</p>}
          </div>
          <div><Label htmlFor="ff-notes">Notes</Label><Textarea id="ff-notes" rows={2} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} /></div>
          {formula && <label className="flex items-center gap-2 text-sm"><Switch checked={f.isActive !== false} onCheckedChange={(v) => set("isActive", v)} /> In use</label>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !f.name.trim() || !f.outputItemId || !(f.batchQuantity > 0)} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

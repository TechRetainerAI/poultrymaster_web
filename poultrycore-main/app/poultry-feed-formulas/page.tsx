"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Loader2, Trash2, FlaskConical, AlertTriangle, CheckCircle2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { listPoultryRawMaterialItems, type PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"
import {
  listFeedFormulas, getFeedFormula, upsertFeedFormula, deleteFeedFormula,
  type FeedFormula, type FeedFormulaQuantityMode,
} from "@/lib/api/poultry-feed-production"

// Feed ingredient vs finished feed classification (mirrors the /feed/i
// convention used by the production-records feed picker).
const isFinishedFeed = (c?: string | null) => !!c && /finish/i.test(c)
const isIngredient = (c?: string | null) => !!c && /feed/i.test(c) && !isFinishedFeed(c)

type LineForm = {
  key: string
  ingredientItemId: number | null
  quantityMode: FeedFormulaQuantityMode
  value: string
  unitOfMeasure: string
  notes: string
}
const newLine = (): LineForm => ({ key: Math.random().toString(36).slice(2), ingredientItemId: null, quantityMode: "Percentage", value: "", unitOfMeasure: "", notes: "" })

type FormState = {
  poultryFeedFormulaId: number | null
  formulaName: string
  finishedFeedItemId: number | null
  defaultOutputUnit: string
  notes: string
  isActive: boolean
  lines: LineForm[]
}
const EMPTY_FORM: FormState = { poultryFeedFormulaId: null, formulaName: "", finishedFeedItemId: null, defaultOutputUnit: "", notes: "", isActive: true, lines: [newLine()] }

export default function PoultryFeedFormulasPage() {
  const { toast } = useToast()
  const canManage = usePermissions().featureAccess.canManageFeedProduction
  const [loading, setLoading] = useState(true)
  const [formulas, setFormulas] = useState<FeedFormula[]>([])
  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [search, setSearch] = useState("")

  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const savingRef = useRef(false)
  const [deleteTarget, setDeleteTarget] = useState<FeedFormula | null>(null)

  const finishedFeedItems = useMemo(() => items.filter((i) => i.isActive && isFinishedFeed(i.category)), [items])
  const ingredientItems = useMemo(() => items.filter((i) => i.isActive && isIngredient(i.category)), [items])

  async function loadAll() {
    setLoading(true)
    try {
      const [f, it] = await Promise.all([listFeedFormulas(), listPoultryRawMaterialItems()])
      setFormulas(f)
      setItems(it)
    } catch (e: any) {
      toast({ title: "Failed to load feed formulas", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void loadAll() }, [])

  const filtered = useMemo(
    () => filterByDateAndSearch(formulas, { search, searchKeys: ["formulaName", "finishedFeedItemName"] }),
    [formulas, search],
  )

  function openNew() {
    setForm(EMPTY_FORM)
    setOpen(true)
  }

  async function openEdit(f: FeedFormula) {
    try {
      const full = await getFeedFormula(f.poultryFeedFormulaId)
      setForm({
        poultryFeedFormulaId: full.poultryFeedFormulaId,
        formulaName: full.formulaName,
        finishedFeedItemId: full.finishedFeedItemId,
        defaultOutputUnit: full.defaultOutputUnit ?? "",
        notes: full.notes ?? "",
        isActive: full.isActive,
        lines: (full.lines ?? []).length
          ? full.lines!.map((l) => ({
              key: Math.random().toString(36).slice(2),
              ingredientItemId: l.ingredientItemId,
              quantityMode: l.quantityMode,
              value: String(l.quantityMode === "Percentage" ? l.percentage ?? "" : l.fixedQuantity ?? ""),
              unitOfMeasure: l.unitOfMeasure ?? "",
              notes: l.notes ?? "",
            }))
          : [newLine()],
      })
      setOpen(true)
    } catch (e: any) {
      toast({ title: "Failed to open formula", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  function setLine(key: string, patch: Partial<LineForm>) {
    setForm((f) => ({ ...f, lines: f.lines.map((l) => (l.key === key ? { ...l, ...patch } : l)) }))
  }
  function pickIngredient(key: string, itemId: number) {
    const item = items.find((i) => i.poultryRawMaterialItemId === itemId)
    setLine(key, { ingredientItemId: itemId, unitOfMeasure: item?.unitOfMeasure ?? "" })
  }
  function addLine() { setForm((f) => ({ ...f, lines: [...f.lines, newLine()] })) }
  function removeLine(key: string) { setForm((f) => ({ ...f, lines: f.lines.length > 1 ? f.lines.filter((l) => l.key !== key) : f.lines })) }

  // Percentage total across percentage lines (fixed-quantity lines don't count).
  const pctTotal = useMemo(
    () => form.lines.filter((l) => l.quantityMode === "Percentage").reduce((s, l) => s + (Number(l.value) || 0), 0),
    [form.lines],
  )
  const hasPercentageLines = form.lines.some((l) => l.quantityMode === "Percentage")
  const pctOk = !hasPercentageLines || Math.abs(pctTotal - 100) < 0.01

  async function save() {
    if (savingRef.current) return
    if (!form.formulaName.trim()) { toast({ title: "Formula name is required", variant: "destructive" }); return }
    if (!form.finishedFeedItemId) { toast({ title: "Pick the finished feed this formula produces", variant: "destructive" }); return }
    const lines = form.lines.filter((l) => l.ingredientItemId && Number(l.value) > 0)
    if (!lines.length) { toast({ title: "Add at least one ingredient line", variant: "destructive" }); return }

    savingRef.current = true
    setSaving(true)
    try {
      await upsertFeedFormula({
        poultryFeedFormulaId: form.poultryFeedFormulaId ?? undefined,
        formulaName: form.formulaName.trim(),
        finishedFeedItemId: form.finishedFeedItemId,
        defaultOutputUnit: form.defaultOutputUnit || null,
        notes: form.notes || null,
        isActive: form.isActive,
        lines: lines.map((l, idx) => ({
          ingredientItemId: l.ingredientItemId!,
          quantityMode: l.quantityMode,
          percentage: l.quantityMode === "Percentage" ? Number(l.value) : null,
          fixedQuantity: l.quantityMode === "FixedQuantity" ? Number(l.value) : null,
          unitOfMeasure: l.unitOfMeasure || null,
          sortOrder: idx,
          notes: l.notes || null,
        })),
      })
      toast({ title: form.poultryFeedFormulaId ? "Formula updated" : "Formula created" })
      setOpen(false)
      await loadAll()
    } catch (e: any) {
      toast({ title: "Failed to save formula", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  async function doDelete() {
    if (!deleteTarget) return
    try {
      await deleteFeedFormula(deleteTarget.poultryFeedFormulaId)
      toast({ title: "Formula deleted" })
      setDeleteTarget(null)
      await loadAll()
    } catch (e: any) {
      toast({ title: "Failed to delete formula", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h1 className="text-2xl font-bold">Feed Formulas</h1>
              <p className="text-sm text-slate-500">Reusable recipes for producing finished feed from ingredients. Used to auto-calculate quantities when producing feed.</p>
            </div>
            {canManage && (
              <div className="self-start sm:ml-auto">
                <Button onClick={openNew} disabled={loading}><Plus className="w-4 h-4 mr-1" /> New Formula</Button>
              </div>
            )}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
          ) : (
            <Card><CardContent className="p-4">
              <div className="mb-3"><ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search formula or feed" /></div>
              <div className="overflow-x-auto">
                <Table className="min-w-[720px]">
                  <TableHeader>
                    <TableRow>
                      <TableHead>Formula</TableHead>
                      <TableHead>Finished Feed</TableHead>
                      <TableHead className="text-center">Ingredients</TableHead>
                      <TableHead className="text-center">% Total</TableHead>
                      <TableHead className="text-center">Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.length === 0 ? (
                      <TableRow><TableCell colSpan={6} className="text-center text-slate-400 py-8">No feed formulas yet. Create one to speed up feed production.</TableCell></TableRow>
                    ) : filtered.map((f) => {
                      const usesPct = (f.percentageTotal ?? 0) > 0
                      const pctGood = !usesPct || Math.abs((f.percentageTotal ?? 0) - 100) < 0.01
                      return (
                        <TableRow key={f.poultryFeedFormulaId}>
                          <TableCell className="font-medium">{f.formulaName}</TableCell>
                          <TableCell>{f.finishedFeedItemName ?? "—"}</TableCell>
                          <TableCell className="text-center tabular-nums">{f.lineCount ?? 0}</TableCell>
                          <TableCell className="text-center tabular-nums">
                            {usesPct ? (
                              <span className={cn("inline-flex items-center gap-1", pctGood ? "text-emerald-700" : "text-amber-700")}>
                                {pctGood ? <CheckCircle2 className="w-3.5 h-3.5" /> : <AlertTriangle className="w-3.5 h-3.5" />}
                                {(f.percentageTotal ?? 0).toLocaleString(undefined, { maximumFractionDigits: 2 })}%
                              </span>
                            ) : <span className="text-slate-400">fixed</span>}
                          </TableCell>
                          <TableCell className="text-center">
                            {f.isActive ? <Badge variant="secondary">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                          </TableCell>
                          <TableCell className="text-right">
                            <div className="flex justify-end gap-1">
                              <Button variant="ghost" size="sm" onClick={() => void openEdit(f)}><Pencil className="w-4 h-4" /></Button>
                              {canManage && <Button variant="ghost" size="sm" onClick={() => setDeleteTarget(f)}><Trash2 className="w-4 h-4 text-red-600" /></Button>}
                            </div>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            </CardContent></Card>
          )}
        </main>
      </div>

      {/* Create / edit formula */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-[820px] max-h-[92vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{form.poultryFeedFormulaId ? "Edit Feed Formula" : "New Feed Formula"}</DialogTitle></DialogHeader>

          <FormSection title="Formula details" color="blue">
            <FormField label="Formula name *"><Input value={form.formulaName} onChange={(e) => setForm({ ...form, formulaName: e.target.value })} placeholder="e.g. Layer Mash Formula" /></FormField>
            <FormField label="Finished feed *" hint="The feed this formula produces">
              <Select value={form.finishedFeedItemId ? String(form.finishedFeedItemId) : ""} onValueChange={(v) => setForm({ ...form, finishedFeedItemId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder={finishedFeedItems.length ? "Pick finished feed" : "No finished-feed items — create one first"} /></SelectTrigger>
                <SelectContent>{finishedFeedItems.map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Default output unit" hint="e.g. kg, bag"><Input value={form.defaultOutputUnit} onChange={(e) => setForm({ ...form, defaultOutputUnit: e.target.value })} /></FormField>
            <FormField label="Active"><div className="pt-1"><Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} /></div></FormField>
            <FormField label="Notes" full><Textarea rows={2} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>

          <FormSection title="Ingredients" color="emerald">
            <div className="sm:col-span-2 space-y-2">
              {form.lines.map((l) => (
                <div key={l.key} className="grid grid-cols-1 sm:grid-cols-12 gap-2 items-end rounded-lg border border-slate-200 p-2.5 bg-white">
                  <div className="sm:col-span-4">
                    <label className="text-xs text-slate-500">Ingredient</label>
                    <Select value={l.ingredientItemId ? String(l.ingredientItemId) : ""} onValueChange={(v) => pickIngredient(l.key, Number(v))}>
                      <SelectTrigger><SelectValue placeholder={ingredientItems.length ? "Pick ingredient" : "No ingredient items"} /></SelectTrigger>
                      <SelectContent>{ingredientItems.map((i) => <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div className="sm:col-span-3">
                    <label className="text-xs text-slate-500">Mode</label>
                    <Select value={l.quantityMode} onValueChange={(v) => setLine(l.key, { quantityMode: v as FeedFormulaQuantityMode })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Percentage">Percentage (%)</SelectItem>
                        <SelectItem value="FixedQuantity">Fixed quantity</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-xs text-slate-500">{l.quantityMode === "Percentage" ? "Percent" : `Qty${l.unitOfMeasure ? ` (${l.unitOfMeasure})` : ""}`}</label>
                    <NumberInput min={0} step={l.quantityMode === "Percentage" ? "0.01" : "0.001"} value={l.value} onChange={(e) => setLine(l.key, { value: e.target.value })} />
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-xs text-slate-500">Notes</label>
                    <Input value={l.notes} onChange={(e) => setLine(l.key, { notes: e.target.value })} />
                  </div>
                  <div className="sm:col-span-1 flex sm:justify-end">
                    <Button variant="ghost" size="sm" onClick={() => removeLine(l.key)} disabled={form.lines.length <= 1}><Trash2 className="w-4 h-4 text-red-600" /></Button>
                  </div>
                </div>
              ))}
              <div className="flex items-center justify-between pt-1">
                <Button variant="outline" size="sm" onClick={addLine}><Plus className="w-4 h-4 mr-1" /> Add ingredient</Button>
                {hasPercentageLines && (
                  <div className={cn("text-sm font-medium inline-flex items-center gap-1.5", pctOk ? "text-emerald-700" : "text-amber-700")}>
                    {pctOk ? <CheckCircle2 className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
                    Percentage total: {pctTotal.toLocaleString(undefined, { maximumFractionDigits: 2 })}%
                    {!pctOk && <span className="text-slate-500 font-normal">(should be 100%)</span>}
                  </div>
                )}
              </div>
            </div>
          </FormSection>

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>Cancel</Button>
            <Button onClick={() => void save()} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Saving…</> : <><FlaskConical className="w-4 h-4 mr-1" /> Save Formula</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
        onConfirm={() => void doDelete()}
        title="Delete feed formula?"
        description={deleteTarget ? `"${deleteTarget.formulaName}" will be permanently removed. This does not affect past production batches.` : ""}
      />
    </div>
  )
}

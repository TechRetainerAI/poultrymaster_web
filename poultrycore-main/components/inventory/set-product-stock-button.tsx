"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { NumberInput } from "@/components/ui/number-input"
import { Input } from "@/components/ui/input"
import { Loader2, ClipboardCheck } from "lucide-react"
import { useToast } from "@/hooks/use-toast"

// Stock-take for FINISHED products. Lists every product with its current stock and
// an editable actual (physical) count; Save writes a correcting Adjust entry for
// each changed row so the displayed stock matches the count. Works all-at-once,
// like the raw-material "Recalculate stock" button. Products with disabledReason
// (e.g. poultry Birds, derived from flocks) are shown read-only.
export function SetProductStockButton({
  products, setStock, onDone, variant = "outline", size, className, label = "Set product stock",
}: {
  products: { id: number; name: string; currentStock: number; disabledReason?: string }[]
  setStock: (productId: number, target: number, note?: string) => Promise<{ currentStock: number }>
  onDone?: () => void | Promise<void>
  variant?: "default" | "outline" | "secondary" | "ghost"
  size?: "default" | "sm" | "lg" | "icon"
  className?: string
  label?: string
}) {
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [counts, setCounts] = useState<Record<number, string>>({})
  const [note, setNote] = useState("")
  const [busy, setBusy] = useState(false)

  function openDialog() {
    const init: Record<number, string> = {}
    products.forEach((p) => { init[p.id] = String(p.currentStock) })
    setCounts(init); setNote(""); setOpen(true)
  }

  const changed = products.filter((p) => !p.disabledReason).filter((p) => {
    const v = Number(counts[p.id])
    return counts[p.id] !== undefined && counts[p.id] !== "" && !Number.isNaN(v) && v !== Number(p.currentStock)
  })

  async function save() {
    if (changed.length === 0) { toast({ title: "No changes to apply" }); return }
    setBusy(true)
    let ok = 0, fail = 0
    for (const p of changed) {
      try { await setStock(p.id, Number(counts[p.id]), note || undefined); ok++ }
      catch { fail++ }
    }
    setBusy(false)
    toast({ title: "Stock updated", description: `${ok} product(s) corrected${fail ? `, ${fail} failed` : ""}.`, variant: fail ? "destructive" : undefined })
    setOpen(false)
    await onDone?.()
  }

  return (
    <>
      <Button variant={variant} size={size} className={className} onClick={openDialog}
        title="Correct finished-product stock to a physical count">
        <ClipboardCheck className="w-4 h-4 mr-1" /> {label}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle>Set product stock to actual counts</DialogTitle></DialogHeader>
          <p className="text-sm text-slate-600">
            Enter each finished product's <span className="font-medium">actual (physical) count</span>.
            We write a correcting stock entry for any that changed, so the displayed stock matches your count.
          </p>
          <div className="max-h-80 overflow-y-auto rounded border">
            <Table>
              <TableHeader><TableRow>
                <TableHead>Product</TableHead>
                <TableHead className="text-right">Current</TableHead>
                <TableHead className="text-right">Actual count</TableHead>
                <TableHead className="text-right">Change</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {products.length === 0 ? (
                  <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-6">No finished products.</TableCell></TableRow>
                ) : products.map((p) => {
                  const v = Number(counts[p.id])
                  const delta = counts[p.id] !== undefined && counts[p.id] !== "" && !Number.isNaN(v) ? v - Number(p.currentStock) : null
                  return (
                    <TableRow key={p.id}>
                      <TableCell className="font-medium">
                        {p.name}
                        {p.disabledReason && <div className="text-[11px] font-normal text-amber-700">{p.disabledReason}</div>}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{Number(p.currentStock).toLocaleString()}</TableCell>
                      <TableCell className="text-right">
                        {p.disabledReason ? <span className="text-slate-400">—</span> : (
                          <NumberInput min={0} step="0.001" value={counts[p.id] ?? ""} onChange={(e) => setCounts((c) => ({ ...c, [p.id]: e.target.value }))} className="w-28 ml-auto text-right" />
                        )}
                      </TableCell>
                      <TableCell className={`text-right tabular-nums ${delta && delta < 0 ? "text-red-600" : delta && delta > 0 ? "text-green-700" : "text-slate-400"}`}>
                        {delta === null || delta === 0 ? "—" : `${delta > 0 ? "+" : ""}${delta.toLocaleString()}`}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <div>
            <label className="text-sm font-medium text-slate-700">Note (optional)</label>
            <Input className="mt-1" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. month-end stock take" />
          </div>
          <div className="flex items-center justify-between pt-1">
            <span className="text-xs text-slate-500">{changed.length} product(s) will be corrected.</span>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={save} disabled={busy || changed.length === 0}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save corrections"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}

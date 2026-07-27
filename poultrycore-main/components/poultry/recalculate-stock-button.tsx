"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, RefreshCw } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  recalculatePoultryRawMaterialStock,
  type PoultryRawMaterialItem, type PoultryRawMaterialRecalcRow,
} from "@/lib/api/poultry-inventory"

// Reusable "Recalculate stock" control for raw materials & supplies.
// Recomputes CurrentQuantity from purchases, usage and adjustments — for every
// item, or a single picked one. Drop it on any Poultry inventory page.
export function RecalculateStockButton({
  items, onDone, variant = "outline", size, className, label = "Recalculate stock",
}: {
  items: PoultryRawMaterialItem[]
  onDone?: () => void | Promise<void>
  variant?: "default" | "outline" | "secondary" | "ghost"
  size?: "default" | "sm" | "lg" | "icon"
  className?: string
  label?: string
}) {
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [target, setTarget] = useState<string>("all")   // "all" or an item id
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<PoultryRawMaterialRecalcRow[] | null>(null)

  const active = items.filter((i) => i.isActive)

  async function run() {
    setBusy(true)
    try {
      const itemId = target === "all" ? undefined : Number(target)
      const rows = await recalculatePoultryRawMaterialStock(itemId)
      const changed = rows.filter((r) => Number(r.delta) !== 0)
      setResult(changed)
      toast({ title: "Stock recalculated", description: `${rows.length} item(s) checked, ${changed.length} updated.` })
      await onDone?.()
    } catch (e: any) { toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <>
      <Button variant={variant} size={size} className={className}
        onClick={() => { setResult(null); setTarget("all"); setOpen(true) }}
        title="Recompute raw-material stock from purchases, usage and adjustments">
        <RefreshCw className="w-4 h-4 mr-1" /> {label}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Recalculate raw-material stock</DialogTitle></DialogHeader>
          {result === null ? (
            <div className="space-y-3">
              <p className="text-sm text-slate-600">
                Recompute stock from history —
                <span className="font-medium"> total purchased (in production units) − used in production + manual adjustments</span>,
                floored at 0. Finished products are not affected.
              </p>
              <div>
                <label className="text-sm font-medium text-slate-700">Item to recalculate</label>
                <Select value={target} onValueChange={setTarget}>
                  <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All raw materials &amp; supplies</SelectItem>
                    {active.map((i) => (
                      <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>
                        {i.itemName}{i.category ? ` — ${i.category}` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                <Button onClick={run} disabled={busy}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Recalculate"}</Button>
              </div>
            </div>
          ) : (
            <div className="space-y-3">
              {result.length === 0 ? (
                <p className="text-sm text-slate-600">Everything already matched — no stock figures needed changing.</p>
              ) : (
                <>
                  <p className="text-sm text-slate-600">{result.length} item(s) updated:</p>
                  <div className="max-h-72 overflow-y-auto rounded border">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Item</TableHead>
                        <TableHead className="text-right">Was</TableHead>
                        <TableHead className="text-right">Now</TableHead>
                        <TableHead className="text-right">Change</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {result.map((r) => (
                          <TableRow key={r.poultryRawMaterialItemId}>
                            <TableCell className="font-medium">{r.itemName}{r.category ? <span className="text-slate-400"> — {r.category}</span> : null}</TableCell>
                            <TableCell className="text-right">{Number(r.oldQuantity).toLocaleString()}</TableCell>
                            <TableCell className="text-right">{Number(r.newQuantity).toLocaleString()}</TableCell>
                            <TableCell className={`text-right ${Number(r.delta) < 0 ? "text-red-600" : "text-green-700"}`}>{Number(r.delta) > 0 ? "+" : ""}{Number(r.delta).toLocaleString()}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </>
              )}
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setResult(null)}>Recalculate again</Button>
                <Button onClick={() => setOpen(false)}>Done</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}

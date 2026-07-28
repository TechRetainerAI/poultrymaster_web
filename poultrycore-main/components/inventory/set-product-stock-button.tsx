"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { NumberInput } from "@/components/ui/number-input"
import { Input } from "@/components/ui/input"
import { Loader2, ClipboardCheck } from "lucide-react"
import { useToast } from "@/hooks/use-toast"

// "Set to actual count" for FINISHED products (Sachet Water, Birds, Eggs…).
// Finished stock is the live sum of its transactions, so you can't edit it
// directly — enter the physical count and this writes a correcting Adjust
// transaction (count − current). The displayed stock then equals the count.
export function SetProductStockButton({
  products, setStock, onDone, variant = "outline", size, className, label = "Set product stock",
}: {
  products: { id: number; name: string; currentStock: number }[]
  setStock: (productId: number, target: number, note?: string) => Promise<{ currentStock: number }>
  onDone?: () => void | Promise<void>
  variant?: "default" | "outline" | "secondary" | "ghost"
  size?: "default" | "sm" | "lg" | "icon"
  className?: string
  label?: string
}) {
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [productId, setProductId] = useState<string>("")
  const [count, setCount] = useState<string>("")
  const [note, setNote] = useState<string>("")
  const [busy, setBusy] = useState(false)

  const selected = products.find((p) => String(p.id) === productId)

  function pick(v: string) {
    setProductId(v)
    const p = products.find((x) => String(x.id) === v)
    setCount(p ? String(p.currentStock) : "")   // prefill with current so the owner edits from there
  }
  function reset() { setProductId(""); setCount(""); setNote("") }

  async function save() {
    if (!selected) { toast({ title: "Pick a product", variant: "destructive" }); return }
    const target = Number(count)
    if (count === "" || Number.isNaN(target) || target < 0) { toast({ title: "Enter a valid count", variant: "destructive" }); return }
    setBusy(true)
    try {
      const r = await setStock(selected.id, target, note || undefined)
      const delta = Number(r.currentStock) - Number(selected.currentStock)
      toast({ title: "Stock corrected", description: `${selected.name} set to ${Number(r.currentStock).toLocaleString()} (${delta >= 0 ? "+" : ""}${delta.toLocaleString()}).` })
      setOpen(false); reset()
      await onDone?.()
    } catch (e: any) { toast({ title: "Update failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  const target = Number(count)
  const delta = selected && count !== "" && !Number.isNaN(target) ? target - Number(selected.currentStock) : null

  return (
    <>
      <Button variant={variant} size={size} className={className}
        onClick={() => { reset(); setOpen(true) }}
        title="Correct a finished product's stock to a physical count">
        <ClipboardCheck className="w-4 h-4 mr-1" /> {label}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Set product stock to actual count</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-slate-600">
              Pick a finished product and enter its <span className="font-medium">actual (physical) count</span>.
              We write a correcting stock entry so the displayed stock matches your count.
            </p>
            <div>
              <label className="text-sm font-medium text-slate-700">Product</label>
              <Select value={productId} onValueChange={pick}>
                <SelectTrigger className="mt-1"><SelectValue placeholder="Pick a finished product…" /></SelectTrigger>
                <SelectContent>
                  {products.map((p) => (
                    <SelectItem key={p.id} value={String(p.id)}>{p.name} — in stock: {Number(p.currentStock).toLocaleString()}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {selected && (
              <>
                <div className="flex items-center gap-3 text-sm">
                  <span className="text-slate-500">Current: <span className="font-medium text-slate-800">{Number(selected.currentStock).toLocaleString()}</span></span>
                  {delta !== null && delta !== 0 && (
                    <span className={delta < 0 ? "text-red-600" : "text-green-700"}>correction {delta > 0 ? "+" : ""}{delta.toLocaleString()}</span>
                  )}
                </div>
                <div>
                  <label className="text-sm font-medium text-slate-700">Actual count</label>
                  <NumberInput className="mt-1" min={0} step="0.001" value={count} onChange={(e) => setCount(e.target.value)} />
                </div>
                <div>
                  <label className="text-sm font-medium text-slate-700">Note (optional)</label>
                  <Input className="mt-1" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. month-end stock take" />
                </div>
              </>
            )}
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={save} disabled={busy || !selected}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save correction"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}

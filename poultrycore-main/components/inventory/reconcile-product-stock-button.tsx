"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, RefreshCw } from "lucide-react"
import { useToast } from "@/hooks/use-toast"

export interface ReconcileRow {
  productId: number
  name?: string | null
  stockIn: number
  stockOut: number
  currentStock: number
}

// "Recalculate product stock" for FINISHED products (Sachet Water, Birds, Eggs…).
// Finished stock is derived from the transaction ledger (not stored), so this
// re-derives it and shows the in/out breakdown that makes up the current stock —
// a reconciliation to verify and diagnose. To CHANGE a finished good, add an
// Adjust entry in New stock entry. Generic: pass a `reconcile` function.
export function ReconcileProductStockButton({
  products, reconcile, onDone, variant = "outline", size, className, label = "Recalculate product stock",
}: {
  products: { id: number; name: string }[]
  reconcile: (productId?: number) => Promise<ReconcileRow[]>
  onDone?: () => void | Promise<void>
  variant?: "default" | "outline" | "secondary" | "ghost"
  size?: "default" | "sm" | "lg" | "icon"
  className?: string
  label?: string
}) {
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [target, setTarget] = useState<string>("all")
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<ReconcileRow[] | null>(null)

  async function run() {
    setBusy(true)
    try {
      const productId = target === "all" ? undefined : Number(target)
      const rows = await reconcile(productId)
      setResult(rows)
      await onDone?.()
    } catch (e: any) { toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <>
      <Button variant={variant} size={size} className={className}
        onClick={() => { setResult(null); setTarget("all"); setOpen(true) }}
        title="Reconcile finished-product stock from its transaction ledger">
        <RefreshCw className="w-4 h-4 mr-1" /> {label}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-xl">
          <DialogHeader><DialogTitle>Recalculate product stock</DialogTitle></DialogHeader>
          {result === null ? (
            <div className="space-y-3">
              <p className="text-sm text-slate-600">
                Finished-product stock is worked out live from its transactions —
                <span className="font-medium"> produced/added in − sold/removed out</span>.
                This re-derives it and shows the breakdown so you can verify a figure.
                To change a finished good, use <span className="font-medium">New stock entry → Adjust</span>.
              </p>
              <div>
                <label className="text-sm font-medium text-slate-700">Product to check</label>
                <Select value={target} onValueChange={setTarget}>
                  <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All finished products</SelectItem>
                    {products.map((p) => <SelectItem key={p.id} value={String(p.id)}>{p.name}</SelectItem>)}
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
                <p className="text-sm text-slate-600">No finished products found.</p>
              ) : (
                <div className="max-h-80 overflow-y-auto rounded border">
                  <Table>
                    <TableHeader><TableRow>
                      <TableHead>Product</TableHead>
                      <TableHead className="text-right">In</TableHead>
                      <TableHead className="text-right">Out</TableHead>
                      <TableHead className="text-right">Current</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {result.map((r) => (
                        <TableRow key={r.productId}>
                          <TableCell className="font-medium">{r.name}</TableCell>
                          <TableCell className="text-right text-green-700">{Number(r.stockIn).toLocaleString()}</TableCell>
                          <TableCell className="text-right text-red-600">{Number(r.stockOut).toLocaleString()}</TableCell>
                          <TableCell className="text-right font-semibold">{Number(r.currentStock).toLocaleString()}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
              <p className="text-[11px] text-slate-400">Current = In − Out. Finished stock is ledger-derived, so this verifies rather than overwrites.</p>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setResult(null)}>Back</Button>
                <Button onClick={() => setOpen(false)}>Done</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}

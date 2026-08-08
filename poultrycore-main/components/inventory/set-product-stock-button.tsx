"use client"

import { useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { NumberInput } from "@/components/ui/number-input"
import { Input } from "@/components/ui/input"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { Loader2, ClipboardCheck, Search, Lock, Info, ArrowUp, ArrowDown, Undo2, X } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"

// Stock-take for FINISHED products. Lists every product with its current stock and
// an editable actual (physical) count; Save writes a correcting Adjust entry for
// each changed row so the displayed stock matches the count. Works all-at-once,
// like the raw-material "Recalculate stock" button. Products with disabledReason
// (e.g. poultry Birds, derived from flocks) are read-only — the reason sits behind
// the lock icon's tooltip rather than crowding every row.

// Hover on desktop, tap on touch (Radix tooltips don't open on tap, so we drive
// `open` ourselves and toggle it from the trigger's click).
function InfoTip({ children, label }: { children: React.ReactNode; label: string }) {
  const [open, setOpen] = useState(false)
  return (
    <Tooltip open={open} onOpenChange={setOpen}>
      <TooltipTrigger asChild>
        <button
          type="button"
          aria-label={label}
          onClick={(e) => { e.preventDefault(); setOpen((o) => !o) }}
          className="inline-flex items-center rounded-full text-slate-400 hover:text-slate-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-300"
        >
          <Info className="h-3.5 w-3.5" />
        </button>
      </TooltipTrigger>
      <TooltipContent side="right" className="max-w-[280px] text-xs leading-relaxed">{children}</TooltipContent>
    </Tooltip>
  )
}

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
  const [progress, setProgress] = useState({ done: 0, total: 0 })
  const [q, setQ] = useState("")

  function openDialog() {
    const init: Record<number, string> = {}
    products.forEach((p) => { init[p.id] = String(p.currentStock) })
    setCounts(init); setNote(""); setQ(""); setProgress({ done: 0, total: 0 }); setOpen(true)
  }

  const deltaOf = (p: { id: number; currentStock: number }) => {
    const raw = counts[p.id]
    if (raw === undefined || raw === "") return null
    const v = Number(raw)
    return Number.isNaN(v) ? null : v - Number(p.currentStock)
  }

  const changed = products.filter((p) => !p.disabledReason).filter((p) => {
    const d = deltaOf(p)
    return d !== null && d !== 0
  })
  const netChange = changed.reduce((s, p) => s + (deltaOf(p) ?? 0), 0)

  const visible = useMemo(() => {
    const term = q.trim().toLowerCase()
    return term ? products.filter((p) => p.name.toLowerCase().includes(term)) : products
  }, [products, q])

  const resetAll = () => {
    const init: Record<number, string> = {}
    products.forEach((p) => { init[p.id] = String(p.currentStock) })
    setCounts(init)
  }

  async function save() {
    if (changed.length === 0) { toast({ title: "No changes to apply" }); return }
    setBusy(true)
    setProgress({ done: 0, total: changed.length })
    let ok = 0, fail = 0
    for (const p of changed) {
      try { await setStock(p.id, Number(counts[p.id]), note || undefined); ok++ }
      catch { fail++ }
      finally { setProgress((s) => ({ ...s, done: s.done + 1 })) }
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

      <Dialog open={open} onOpenChange={(o) => { if (!busy) setOpen(o) }}>
        <DialogContent className="max-w-3xl sm:max-w-3xl p-0 gap-0 overflow-hidden">
          <DialogHeader className="flex-row items-start gap-3 space-y-0 border-b bg-slate-50 p-4 pr-10 text-left">
            <div className="rounded-lg bg-emerald-100 p-2 shrink-0"><ClipboardCheck className="h-5 w-5 text-emerald-700" /></div>
            <div className="min-w-0">
              <DialogTitle className="text-base">Stock take — set product stock</DialogTitle>
              <DialogDescription className="text-sm">
                Enter each product's <span className="font-medium text-slate-700">actual (physical) count</span>. We write a correcting
                stock entry for every row that changed, so the displayed stock matches your count.
              </DialogDescription>
            </div>
          </DialogHeader>

          {/* Middle section scrolls when the viewport is short — header + footer stay put. */}
          <div className="min-h-0 space-y-3 overflow-y-auto p-4">
            {/* Search + running totals */}
            <div className="flex flex-wrap items-center gap-2">
              <div className="relative w-full sm:w-64">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Find a product…" className="pl-9 h-9" value={q} onChange={(e) => setQ(e.target.value)} />
              </div>
              <div className="flex items-center gap-2 sm:ml-auto">
                <span className={cn(
                  "rounded-full px-2.5 py-1 text-xs font-medium",
                  changed.length ? "bg-amber-100 text-amber-800" : "bg-slate-100 text-slate-600",
                )}>
                  {changed.length} change{changed.length === 1 ? "" : "s"}
                </span>
                {changed.length > 0 && (
                  <>
                    <span className={cn(
                      "rounded-full px-2.5 py-1 text-xs font-medium tabular-nums",
                      netChange < 0 ? "bg-rose-100 text-rose-700" : "bg-emerald-100 text-emerald-700",
                    )}>
                      Net {netChange > 0 ? "+" : ""}{netChange.toLocaleString()}
                    </span>
                    <Button variant="ghost" size="sm" className="h-8 text-slate-600" onClick={resetAll} disabled={busy}>
                      <Undo2 className="h-3.5 w-3.5 mr-1" /> Reset
                    </Button>
                  </>
                )}
              </div>
            </div>

            <div className="max-h-[45vh] overflow-y-auto rounded-lg border">
              <Table>
                <TableHeader className="sticky top-0 z-10 bg-slate-50">
                  <TableRow>
                    <TableHead>Product</TableHead>
                    <TableHead className="text-right">Current</TableHead>
                    <TableHead className="text-right">Actual count</TableHead>
                    <TableHead className="text-right">Change</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visible.length === 0 ? (
                    <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-8">
                      {products.length === 0 ? "No finished products." : "No products match your search."}
                    </TableCell></TableRow>
                  ) : visible.map((p) => {
                    const delta = p.disabledReason ? null : deltaOf(p)
                    const dirty = delta !== null && delta !== 0
                    return (
                      <TableRow key={p.id} className={cn(dirty && "bg-amber-50/60", p.disabledReason && "opacity-70")}>
                        <TableCell className="font-medium">
                          <span className="inline-flex items-center gap-1.5">
                            {p.name}
                            {p.disabledReason && (
                              <>
                                <Lock className="h-3.5 w-3.5 text-slate-400" />
                                <InfoTip label={`Why ${p.name} can't be edited`}>{p.disabledReason}</InfoTip>
                              </>
                            )}
                          </span>
                        </TableCell>
                        <TableCell className="text-right tabular-nums text-slate-600">{Number(p.currentStock).toLocaleString()}</TableCell>
                        <TableCell className="text-right">
                          {p.disabledReason ? (
                            <span className="text-xs text-slate-400">Locked</span>
                          ) : (
                            <div className="flex items-center justify-end gap-1">
                              <NumberInput
                                min={0} step="0.001" disabled={busy}
                                value={counts[p.id] ?? ""}
                                onChange={(e) => setCounts((c) => ({ ...c, [p.id]: e.target.value }))}
                                className={cn("w-28 h-9 text-right tabular-nums", dirty && "border-amber-400 bg-white")}
                              />
                              {dirty && (
                                <button
                                  type="button" aria-label={`Reset ${p.name}`} disabled={busy}
                                  onClick={() => setCounts((c) => ({ ...c, [p.id]: String(p.currentStock) }))}
                                  className="rounded p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
                                >
                                  <X className="h-3.5 w-3.5" />
                                </button>
                              )}
                            </div>
                          )}
                        </TableCell>
                        <TableCell className="text-right">
                          {delta === null || delta === 0 ? (
                            <span className="text-slate-400">—</span>
                          ) : (
                            <span className={cn(
                              "inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-xs font-medium tabular-nums",
                              delta < 0 ? "bg-rose-100 text-rose-700" : "bg-emerald-100 text-emerald-700",
                            )}>
                              {delta < 0 ? <ArrowDown className="h-3 w-3" /> : <ArrowUp className="h-3 w-3" />}
                              {delta > 0 ? "+" : ""}{delta.toLocaleString()}
                            </span>
                          )}
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>

            <div>
              <label className="text-sm font-medium text-slate-700">Note (optional)</label>
              <Input className="mt-1" value={note} onChange={(e) => setNote(e.target.value)} disabled={busy} placeholder="e.g. month-end stock take" />
              <p className="mt-1 text-xs text-slate-500">Saved on every correcting entry, so the audit log explains the adjustment.</p>
            </div>
          </div>

          <div className="flex flex-col-reverse gap-2 border-t bg-slate-50 p-4 sm:flex-row sm:items-center sm:justify-between">
            <span className="text-xs text-slate-500">
              {busy && progress.total > 0
                ? `Saving ${progress.done} of ${progress.total}…`
                : changed.length === 0
                  ? "No corrections yet — edit an actual count to begin."
                  : `${changed.length} product(s) will be corrected.`}
            </span>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>Cancel</Button>
              <Button onClick={save} disabled={busy || changed.length === 0}>
                {busy ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> Saving…</> : "Save corrections"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}

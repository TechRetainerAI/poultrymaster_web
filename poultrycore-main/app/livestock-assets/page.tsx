"use client"

// Assets -- buildings, equipment and vehicles: what they cost, what they are
// worth now (written down evenly over their useful life), and selling or
// scrapping one.

import { useCallback, useEffect, useState } from "react"
import { Building2, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { createAsset, disposeAsset, listAssets, reverseAsset, type Asset, type AssetCategory } from "@/lib/api/livestock"
import { AccountSelect, isShort, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const NONE = "__none"
const CATEGORIES: AssetCategory[] = ["Building", "Equipment", "Vehicle", "Land", "Other"]

export default function LivestockAssetsPage() {
  const [rows, setRows] = useState<Asset[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [disposing, setDisposing] = useState<Asset | null>(null)
  const [reversing, setReversing] = useState<Asset | null>(null)
  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listAssets()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])
  const live = (rows ?? []).filter((a) => !a.reversedAt && !a.disposedDate)
  const pg = usePagination(rows ?? [], 10)

  return (
    <LivestockPage title="Assets" description="Buildings, equipment and vehicles, and what they are worth now." icon={Building2}
      actions={<Button className={AMBER_BUTTON} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Add asset</Button>}>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="Worth now" value={fmtMoney(live.reduce((s, a) => s + a.bookValue, 0))} tone="amber" />
        <StatCard label="Cost" value={fmtMoney(live.reduce((s, a) => s + a.cost, 0))} />
        <StatCard label="Wear and tear a month" value={fmtMoney(live.reduce((s, a) => s + a.monthlyDepreciation, 0))} />
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No assets yet" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Asset</TableHead><TableHead>Kind</TableHead><TableHead>Bought</TableHead><TableHead className="text-right">Cost</TableHead><TableHead className="text-right">Worth now</TableHead><TableHead>Life</TableHead><TableHead /></TableRow></TableHeader>
            <TableBody>
              {pg.pageItems.map((a) => (
                <TableRow key={a.assetId} className={a.reversedAt || a.disposedDate ? "opacity-60" : undefined}>
                  <TableCell className="font-medium">{a.name}
                    {a.disposedDate && <div className="text-xs text-stone-500">Sold/scrapped {fmtDate(a.disposedDate)} for {fmtMoney(a.disposalAmount)} ({(a.gainOnDisposal ?? 0) >= 0 ? "gain" : "loss"} {fmtMoney(Math.abs(a.gainOnDisposal ?? 0))})</div>}
                    {a.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                  </TableCell>
                  <TableCell>{a.category}</TableCell>
                  <TableCell>{fmtDate(a.acquiredDate)}</TableCell>
                  <TableCell className="text-right">{fmtMoney(a.cost)}</TableCell>
                  <TableCell className="text-right">{fmtMoney(a.bookValue)}</TableCell>
                  <TableCell>{a.usefulMonths ? `${a.usefulMonths} months` : "Not written down"}</TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    {!a.reversedAt && !a.disposedDate && <Button variant="ghost" size="sm" onClick={() => setDisposing(a)}>Sold / scrapped</Button>}
                    {!a.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(a)}>{a.disposedDate ? "Undo sale" : "Reverse"}</Button>}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
      {adding && <AssetDialog onClose={() => setAdding(false)} onDone={() => { setAdding(false); load() }} />}
      {disposing && <DisposeDialog asset={disposing} onClose={() => setDisposing(null)} onDone={() => { setDisposing(null); load() }} />}
      <PromptDialog open={!!reversing} onOpenChange={(o) => !o && setReversing(null)} title={reversing?.disposedDate ? "Undo the sale?" : "Reverse this asset?"}
        description={reversing?.disposedDate ? "The money from the sale comes back out and the asset is kept." : "The money paid for it goes back into the account."}
        label="Why" confirmLabel="Reverse" confirmVariant="destructive"
        onSubmit={async (r) => { await reverseAsset(reversing!.assetId, r); setReversing(null); load() }} />
    </LivestockPage>
  )
}

function AssetDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const { accounts, defaultId } = useCashAccounts()
  const [f, setF] = useState({ name: "", category: "Equipment" as AssetCategory, date: todayIso(), cost: "", salvage: "", years: "5", paid: true, accountId: null as number | null, notes: "" })
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!f.accountId && defaultId) setF((s) => ({ ...s, accountId: defaultId })) }, [defaultId, f.accountId])
  const cost = Number(f.cost) || 0
  const save = async () => {
    setSaving(true)
    try {
      await createAsset({ name: f.name.trim(), category: f.category, acquiredDate: f.date, cost, salvageValue: Number(f.salvage) || 0,
        usefulMonths: f.category === "Land" ? null : Math.round((Number(f.years) || 0) * 12), accountId: f.paid ? f.accountId : null, notes: f.notes.trim() || null })
      toast({ title: "Asset added" }); onDone()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Add an asset</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="as-name">Name</Label><Input id="as-name" value={f.name} onChange={(e) => setF((s) => ({ ...s, name: e.target.value }))} placeholder="Goat house, water pump" /></div>
            <div>
              <Label>Kind</Label>
              <Select value={f.category} onValueChange={(v) => setF((s) => ({ ...s, category: v as AssetCategory }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><Label htmlFor="as-cost">Cost</Label><Input id="as-cost" type="number" min={0} step="0.01" value={f.cost} onChange={(e) => setF((s) => ({ ...s, cost: e.target.value }))} /></div>
            <div><Label htmlFor="as-date">Bought on</Label><Input id="as-date" type="date" max={todayIso()} value={f.date} onChange={(e) => setF((s) => ({ ...s, date: e.target.value }))} /></div>
            {f.category !== "Land" && <div><Label htmlFor="as-years">Useful for (years)</Label><Input id="as-years" type="number" min={0.5} step="0.5" value={f.years} onChange={(e) => setF((s) => ({ ...s, years: e.target.value }))} /></div>}
          </div>
          {f.category !== "Land" && <div className="w-1/2 pr-1.5"><Label htmlFor="as-salv">Worth at the end</Label><Input id="as-salv" type="number" min={0} step="0.01" value={f.salvage} onChange={(e) => setF((s) => ({ ...s, salvage: e.target.value }))} /></div>}
          <div>
            <Label>Paid for</Label>
            <Select value={f.paid ? "paid" : NONE} onValueChange={(v) => setF((s) => ({ ...s, paid: v === "paid" }))}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value="paid">Paid now from an account</SelectItem><SelectItem value={NONE}>Already owned before I started recording</SelectItem></SelectContent>
            </Select>
          </div>
          {f.paid && <AccountSelect label="Paid from" value={f.accountId} onChange={(v) => setF((s) => ({ ...s, accountId: v }))} accounts={accounts} spend={cost} />}
          <div><Label htmlFor="as-notes">Notes</Label><Textarea id="as-notes" rows={2} value={f.notes} onChange={(e) => setF((s) => ({ ...s, notes: e.target.value }))} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !f.name.trim() || f.cost === "" || (f.paid && (!f.accountId || isShort(accounts, f.accountId, cost)))} onClick={save}>{saving ? "Saving…" : "Add"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function DisposeDialog({ asset, onClose, onDone }: { asset: Asset; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const { accounts, defaultId } = useCashAccounts()
  const [date, setDate] = useState(todayIso())
  const [amount, setAmount] = useState("")
  const [accountId, setAccountId] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!accountId && defaultId) setAccountId(defaultId) }, [defaultId, accountId])
  const n = Number(amount) || 0
  const save = async () => {
    setSaving(true)
    try {
      const r = await disposeAsset(asset.assetId, { date, amount: n, accountId: n > 0 ? accountId : null })
      toast({ title: r.gain >= 0 ? `Gain of ${fmtMoney(r.gain)}` : `Loss of ${fmtMoney(-r.gain)}` }); onDone()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{asset.name} sold or scrapped</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-stone-600">Worth on the books now: <strong>{fmtMoney(asset.bookValue)}</strong></p>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ds-amt">Sold for (0 if scrapped)</Label><Input id="ds-amt" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            <div><Label htmlFor="ds-date">Date</Label><Input id="ds-date" type="date" max={todayIso()} min={asset.acquiredDate} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          {n > 0 && <AccountSelect label="Money went into" value={accountId} onChange={setAccountId} accounts={accounts} />}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || amount === "" || (n > 0 && !accountId)} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

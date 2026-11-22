"use client"

// Cash Accounts -- the cash box, bank and mobile money accounts the farm pays
// from and into, with what each holds now.

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Pencil, Plus, Wallet } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useToast } from "@/hooks/use-toast"
import { listCashAccounts, saveCashAccount, type CashAccount, type CashAccountInput, type CashAccountType } from "@/lib/api/livestock"
import { ACCOUNT_TYPE_LABEL } from "@/components/livestock/labels"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockCashAccountsPage() {
  const router = useRouter()
  const [rows, setRows] = useState<CashAccount[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [showClosed, setShowClosed] = useState(false)
  const [editing, setEditing] = useState<{ account?: CashAccount } | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listCashAccounts(showClosed)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [showClosed])
  useEffect(() => { load() }, [load])

  const total = (rows ?? []).filter((a) => a.isActive).reduce((s, a) => s + a.balance, 0)

  return (
    <LivestockPage
      title="Cash accounts"
      description="Where the farm's money is: cash box, bank, mobile money."
      icon={Wallet}
      actions={<Button className={AMBER_BUTTON} onClick={() => setEditing({})}><Plus className="h-4 w-4 mr-1" /> Add account</Button>}
    >
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="Money in all accounts" value={fmtMoney(total)} tone="amber" />
        <StatCard label="Accounts" value={(rows ?? []).filter((a) => a.isActive).length} />
      </div>
      <label className="flex items-center gap-2 text-sm text-stone-600"><Switch checked={showClosed} onCheckedChange={setShowClosed} /> Show closed accounts</label>

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title="No accounts yet">Add the cash box and any bank or mobile money account you pay from, with what each held when you started.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow><TableHead>Account</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Opening</TableHead><TableHead className="text-right">Now</TableHead><TableHead /></TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((a) => (
                <TableRow key={a.accountId} className={`cursor-pointer hover:bg-amber-50/60 ${a.isActive ? "" : "opacity-60"}`} onClick={() => router.push(`/livestock-cash-accounts/${a.accountId}`)}>
                  <TableCell className="font-medium">
                    {a.name}{a.isDefault && <Badge className="ml-2 bg-amber-700">Default</Badge>}{!a.isActive && <Badge variant="outline" className="ml-2">Closed</Badge>}
                  </TableCell>
                  <TableCell>{ACCOUNT_TYPE_LABEL[a.accountType]}</TableCell>
                  <TableCell className="text-right">{fmtMoney(a.openingBalance)}</TableCell>
                  <TableCell className={`text-right font-medium ${a.balance < 0 ? "text-rose-700" : ""}`}>{fmtMoney(a.balance)}</TableCell>
                  <TableCell className="text-right">
                    <Button variant="ghost" size="icon" aria-label={`Edit ${a.name}`} onClick={(e) => { e.stopPropagation(); setEditing({ account: a }) }}><Pencil className="h-4 w-4" /></Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
      {editing && <AccountDialog account={editing.account} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
    </LivestockPage>
  )
}

function AccountDialog({ account, onClose, onSaved }: { account?: CashAccount; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [f, setF] = useState<CashAccountInput>(account ? {
    name: account.name, accountType: account.accountType, openingBalance: account.openingBalance, openingDate: account.openingDate,
    allowNegative: account.allowNegative, isDefault: account.isDefault, isActive: account.isActive, notes: account.notes,
  } : { name: "", accountType: "Cash", openingBalance: 0, openingDate: todayIso(), allowNegative: false, isDefault: false, notes: null })
  const [saving, setSaving] = useState(false)
  const set = <K extends keyof CashAccountInput>(k: K, v: CashAccountInput[K]) => setF((s) => ({ ...s, [k]: v }))
  const save = async () => {
    setSaving(true)
    try { await saveCashAccount(f, account?.accountId); toast({ title: "Account saved" }); onSaved() }
    catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{account ? `Edit ${account.name}` : "Add an account"}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ca-name">Name</Label><Input id="ca-name" value={f.name} onChange={(e) => set("name", e.target.value)} placeholder="Cash box" /></div>
            <div>
              <Label>Type</Label>
              <Select value={f.accountType} onValueChange={(v) => set("accountType", v as CashAccountType)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{(Object.keys(ACCOUNT_TYPE_LABEL) as CashAccountType[]).map((t) => <SelectItem key={t} value={t}>{ACCOUNT_TYPE_LABEL[t]}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ca-open">Money in it when you started</Label><Input id="ca-open" type="number" step="0.01" value={f.openingBalance} onChange={(e) => set("openingBalance", Number(e.target.value))} /></div>
            <div><Label htmlFor="ca-od">As of</Label><Input id="ca-od" type="date" max={todayIso()} value={f.openingDate} onChange={(e) => set("openingDate", e.target.value)} /></div>
          </div>
          <label className="flex items-center gap-2 text-sm"><Switch checked={f.isDefault} onCheckedChange={(v) => set("isDefault", v)} /> Use this account by default</label>
          <label className="flex items-center gap-2 text-sm"><Switch checked={f.allowNegative} onCheckedChange={(v) => set("allowNegative", v)} /> Allow it to go below zero (an overdraft)</label>
          {account && <label className="flex items-center gap-2 text-sm"><Switch checked={f.isActive !== false} onCheckedChange={(v) => set("isActive", v)} /> Open</label>}
          <div><Label htmlFor="ca-notes">Notes</Label><Textarea id="ca-notes" rows={2} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !f.name.trim()} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

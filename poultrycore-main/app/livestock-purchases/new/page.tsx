"use client"

// Record a purchase: stock (feed, medicine, supplies) and/or animals from a
// supplier, and what was paid at the time. Animals become an intake batch,
// ready to divide into groups.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Plus, ShoppingCart, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import {
  createPurchase, listCashAccounts, listItems,
  EXPENSE_CATEGORIES, type CashAccount, type LivestockItem, type PurchaseInput, type PurchaseLineInput,
} from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { SupplierSelect } from "@/components/livestock/supplier-select"
import { AgeTextInput, BreedSelect } from "@/components/livestock/breed-age-inputs"
import { AMBER_BUTTON, LivestockPage, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

type Row = { kind: "Item" | "Animals" | "Expense"; itemId: number | null; speciesCode: string; quantity: string; unitCost: string; breed: string; age: string; category: string; description: string }
const blankRow = (kind: Row["kind"] = "Item"): Row => ({ kind, itemId: null, speciesCode: "", quantity: kind === "Expense" ? "1" : "", unitCost: "", breed: "", age: "", category: "", description: "" })

export default function NewLivestockPurchasePage() {
  const router = useRouter()
  const { toast } = useToast()
  const { kept } = useLivestockSpecies()
  const [items, setItems] = useState<LivestockItem[]>([])
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [supplierId, setSupplierId] = useState<number | null>(null)
  const [date, setDate] = useState(todayIso())
  const [dueDate, setDueDate] = useState("")
  const [notes, setNotes] = useState("")
  const [rows, setRows] = useState<Row[]>([blankRow()])
  const [payment, setPayment] = useState<"full" | "part" | "none">("full")
  const [paid, setPaid] = useState("")
  const [accountId, setAccountId] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    listItems().then(setItems).catch(() => setItems([]))
    listCashAccounts().then((a) => { setAccounts(a); setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null) }).catch(() => setAccounts([]))
    if (new URLSearchParams(window.location.search).get("animals") === "1") setRows([blankRow("Animals")])
  }, [])

  // No supplier: a cash purchase, paid in full there and then.
  useEffect(() => { if (!supplierId) setPayment("full") }, [supplierId])

  const total = useMemo(() => rows.reduce((s, r) => s + (Number(r.quantity) || 0) * (Number(r.unitCost) || 0), 0), [rows])
  const amountPaid = payment === "full" ? total : payment === "none" ? 0 : Number(paid) || 0
  const account = accounts.find((a) => a.accountId === accountId)
  const short = account && !account.allowNegative && amountPaid > account.balance
  const setRow = (i: number, patch: Partial<Row>) => setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...patch } : r)))

  const save = async () => {
    const lines: PurchaseLineInput[] = rows.filter((r) => r.quantity).map((r) => r.kind === "Item"
      ? { lineType: "Item", itemId: r.itemId as number, quantity: Number(r.quantity), unitCost: Number(r.unitCost) || 0 }
      : r.kind === "Expense"
      ? { lineType: "Expense", expenseCategory: r.category, description: r.description.trim() || null, groupId: null, quantity: Number(r.quantity), unitCost: Number(r.unitCost) || 0 }
      : { lineType: "Animals", speciesCode: r.speciesCode, quantity: Number(r.quantity), unitCost: Number(r.unitCost) || 0, breed: r.breed || null, ageAtIntake: r.age || null })
    const input: PurchaseInput = { supplierId, date, reference: null, dueDate: dueDate || null, notes: notes.trim() || null,
      lines, amountPaid, accountId: amountPaid > 0 ? accountId : null }
    setSaving(true)
    try {
      const r = await createPurchase(input)
      toast({ title: "Purchase recorded" })
      router.push(`/livestock-purchases/${r.purchaseId}`)
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const rowsOk = rows.some((r) => r.quantity) && rows.every((r) => !r.quantity || (r.kind === "Item" ? r.itemId : r.kind === "Expense" ? r.category : r.speciesCode))
  const canSave = rowsOk && date && (payment === "none" || accountId) && (supplierId || amountPaid >= total) && !short

  return (
    <LivestockPage title="New purchase" icon={ShoppingCart} back={{ href: "/livestock-purchases", label: "Purchases" }}>
      <div className="space-y-4">
        <Card>
          <CardContent className="p-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
            <div className="lg:col-span-2"><Label>Supplier</Label><SupplierSelect value={supplierId} onChange={setSupplierId} allowNone /></div>
            <div><Label htmlFor="pu-date">Date</Label><Input id="pu-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label>Invoice no.</Label><div className="h-9 px-3 flex items-center rounded-md border border-dashed bg-stone-50 text-sm text-stone-500">Given automatically (LP-0001…)</div></div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2 flex-row items-center justify-between space-y-0">
            <CardTitle className="text-base">What was bought</CardTitle>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" onClick={() => setRows((rs) => [...rs, blankRow("Item")])}><Plus className="h-4 w-4 mr-1" />Stock</Button>
              <Button variant="outline" size="sm" onClick={() => setRows((rs) => [...rs, blankRow("Animals")])}><Plus className="h-4 w-4 mr-1" />Animals</Button>
              <Button variant="outline" size="sm" onClick={() => setRows((rs) => [...rs, blankRow("Expense")])}><Plus className="h-4 w-4 mr-1" />Service / bill</Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-2">
            {rows.map((r, i) => {
              const it = items.find((x) => x.itemId === r.itemId)
              return (
                <div key={i} className="grid grid-cols-1 sm:grid-cols-[1fr_7rem_8rem_7rem_auto] gap-2 items-start border-b pb-2 last:border-0">
                  {r.kind === "Item" ? (
                    <Select value={r.itemId ? String(r.itemId) : ""} onValueChange={(v) => setRow(i, { itemId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder={items.length ? "Choose an item" : "Add items under Feed & stock"} /></SelectTrigger>
                      <SelectContent>{items.map((x) => <SelectItem key={x.itemId} value={String(x.itemId)}>{x.name} ({x.unit})</SelectItem>)}</SelectContent>
                    </Select>
                  ) : r.kind === "Expense" ? (
                    <div className="grid grid-cols-2 gap-2">
                      <Select value={r.category} onValueChange={(v) => setRow(i, { category: v })}>
                        <SelectTrigger><SelectValue placeholder="For" /></SelectTrigger>
                        <SelectContent>{EXPENSE_CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
                      </Select>
                      <Input placeholder="What exactly" value={r.description} onChange={(e) => setRow(i, { description: e.target.value })} />
                    </div>
                  ) : (
                    <div className="grid grid-cols-2 gap-2">
                      <Select value={r.speciesCode} onValueChange={(v) => setRow(i, { speciesCode: v, breed: "" })}>
                        <SelectTrigger><SelectValue placeholder="Animal" /></SelectTrigger>
                        <SelectContent>{kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}</SelectContent>
                      </Select>
                      <BreedSelect speciesCode={r.speciesCode} value={r.breed || null} onChange={(v) => setRow(i, { breed: v ?? "" })} placeholder="Breed" />
                      <div className="col-span-2">
                        <AgeTextInput key={`${i}-${rows.length}`} value={r.age || null} onChange={(v) => setRow(i, { age: v ?? "" })} />
                        <p className="text-xs text-stone-500 mt-0.5">Age when bought</p>
                      </div>
                    </div>
                  )}
                  <Input type="number" min={0} step={r.kind === "Animals" ? 1 : "any"} placeholder={r.kind === "Animals" ? "Head" : it?.unit ?? "Qty"}
                    value={r.quantity} onChange={(e) => setRow(i, { quantity: e.target.value })} aria-label="Quantity" />
                  <Input type="number" min={0} step="0.01" placeholder={r.kind === "Animals" ? "Price each" : `Price per ${it?.unit ?? "unit"}`}
                    value={r.unitCost} onChange={(e) => setRow(i, { unitCost: e.target.value })} aria-label="Price" />
                  <div className="text-right text-sm pt-2">{fmtMoney((Number(r.quantity) || 0) * (Number(r.unitCost) || 0))}</div>
                  <Button variant="ghost" size="icon" aria-label="Remove line" disabled={rows.length === 1} onClick={() => setRows((rs) => rs.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
                </div>
              )
            })}
            <div className="flex justify-end text-base font-semibold text-stone-900">Total {fmtMoney(total)}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Payment</CardTitle></CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <Label>Paid now</Label>
              <Select value={payment} onValueChange={(v) => setPayment(v as typeof payment)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="full">All of it</SelectItem>
                  {supplierId && <SelectItem value="part">Part of it</SelectItem>}
                  {supplierId && <SelectItem value="none">Nothing yet (on credit)</SelectItem>}
                </SelectContent>
              </Select>
            </div>
            {payment === "part" && (
              <div><Label htmlFor="pu-paid">Amount paid</Label><Input id="pu-paid" type="number" min={0} step="0.01" value={paid} onChange={(e) => setPaid(e.target.value)} /></div>
            )}
            {payment !== "none" && (
              <div>
                <Label>Paid from (cash account)</Label>
                <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
                  <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
                  <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name} · {fmtMoney(a.balance)}</SelectItem>)}</SelectContent>
                </Select>
                {short && <p className="text-xs text-rose-700 mt-1">{account!.name} holds only {fmtMoney(account!.balance)}.</p>}
              </div>
            )}
            {payment !== "full" && (
              <div><Label htmlFor="pu-due">Pay by</Label><Input id="pu-due" type="date" min={date} value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></div>
            )}
            {payment !== "full" && total > 0 && <p className="sm:col-span-3 text-sm text-stone-600">Paying now: <strong className="text-emerald-700">{fmtMoney(amountPaid)}</strong> · Still owed: <strong>{fmtMoney(Math.max(total - amountPaid, 0))}</strong></p>}
            <div className="sm:col-span-3"><Label htmlFor="pu-notes">Notes</Label><Textarea id="pu-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => router.back()}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={save}>{saving ? "Saving…" : (amountPaid > 0 ? `Record purchase · paying ${fmtMoney(amountPaid)} now` : "Record purchase · nothing paid now")}</Button>
        </div>
        {rows.some((r) => r.kind === "Animals" && r.quantity) && (
          <p className="text-xs text-stone-500 text-right">Each line of animals ({fmtNum(rows.filter((r) => r.kind === "Animals").reduce((s, r) => s + (Number(r.quantity) || 0), 0))} head in all) becomes an intake batch; divide it into groups next.</p>
        )}
      </div>
    </LivestockPage>
  )
}

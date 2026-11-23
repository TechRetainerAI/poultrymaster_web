"use client"

// Record a sale: animals from a group, tagged animals one by one, eggs, milk,
// meat or any stock; what was received now, and the rest on credit to a
// customer. Animals under a medicine withdrawal period need a confirmed reason.
// The sale number (LS-0001, ...) is given by the database (473), never typed.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { AlertTriangle, Plus, ShoppingBag, UserRound, Wallet, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  createSale, getSaleOptions, listCashAccounts, LivestockApiError,
  type CashAccount, type SaleInput, type SaleLineInput, type SaleLineType, type SaleOptions,
} from "@/lib/api/livestock"
import { CustomerSelect } from "@/components/livestock/customer-select"
import { AMBER_BUTTON, LivestockPage, fmtDate, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

type Row = { kind: SaleLineType; groupId: number | null; animalId: number | null; itemId: number | null; quantity: string; price: string; weight: string }
const blank = (kind: SaleLineType): Row => ({ kind, groupId: null, animalId: null, itemId: null, quantity: kind === "Tagged" ? "1" : "", price: "", weight: "" })

export default function NewLivestockSalePage() {
  const router = useRouter()
  const { toast } = useToast()
  const [opts, setOpts] = useState<SaleOptions | null>(null)
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [customerId, setCustomerId] = useState<number | null>(null)
  const [date, setDate] = useState(todayIso())
  const [notes, setNotes] = useState("")
  const [rows, setRows] = useState<Row[]>([blank("Tagged")])
  const [payment, setPayment] = useState<"full" | "part" | "none">("full")
  const [received, setReceived] = useState("")
  const [accountId, setAccountId] = useState<number | null>(null)
  const [dueDate, setDueDate] = useState("")
  const [saving, setSaving] = useState(false)
  const [withdrawal, setWithdrawal] = useState<string | null>(null)

  useEffect(() => {
    getSaleOptions().then((o) => {
      setOpts(o)
      // No tagged animals to sell: an untouched first line becomes eggs, milk, stock.
      if (o.animals.length === 0) setRows((rs) => (rs.length === 1 && rs[0].kind === "Tagged" && !rs[0].animalId ? [blank("Product")] : rs))
    }).catch(() => setOpts({ groups: [], animals: [], products: [] }))
    listCashAccounts().then((a) => { setAccounts(a); setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null) }).catch(() => setAccounts([]))
    const p = new URLSearchParams(window.location.search)
    if (p.get("groupId")) setRows([{ ...blank("Animals"), groupId: Number(p.get("groupId")) }])
    if (p.get("animalId")) setRows([{ ...blank("Tagged"), animalId: Number(p.get("animalId")) }])
  }, [])

  const lineTotal = (r: Row) => (r.kind === "Tagged" ? 1 : Number(r.quantity) || 0) * (Number(r.price) || 0)
  const total = useMemo(() => rows.reduce((s, r) => s + lineTotal(r), 0), [rows])
  const amount = payment === "full" ? total : payment === "none" ? 0 : Number(received) || 0
  const setRow = (i: number, patch: Partial<Row>) => setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...patch } : r)))
  const usedAnimals = new Set(rows.filter((r) => r.kind === "Tagged" && r.animalId).map((r) => r.animalId))

  const submit = async (override: string | null) => {
    const lines: SaleLineInput[] = rows.filter((r) => (r.kind === "Tagged" ? r.animalId : r.quantity)).map((r) =>
      r.kind === "Animals" ? { lineType: "Animals", groupId: r.groupId as number, quantity: Number(r.quantity), unitPrice: Number(r.price) || 0, weightKg: r.weight ? Number(r.weight) : null }
      : r.kind === "Tagged" ? { lineType: "Tagged", animalId: r.animalId as number, unitPrice: Number(r.price) || 0, weightKg: r.weight ? Number(r.weight) : null }
      : { lineType: "Product", itemId: r.itemId as number, quantity: Number(r.quantity), unitPrice: Number(r.price) || 0 })
    const input: SaleInput = { customerId, date, reference: null, dueDate: dueDate || null, notes: notes.trim() || null,
      overrideWithdrawal: override, lines, amountReceived: amount, accountId: amount > 0 ? accountId : null }
    setSaving(true)
    try {
      const r = await createSale(input)
      toast({ title: "Sale recorded" })
      router.push(`/livestock-sales/${r.saleId}`)
    } catch (e: any) {
      if (e instanceof LivestockApiError && e.code === "WithdrawalPeriod") setWithdrawal(e.message)
      else toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const rowsOk = rows.some((r) => lineTotal(r) >= 0 && (r.kind === "Tagged" ? r.animalId : r.quantity))
    && rows.every((r) => r.kind === "Tagged" ? (!r.animalId || r.price !== "") : (!r.quantity || ((r.kind === "Animals" ? r.groupId : r.itemId) && r.price !== "")))
  const needsCustomer = !customerId && amount < total
  const overpaid = payment === "part" && amount > total
  const canSave = rowsOk && date && (amount === 0 || accountId) && !needsCustomer && !overpaid

  return (
    <LivestockPage title="New sale" icon={ShoppingBag} back={{ href: "/livestock-sales", label: "Sales" }}>
      <div className="space-y-4">
        <section className="rounded-lg border border-amber-200 bg-amber-50/60 p-4">
          <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-amber-900"><UserRound className="h-4 w-4" />Who bought</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
            <div className="lg:col-span-2"><Label>Customer</Label><CustomerSelect value={customerId} onChange={setCustomerId} allowNone /></div>
            <div><Label htmlFor="sa-date">Date</Label><Input id="sa-date" className="bg-white" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label>Sale no.</Label><div className="h-9 px-3 flex items-center rounded-md border border-dashed border-amber-300 bg-white text-sm text-amber-800">Given automatically (LS-0001…)</div></div>
          </div>
        </section>

        <section className="rounded-lg border border-amber-200 overflow-hidden bg-white">
          <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b border-amber-200">
            <h3 className="flex items-center gap-2 text-sm font-semibold text-amber-900"><ShoppingBag className="h-4 w-4" />What was sold</h3>
            <div className="flex gap-2 flex-wrap">
              <Button variant="outline" size="sm" className="border-amber-300 text-amber-800 hover:bg-amber-50" onClick={() => setRows((rs) => [...rs, blank("Product")])}><Plus className="h-4 w-4 mr-1" />Eggs, milk, stock</Button>
              <Button variant="outline" size="sm" className="border-amber-300 text-amber-800 hover:bg-amber-50" onClick={() => setRows((rs) => [...rs, blank("Animals")])}><Plus className="h-4 w-4 mr-1" />Animals from a group</Button>
              {(opts?.animals.length ?? 0) > 0 && <Button variant="outline" size="sm" className="border-amber-300 text-amber-800 hover:bg-amber-50" onClick={() => setRows((rs) => [...rs, blank("Tagged")])}><Plus className="h-4 w-4 mr-1" />Tagged animal</Button>}
            </div>
          </div>
          <div className="hidden sm:grid grid-cols-[1fr_7rem_7rem_9rem_8rem_2.5rem] gap-2 px-4 py-2 bg-amber-600 text-xs font-semibold text-white">
            <div>Item</div><div>Quantity</div><div>Live weight</div><div>Price</div><div className="text-right">Amount</div><div />
          </div>
          <div className="divide-y divide-amber-100">
            {rows.map((r, i) => {
              const g = opts?.groups.find((x) => x.groupId === r.groupId)
              const pr = opts?.products.find((x) => x.itemId === r.itemId)
              const over = (r.kind === "Animals" && g && Number(r.quantity) > g.untagged) || (r.kind === "Product" && pr && Number(r.quantity) > pr.stock)
              return (
                <div key={i} className="grid grid-cols-1 sm:grid-cols-[1fr_7rem_7rem_9rem_8rem_2.5rem] gap-2 items-start px-4 py-2 odd:bg-white even:bg-amber-50/40">
                  <div>
                    {r.kind === "Product" && (
                      <Select value={r.itemId ? String(r.itemId) : ""} onValueChange={(v) => setRow(i, { itemId: Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="Eggs, milk or stock" /></SelectTrigger>
                        <SelectContent>{opts?.products.map((x) => <SelectItem key={x.itemId} value={String(x.itemId)}>{x.name} · {fmtNum(x.stock)} {x.unit}</SelectItem>)}</SelectContent>
                      </Select>
                    )}
                    {r.kind === "Animals" && (
                      <Select value={r.groupId ? String(r.groupId) : ""} onValueChange={(v) => setRow(i, { groupId: Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="From group" /></SelectTrigger>
                        <SelectContent>{opts?.groups.filter((x) => x.untagged > 0).map((x) => <SelectItem key={x.groupId} value={String(x.groupId)}>{x.name} · {x.untagged} untagged</SelectItem>)}</SelectContent>
                      </Select>
                    )}
                    {r.kind === "Tagged" && (
                      <Select value={r.animalId ? String(r.animalId) : ""} onValueChange={(v) => setRow(i, { animalId: Number(v) })}>
                        <SelectTrigger><SelectValue placeholder="Tag" /></SelectTrigger>
                        <SelectContent>{opts?.animals.filter((a) => a.animalId === r.animalId || !usedAnimals.has(a.animalId)).map((a) =>
                          <SelectItem key={a.animalId} value={String(a.animalId)}>{a.tagNumber} · {a.speciesName}{a.sex !== "Unknown" ? ` ${a.sex.toLowerCase()}` : ""} · {a.groupName}</SelectItem>)}</SelectContent>
                      </Select>
                    )}
                    {g?.meatWithdrawalUntil && g.meatWithdrawalUntil >= date && (
                      <p className="text-xs text-rose-700 mt-1 flex items-center gap-1"><AlertTriangle className="h-3 w-3" />Withdrawal until {fmtDate(g.meatWithdrawalUntil)}</p>
                    )}
                    {over && <p className="text-xs text-rose-700 mt-1">More than there is.</p>}
                  </div>
                  <Input type="number" min={0} step={r.kind === "Product" ? "any" : 1} disabled={r.kind === "Tagged"} placeholder={r.kind === "Product" ? pr?.unit ?? "Qty" : "Head"}
                    value={r.quantity} onChange={(e) => setRow(i, { quantity: e.target.value })} aria-label="Quantity" />
                  {r.kind === "Product" ? <div /> : (
                    <Input type="number" min={0} step="0.1" placeholder="kg (optional)" value={r.weight} onChange={(e) => setRow(i, { weight: e.target.value })} aria-label="Live weight" />
                  )}
                  <Input type="number" min={0} step="0.01" placeholder={r.kind === "Product" ? `Price per ${pr?.unit ?? "unit"}` : "Price each"} value={r.price}
                    onChange={(e) => setRow(i, { price: e.target.value })} aria-label="Price" />
                  <div className="text-right text-sm pt-2 font-medium text-amber-900">{fmtMoney(lineTotal(r))}</div>
                  <Button variant="ghost" size="icon" aria-label="Remove line" disabled={rows.length === 1} onClick={() => setRows((rs) => rs.filter((_, j) => j !== i))}><X className="h-4 w-4 text-rose-600" /></Button>
                </div>
              )
            })}
          </div>
          <div className="flex justify-end px-4 py-3 border-t border-amber-200 bg-amber-50 text-base font-bold text-amber-900">Total {fmtMoney(total)}</div>
        </section>

        <section className="rounded-lg border border-emerald-200 bg-emerald-50/60 p-4">
          <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-emerald-800"><Wallet className="h-4 w-4" />Payment</h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <Label>Received now</Label>
              <Select value={payment} onValueChange={(v) => setPayment(v as typeof payment)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="full">All of it now</SelectItem>
                  <SelectItem value="part">Part now, the rest later</SelectItem>
                  <SelectItem value="none">Nothing now, pay later</SelectItem>
                </SelectContent>
              </Select>
              {needsCustomer && total > 0 && <p className="text-xs text-rose-700 mt-1">Choose the customer at the top: they will owe the rest.</p>}
            </div>
            {payment === "part" && (
              <div>
                <Label htmlFor="sa-recv">Amount received now</Label>
                <Input id="sa-recv" className="bg-white" type="number" min={0} step="0.01" value={received} onChange={(e) => setReceived(e.target.value)} />
                {overpaid && <p className="text-xs text-rose-700 mt-1">More than the sale comes to ({fmtMoney(total)}).</p>}
              </div>
            )}
            {amount > 0 && (
              <div>
                <Label>Into</Label>
                <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
                  <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
                  <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            )}
            {payment !== "full" && <div><Label htmlFor="sa-due">To be paid by</Label><Input id="sa-due" type="date" min={date} value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></div>}
            {payment !== "full" && total > 0 && <p className="sm:col-span-3 text-sm text-stone-600">Receiving now: <strong className="text-emerald-700">{fmtMoney(amount)}</strong> · Customer will owe <strong className="text-rose-700">{fmtMoney(Math.max(total - amount, 0))}</strong></p>}
            <div className="sm:col-span-3"><Label htmlFor="sa-notes">Notes</Label><Textarea id="sa-notes" className="bg-white" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
          </div>
        </section>

        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={() => router.back()}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !canSave} onClick={() => submit(null)}>{saving ? "Saving…" : `Record sale · ${fmtMoney(total)}`}</Button>
        </div>
      </div>

      <PromptDialog
        open={!!withdrawal}
        onOpenChange={(o) => !o && setWithdrawal(null)}
        title="These animals are under a withdrawal period"
        description={<>{withdrawal} Sell anyway only if they are not going for meat (for breeding, for example). Say why; it is kept on the sale.</>}
        label="Why they can be sold"
        confirmLabel="Sell anyway"
        confirmVariant="destructive"
        onSubmit={async (reason) => { setWithdrawal(null); await submit(reason) }}
      />
    </LivestockPage>
  )
}

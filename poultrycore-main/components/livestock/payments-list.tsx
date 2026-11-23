"use client"

// Customer payments / Supplier payments -- every payment received from
// customers or paid to suppliers, like poultry's Customer Payments and Supplier
// Payments pages. One component for both directions: the list with filters,
// paging, "Receive / Pay" (pick who, then the usual payment dialog) and
// reversing a payment made after the sale or purchase. A payment taken with
// the sale or purchase itself is shown, and is undone by reversing that sale
// or purchase.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Plus, Search, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod, type DateRange, type PeriodKey } from "@/lib/date-ranges"
import { usePagination } from "@/hooks/use-pagination"
import {
  listCustomerBalances, listCustomerPayments, listSupplierBalances, listSupplierPayments,
  reverseCustomerPayment, reverseSupplierPayment,
} from "@/lib/api/livestock"
import { ReceivePaymentDialog } from "./receive-payment-dialog"
import { PaySupplierDialog } from "./pay-supplier-dialog"
import { AMBER_BUTTON, EmptyState, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "./livestock-page"

const ALL = "__all"

/** One payment, either direction. */
interface Pay {
  paymentId: number
  partyId: number | null
  partyName: string | null
  date: string
  amount: number
  accountId: number
  accountName: string
  reference: string | null
  notes: string | null
  isUpfront: boolean
  reversedAt: string | null
}
interface Owing { id: number; name: string; owes: number }

const monthStart = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01` }

export function PaymentsList({ direction }: { direction: "customer" | "supplier" }) {
  const isCustomer = direction === "customer"
  const party = isCustomer ? "Customer" : "Supplier"
  const [rows, setRows] = useState<Pay[] | null>(null)
  const [owing, setOwing] = useState<Owing[]>([])
  const [error, setError] = useState<string | null>(null)
  const [from, setFrom] = useState(monthStart())
  const [to, setTo] = useState(todayIso())
  const [search, setSearch] = useState("")
  const [partyF, setPartyF] = useState(ALL)
  const [account, setAccount] = useState(ALL)
  const [how, setHow] = useState<typeof ALL | "upfront" | "later">(ALL)
  const [state, setState] = useState<typeof ALL | "live" | "reversed">("live")
  const [choosing, setChoosing] = useState(false)
  const [chosen, setChosen] = useState<string>("")
  const [paying, setPaying] = useState<Owing | null>(null)
  const [reversing, setReversing] = useState<Pay | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      if (isCustomer) {
        const [p, b] = await Promise.all([listCustomerPayments(), listCustomerBalances()])
        setRows(p.map((x) => ({ ...x, partyId: x.customerId, partyName: x.customerName })))
        setOwing(b.filter((x) => x.owes > 0).map((x) => ({ id: x.customerId, name: x.name, owes: x.owes })))
      } else {
        const [p, b] = await Promise.all([listSupplierPayments(), listSupplierBalances()])
        setRows(p.map((x) => ({ ...x, partyId: x.supplierId, partyName: x.supplierName })))
        setOwing(b.filter((x) => x.owed > 0).map((x) => ({ id: x.supplierId, name: x.name, owes: x.owed })))
      }
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [isCustomer])
  useEffect(() => { load() }, [load])

  const all = rows ?? []
  const parties = useMemo(() => {
    const m = new Map<string, string>()
    for (const p of all) if (p.partyId != null) m.set(String(p.partyId), p.partyName ?? party)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [all, party])
  const accounts = useMemo(() => {
    const m = new Map<string, string>()
    for (const p of all) m.set(String(p.accountId), p.accountName)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [all])

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    return all
      .filter((p) => (!from || p.date.slice(0, 10) >= from) && (!to || p.date.slice(0, 10) <= to))
      .filter((p) => partyF === ALL || String(p.partyId) === partyF)
      .filter((p) => account === ALL || String(p.accountId) === account)
      .filter((p) => how === ALL || (how === "upfront") === p.isUpfront)
      .filter((p) => state === ALL || (state === "reversed") === !!p.reversedAt)
      .filter((p) => !q || [p.partyName, p.reference, p.notes, p.accountName].some((v) => v?.toLowerCase().includes(q)))
      .sort((a, b) => b.date.localeCompare(a.date) || b.paymentId - a.paymentId)
  }, [all, from, to, partyF, account, how, state, search])
  const live = shown.filter((p) => !p.reversedAt)
  const total = live.reduce((s, p) => s + p.amount, 0)
  const upfront = live.filter((p) => p.isUpfront).reduce((s, p) => s + p.amount, 0)
  const owedNow = owing.reduce((s, o) => s + o.owes, 0)
  const pg = usePagination(shown, 10)

  const filtering = !!search || partyF !== ALL || account !== ALL || how !== ALL || state !== "live" || from !== monthStart() || to !== todayIso()
  const clear = () => { setSearch(""); setPartyF(ALL); setAccount(ALL); setHow(ALL); setState("live"); setFrom(monthStart()); setTo(todayIso()) }
  const periodOf = (f: string, t: string): PeriodKey => (!f && !t ? "allTime" : rangeToPeriod(f, t))
  const applyPeriod = (p: PeriodKey, rg: DateRange | null) => {
    if (p === "allTime") { setFrom(""); setTo("") } else if (rg) { setFrom(rg.from); setTo(rg.to) }
  }

  const verb = isCustomer ? "Receive payment" : "Pay a supplier"
  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="grid flex-1 grid-cols-2 lg:grid-cols-4 gap-3">
          <StatCard label={isCustomer ? "Received" : "Paid"} value={fmtMoney(total)} tone={isCustomer ? "emerald" : "rose"} />
          <StatCard label={isCustomer ? "With the sale" : "With the purchase"} value={fmtMoney(upfront)} />
          <StatCard label="Paid later" value={fmtMoney(total - upfront)} />
          <StatCard label={isCustomer ? "Customers still owe" : "You still owe suppliers"} value={fmtMoney(owedNow)} tone={owedNow > 0 ? "amber" : "stone"} />
        </div>
      </div>
      <div className="flex justify-end gap-2">
        <Button asChild variant="outline"><Link href={isCustomer ? "/livestock-customer-balances" : "/livestock-supplier-balances"}>{party} balances</Link></Button>
        <Button className={AMBER_BUTTON} disabled={owing.length === 0} title={owing.length === 0 ? `No ${party.toLowerCase()} is owed anything` : undefined}
          onClick={() => { setChosen(""); setChoosing(true) }}>
          <Plus className="h-4 w-4 mr-1" /> {verb}
        </Button>
      </div>

      <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-white p-2">
        <div className="relative min-w-[180px] flex-[1.4]">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-stone-400" />
          <Input className="pl-9" placeholder={`${party}, reference or note`} value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <PeriodSelect label={null} className="w-40" value={periodOf(from, to)} onChange={applyPeriod} />
        <Input type="date" className="w-[140px]" value={from} max={to || todayIso()} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <Input type="date" className="w-[140px]" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
        <Select value={partyF} onValueChange={setPartyF}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All {party.toLowerCase()}s</SelectItem>
            {parties.map(([id, name]) => <SelectItem key={id} value={id}>{name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={account} onValueChange={setAccount}>
          <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All accounts</SelectItem>
            {accounts.map(([id, name]) => <SelectItem key={id} value={id}>{name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={how} onValueChange={(v) => setHow(v as typeof how)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any time</SelectItem>
            <SelectItem value="upfront">{isCustomer ? "With the sale" : "With the purchase"}</SelectItem>
            <SelectItem value="later">Paid later</SelectItem>
          </SelectContent>
        </Select>
        <Select value={state} onValueChange={(v) => setState(v as typeof state)}>
          <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="live">Not reversed</SelectItem>
            <SelectItem value="reversed">Reversed</SelectItem>
            <SelectItem value={ALL}>All</SelectItem>
          </SelectContent>
        </Select>
        {filtering && <Button variant="ghost" size="sm" className="text-amber-800" onClick={clear}><X className="h-4 w-4 mr-1" />Clear filters</Button>}
        {rows && <span className="ml-auto pr-1 text-sm text-stone-500">{shown.length} payment{shown.length === 1 ? "" : "s"}</span>}
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : shown.length === 0 ? (
        <EmptyState title={filtering ? "No payment matches" : `No payments ${isCustomer ? "received" : "made"} yet`}>
          {filtering ? "Try other filters, or clear them." : undefined}
        </EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead><TableHead>{party}</TableHead><TableHead>{isCustomer ? "Into" : "From"}</TableHead>
                <TableHead>Reference</TableHead><TableHead>When</TableHead><TableHead className="text-right">Amount</TableHead><TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((p) => (
                <TableRow key={p.paymentId} className={p.reversedAt ? "opacity-50" : undefined}>
                  <TableCell className="whitespace-nowrap">{fmtDate(p.date)}</TableCell>
                  <TableCell className="font-medium">{p.partyName ?? <span className="text-stone-400">{isCustomer ? "Walk-in" : "No supplier"}</span>}
                    {p.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                    {p.notes && <div className="text-xs font-normal text-stone-500">{p.notes}</div>}
                  </TableCell>
                  <TableCell>{p.accountName}</TableCell>
                  <TableCell>{p.reference ?? "—"}</TableCell>
                  <TableCell>
                    {p.isUpfront
                      ? <Badge className="bg-stone-100 text-stone-700 hover:bg-stone-100">{isCustomer ? "With the sale" : "With the purchase"}</Badge>
                      : <Badge className="bg-amber-100 text-amber-900 hover:bg-amber-100">Paid later</Badge>}
                  </TableCell>
                  <TableCell className={`text-right font-medium ${isCustomer ? "text-emerald-700" : "text-rose-700"}`}>{fmtMoney(p.amount)}</TableCell>
                  <TableCell className="text-right">
                    {!p.reversedAt && !p.isUpfront && <Button variant="ghost" size="sm" onClick={() => setReversing(p)}>Reverse</Button>}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}

      {/* Who is paying / being paid, then the usual payment dialog. */}
      <Dialog open={choosing} onOpenChange={setChoosing}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>{verb}</DialogTitle></DialogHeader>
          <div>
            <Label>{party}</Label>
            <Select value={chosen} onValueChange={setChosen}>
              <SelectTrigger><SelectValue placeholder={`Choose a ${party.toLowerCase()}`} /></SelectTrigger>
              <SelectContent>
                {owing.map((o) => <SelectItem key={o.id} value={String(o.id)}>{o.name} · {isCustomer ? "owes" : "owed"} {fmtMoney(o.owes)}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setChoosing(false)}>Cancel</Button>
            <Button className={AMBER_BUTTON} disabled={!chosen} onClick={() => { setPaying(owing.find((o) => String(o.id) === chosen) ?? null); setChoosing(false) }}>Continue</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {paying && isCustomer && (
        <ReceivePaymentDialog customerId={paying.id} customerName={paying.name} owes={paying.owes}
          onClose={() => setPaying(null)} onDone={() => { setPaying(null); load() }} />
      )}
      {paying && !isCustomer && (
        <PaySupplierDialog supplierId={paying.id} supplierName={paying.name} owed={paying.owes}
          onClose={() => setPaying(null)} onDone={() => { setPaying(null); load() }} />
      )}

      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this payment?"
        description={reversing ? (isCustomer
          ? `${fmtMoney(reversing.amount)} from ${reversing.partyName} comes back out of ${reversing.accountName}, and is owed again.`
          : `${fmtMoney(reversing.amount)} to ${reversing.partyName} goes back into ${reversing.accountName}, and is owed again.`) : undefined}
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => {
          if (isCustomer) await reverseCustomerPayment(reversing!.paymentId, reason)
          else await reverseSupplierPayment(reversing!.paymentId, reason)
          setReversing(null); load()
        }}
      />
    </>
  )
}

"use client"

// One sale: what was sold, what it came to and cost, the money received, and
// receiving the rest. A sale entered by mistake can be reversed.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams } from "next/navigation"
import { ShoppingBag } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { getSale, reverseSale, type Sale } from "@/lib/api/livestock"
import { PURCHASE_STATUS as STATUS } from "@/components/livestock/labels"
import { ReceivePaymentDialog } from "@/components/livestock/receive-payment-dialog"
import { AMBER_BUTTON, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockSalePage() {
  const { id } = useParams<{ id: string }>()
  const saleId = Number(id)
  const [s, setS] = useState<Sale | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [receiving, setReceiving] = useState(false)
  const [reversing, setReversing] = useState(false)
  const load = useCallback(async () => {
    setError(null)
    try { setS(await getSale(saleId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [saleId])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-sales", label: "Sales" }
  if (error) return <LivestockPage title="Sale" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!s) return <LivestockPage title="Sale" back={back}><Loading /></LivestockPage>

  return (
    <LivestockPage
      title={<>{s.customerName ?? "Walk-in sale"} · {fmtDate(s.date)} <Badge className={`ml-2 align-middle ${STATUS[s.status].cls}`}>{STATUS[s.status].label}</Badge></>}
      description={[s.reference && `Sale no. ${s.reference}`, s.dueDate && `to be paid by ${fmtDate(s.dueDate)}`, s.customerPhone, s.createdBy && `recorded by ${s.createdBy}`].filter(Boolean).join(" · ")}
      icon={ShoppingBag}
      back={back}
      actions={!s.reversedAt ? (
        <>
          {s.owed > 0 && s.customerId && <Button className={AMBER_BUTTON} onClick={() => setReceiving(true)}>Receive {fmtMoney(s.owed)}</Button>}
          <Button variant="outline" className="text-rose-700" onClick={() => setReversing(true)}>Reverse</Button>
        </>
      ) : undefined}
    >
      {s.reversedAt && <div className="rounded-md border border-stone-300 bg-stone-50 p-3 text-sm">Reversed: {s.reverseReason}</div>}
      {s.withdrawalOverride && <div className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">Sold during a withdrawal period: {s.withdrawalOverride}</div>}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <StatCard label="Total" value={fmtMoney(s.total)} tone="amber" />
        <StatCard label="Received" value={fmtMoney(s.paid)} tone="emerald" />
        <StatCard label="Owed" value={fmtMoney(s.owed)} tone={s.overdue ? "rose" : "stone"} hint={s.overdue ? "Overdue" : undefined} />
        {s.cost > 0 && <StatCard label="Stock cost of what was sold" value={fmtMoney(s.cost)} hint={`Margin ${fmtMoney(s.total - s.cost)} on the stock lines`} />}
      </div>
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Sold</CardTitle></CardHeader>
        <CardContent>
          <Table>
            <TableHeader><TableRow><TableHead>What</TableHead><TableHead className="text-right">Quantity</TableHead><TableHead className="text-right">Price each</TableHead><TableHead className="text-right">Total</TableHead></TableRow></TableHeader>
            <TableBody>
              {s.lines.map((l) => (
                <TableRow key={l.lineId}>
                  <TableCell>
                    {l.lineType === "Product" && <Link className="text-amber-800 hover:underline" href={`/livestock-items/${l.itemId}`}>{l.itemName}</Link>}
                    {l.lineType === "Animals" && <>{l.speciesName} from <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${l.groupId}`}>{l.groupName}</Link></>}
                    {l.lineType === "Tagged" && <>{l.speciesName} <Link className="text-amber-800 hover:underline" href={`/livestock-animals/${l.animalId}`}>tag {l.tagNumber}</Link></>}
                    {l.weightKg != null && <span className="text-xs text-stone-500"> · {fmtNum(l.weightKg)} kg live</span>}
                  </TableCell>
                  <TableCell className="text-right">{fmtNum(l.quantity)} {l.lineType === "Product" ? l.unit : "head"}</TableCell>
                  <TableCell className="text-right">{fmtMoney(l.unitPrice)}</TableCell>
                  <TableCell className="text-right">{fmtMoney(l.lineTotal)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Money received</CardTitle></CardHeader>
        <CardContent className="text-sm">
          {s.payments.length === 0 ? <p className="text-stone-500">Nothing received yet.</p> : (
            <ul className="divide-y">
              {s.payments.map((p) => (
                <li key={p.paymentId} className={`py-2 flex justify-between ${p.reversedAt ? "opacity-50" : ""}`}>
                  <span>{fmtDate(p.date)} · {p.accountName}{p.isUpfront ? " · with the sale" : ""}{p.reversedAt ? " (reversed)" : ""}</span>
                  <span className="font-medium">{fmtMoney(p.amount)}</span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
      {s.notes && <Card><CardContent className="p-4 text-sm whitespace-pre-wrap">{s.notes}</CardContent></Card>}
      {receiving && s.customerId && <ReceivePaymentDialog customerId={s.customerId} customerName={s.customerName ?? "customer"} owes={s.owed} saleId={s.saleId} onClose={() => setReceiving(false)} onDone={() => { setReceiving(false); load() }} />}
      <PromptDialog
        open={reversing}
        onOpenChange={setReversing}
        title="Reverse this sale?"
        description="Its animals go back into their groups (tagged ones back to alive), its stock back into stock, and money received with it comes back out of the account."
        label="Why"
        confirmLabel="Reverse sale"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseSale(saleId, reason); setReversing(false); load() }}
      />
    </LivestockPage>
  )
}

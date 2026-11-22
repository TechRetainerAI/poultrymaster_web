"use client"

// One purchase: what was bought, what it came to, the payments against it,
// and paying the rest. A purchase entered by mistake can be reversed while
// its stock is unused and its animals are not yet in groups.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams } from "next/navigation"
import { ShoppingCart } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { getPurchase, reversePurchase, type Purchase } from "@/lib/api/livestock"
import { PURCHASE_STATUS } from "@/components/livestock/labels"
import { PaySupplierDialog } from "@/components/livestock/pay-supplier-dialog"
import { AMBER_BUTTON, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockPurchasePage() {
  const { id } = useParams<{ id: string }>()
  const purchaseId = Number(id)
  const [p, setP] = useState<Purchase | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [paying, setPaying] = useState(false)
  const [reversing, setReversing] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setP(await getPurchase(purchaseId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [purchaseId])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-purchases", label: "Purchases" }
  if (error) return <LivestockPage title="Purchase" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!p) return <LivestockPage title="Purchase" back={back}><Loading /></LivestockPage>

  return (
    <LivestockPage
      title={<>{p.supplierName ?? "Cash purchase"} · {fmtDate(p.date)} <Badge className={`ml-2 align-middle ${PURCHASE_STATUS[p.status].cls}`}>{PURCHASE_STATUS[p.status].label}</Badge></>}
      description={[p.reference && `Invoice ${p.reference}`, p.dueDate && `pay by ${fmtDate(p.dueDate)}`, p.createdBy && `recorded by ${p.createdBy}`].filter(Boolean).join(" · ")}
      icon={ShoppingCart}
      back={back}
      actions={!p.reversedAt ? (
        <>
          {p.owed > 0 && p.supplierId && <Button className={AMBER_BUTTON} onClick={() => setPaying(true)}>Pay {fmtMoney(p.owed)}</Button>}
          <Button variant="outline" className="text-rose-700" onClick={() => setReversing(true)}>Reverse</Button>
        </>
      ) : undefined}
    >
      {p.reversedAt && <div className="rounded-md border border-stone-300 bg-stone-50 p-3 text-sm">Reversed: {p.reverseReason}</div>}
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="Total" value={fmtMoney(p.total)} tone="amber" />
        <StatCard label="Paid" value={fmtMoney(p.paid)} tone="emerald" />
        <StatCard label="Owed" value={fmtMoney(p.owed)} tone={p.overdue ? "rose" : "stone"} hint={p.overdue ? "Overdue" : undefined} />
      </div>
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Bought</CardTitle></CardHeader>
        <CardContent>
          <Table>
            <TableHeader><TableRow><TableHead>What</TableHead><TableHead className="text-right">Quantity</TableHead><TableHead className="text-right">Price each</TableHead><TableHead className="text-right">Total</TableHead></TableRow></TableHeader>
            <TableBody>
              {p.lines.map((l) => (
                <TableRow key={l.lineId}>
                  <TableCell>
                    {l.lineType === "Item"
                      ? <Link className="text-amber-800 hover:underline" href={`/livestock-items/${l.itemId}`}>{l.itemName}</Link>
                      : l.lineType === "Expense"
                      ? <>{l.expenseCategory}{l.description ? `: ${l.description}` : ""}</>
                      : <>{l.speciesName} · <Link className="text-amber-800 hover:underline" href="/livestock-batches">batch {l.batchCode}</Link></>}
                  </TableCell>
                  <TableCell className="text-right">{fmtNum(l.quantity)} {l.lineType === "Item" ? l.unit : l.lineType === "Animals" ? "head" : ""}</TableCell>
                  <TableCell className="text-right">{fmtMoney(l.unitCost)}</TableCell>
                  <TableCell className="text-right">{fmtMoney(l.lineTotal)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Payments</CardTitle></CardHeader>
        <CardContent className="text-sm">
          {p.payments.length === 0 ? <p className="text-stone-500">Nothing paid yet.</p> : (
            <ul className="divide-y">
              {p.payments.map((x) => (
                <li key={x.paymentId} className={`py-2 flex justify-between ${x.reversedAt ? "opacity-50" : ""}`}>
                  <span>{fmtDate(x.date)} · {x.accountName}{x.isUpfront ? " · paid with the purchase" : ""}{x.reversedAt ? " (reversed)" : ""}</span>
                  <span className="font-medium">{fmtMoney(x.amount)}</span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
      {p.notes && <Card><CardContent className="p-4 text-sm whitespace-pre-wrap">{p.notes}</CardContent></Card>}

      {paying && p.supplierId && (
        <PaySupplierDialog supplierId={p.supplierId} supplierName={p.supplierName ?? "supplier"} owed={p.owed} purchaseId={p.purchaseId}
          onClose={() => setPaying(false)} onDone={() => { setPaying(false); load() }} />
      )}
      <PromptDialog
        open={reversing}
        onOpenChange={setReversing}
        title="Reverse this purchase?"
        description="Its stock comes back out, its animals' batch is removed, and money paid with it goes back into the account."
        label="Why"
        confirmLabel="Reverse purchase"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reversePurchase(purchaseId, reason); setReversing(false); load() }}
      />
    </LivestockPage>
  )
}

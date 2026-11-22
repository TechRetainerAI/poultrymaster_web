"use client"

// Customer Balances -- what each customer owes, their statement with a
// running balance, receiving payment, and the payments received.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Scale } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  getCustomerStatement, listCustomerBalances, listCustomerPayments, reverseCustomerPayment,
  type CustomerBalance, type CustomerPayment, type CustomerStatement,
} from "@/lib/api/livestock"
import { ReceivePaymentDialog } from "@/components/livestock/receive-payment-dialog"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney } from "@/components/livestock/livestock-page"

export default function LivestockCustomerBalancesPage() {
  const [rows, setRows] = useState<CustomerBalance[] | null>(null)
  const [payments, setPayments] = useState<CustomerPayment[]>([])
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<number | null>(null)
  const [statement, setStatement] = useState<CustomerStatement | null>(null)
  const [receiving, setReceiving] = useState<CustomerBalance | null>(null)
  const [reversing, setReversing] = useState<CustomerPayment | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [b, p] = await Promise.all([listCustomerBalances(), listCustomerPayments()])
      setRows(b); setPayments(p)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => {
    load()
    const c = Number(new URLSearchParams(window.location.search).get("customerId"))
    if (c) setSelected(c)
  }, [load])
  useEffect(() => {
    if (!selected) { setStatement(null); return }
    getCustomerStatement(selected).then(setStatement).catch(() => setStatement(null))
  }, [selected, rows])

  const owes = (rows ?? []).reduce((s, r) => s + r.owes, 0)
  const overdue = (rows ?? []).reduce((s, r) => s + r.overdue, 0)
  const later = payments.filter((p) => !p.isUpfront)

  return (
    <LivestockPage title="Customer balances" description="What customers owe you, and receiving it." icon={Scale}>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="Customers owe you" value={fmtMoney(owes)} tone="amber" />
        <StatCard label="Of which overdue" value={fmtMoney(overdue)} tone={overdue > 0 ? "rose" : "stone"} />
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : (
        <Tabs defaultValue="balances">
          <TabsList>
            <TabsTrigger value="balances">Balances</TabsTrigger>
            <TabsTrigger value="payments">Payments ({later.length})</TabsTrigger>
          </TabsList>
          <TabsContent value="balances" className="pt-3 space-y-4">
            {rows.length === 0 ? <EmptyState title="No sales to customers yet" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Customer</TableHead><TableHead className="text-right">Bought</TableHead><TableHead className="text-right">Paid</TableHead><TableHead className="text-right">Owes</TableHead><TableHead>Last sale</TableHead><TableHead /></TableRow></TableHeader>
                  <TableBody>
                    {rows.map((r) => (
                      <TableRow key={r.customerId} className={`cursor-pointer hover:bg-amber-50/60 ${selected === r.customerId ? "bg-amber-50" : ""}`} onClick={() => setSelected(r.customerId)}>
                        <TableCell className="font-medium">{r.name}{r.phone && <div className="text-xs text-stone-500">{r.phone}</div>}</TableCell>
                        <TableCell className="text-right">{fmtMoney(r.bought)}</TableCell>
                        <TableCell className="text-right">{fmtMoney(r.paid)}</TableCell>
                        <TableCell className={`text-right font-medium ${r.overdue > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.owes)}{r.overdue > 0 && <Badge className="ml-2 bg-rose-600">Overdue</Badge>}</TableCell>
                        <TableCell>{fmtDate(r.lastSale)}</TableCell>
                        <TableCell className="text-right">{r.owes > 0 && <Button size="sm" className={AMBER_BUTTON} onClick={(e) => { e.stopPropagation(); setReceiving(r) }}>Receive</Button>}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
            {statement && (
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">{statement.name}: statement</CardTitle></CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>What</TableHead><TableHead className="text-right">Sold</TableHead><TableHead className="text-right">Paid</TableHead><TableHead className="text-right">Owes after</TableHead></TableRow></TableHeader>
                    <TableBody>
                      {statement.lines.map((l) => (
                        <TableRow key={`${l.kind}-${l.id}`}>
                          <TableCell>{fmtDate(l.date)}</TableCell>
                          <TableCell>{l.kind === "Sale" ? <Link className="text-amber-800 hover:underline" href={`/livestock-sales/${l.id}`}>{l.description}</Link> : l.description}</TableCell>
                          <TableCell className="text-right">{l.sold != null ? fmtMoney(l.sold) : ""}</TableCell>
                          <TableCell className="text-right">{l.paid != null ? fmtMoney(l.paid) : ""}</TableCell>
                          <TableCell className="text-right">{fmtMoney(l.balance)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            )}
          </TabsContent>
          <TabsContent value="payments" className="pt-3">
            {later.length === 0 ? <EmptyState title="No payments received after a sale yet" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Customer</TableHead><TableHead>Into</TableHead><TableHead>Reference</TableHead><TableHead className="text-right">Amount</TableHead><TableHead /></TableRow></TableHeader>
                  <TableBody>
                    {later.map((p) => (
                      <TableRow key={p.paymentId} className={p.reversedAt ? "opacity-50" : undefined}>
                        <TableCell>{fmtDate(p.date)}</TableCell>
                        <TableCell>{p.customerName}{p.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                        <TableCell>{p.accountName}</TableCell>
                        <TableCell>{p.reference ?? "—"}</TableCell>
                        <TableCell className="text-right">{fmtMoney(p.amount)}</TableCell>
                        <TableCell className="text-right">{!p.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(p)}>Reverse</Button>}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </TabsContent>
        </Tabs>
      )}
      {receiving && <ReceivePaymentDialog customerId={receiving.customerId} customerName={receiving.name} owes={receiving.owes} onClose={() => setReceiving(null)} onDone={() => { setReceiving(null); load() }} />}
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this payment?"
        description={reversing ? `${fmtMoney(reversing.amount)} from ${reversing.customerName} comes back out of ${reversing.accountName}, and is owed again.` : undefined}
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseCustomerPayment(reversing!.paymentId, reason); setReversing(null); load() }}
      />
    </LivestockPage>
  )
}

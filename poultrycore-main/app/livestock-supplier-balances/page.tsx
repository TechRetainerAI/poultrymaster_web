"use client"

// Supplier Balances -- what is owed to each supplier, a supplier's statement
// (purchases and payments with a running balance), paying them, and the
// payments made.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Scale } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  getSupplierStatement, listSupplierBalances, listSupplierPayments, reverseSupplierPayment,
  type SupplierBalance, type SupplierPayment, type SupplierStatement,
} from "@/lib/api/livestock"
import { PaySupplierDialog } from "@/components/livestock/pay-supplier-dialog"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney } from "@/components/livestock/livestock-page"

export default function LivestockSupplierBalancesPage() {
  const [rows, setRows] = useState<SupplierBalance[] | null>(null)
  const [payments, setPayments] = useState<SupplierPayment[]>([])
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<number | null>(null)
  const [statement, setStatement] = useState<SupplierStatement | null>(null)
  const [paying, setPaying] = useState<SupplierBalance | null>(null)
  const [reversing, setReversing] = useState<SupplierPayment | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [b, p] = await Promise.all([listSupplierBalances(), listSupplierPayments()])
      setRows(b); setPayments(p)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => {
    load()
    const s = Number(new URLSearchParams(window.location.search).get("supplierId"))
    if (s) setSelected(s)
  }, [load])
  useEffect(() => {
    if (!selected) { setStatement(null); return }
    getSupplierStatement(selected).then(setStatement).catch(() => setStatement(null))
  }, [selected, rows])

  const owed = (rows ?? []).reduce((s, r) => s + r.owed, 0)
  const overdue = (rows ?? []).reduce((s, r) => s + r.overdue, 0)
  const pg = usePagination(rows ?? [], 10)
  const statementPg = usePagination(statement?.lines ?? [], 10)
  const paymentsPg = usePagination(payments.filter((p) => !p.isUpfront), 10)

  return (
    <LivestockPage title="Supplier balances" description="What you owe each supplier, and paying them." icon={Scale}>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="You owe suppliers" value={fmtMoney(owed)} tone="amber" />
        <StatCard label="Of which overdue" value={fmtMoney(overdue)} tone={overdue > 0 ? "rose" : "stone"} />
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : (
        <Tabs defaultValue="balances">
          <TabsList>
            <TabsTrigger value="balances">Balances</TabsTrigger>
            <TabsTrigger value="payments">Payments ({payments.filter((p) => !p.isUpfront).length})</TabsTrigger>
          </TabsList>
          <TabsContent value="balances" className="pt-3 space-y-4">
            {rows.length === 0 ? <EmptyState title="Nothing bought from a supplier yet" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Supplier</TableHead><TableHead className="text-right">Bought</TableHead><TableHead className="text-right">Paid</TableHead><TableHead className="text-right">Owed</TableHead><TableHead>Last bought</TableHead><TableHead /></TableRow></TableHeader>
                  <TableBody>
                    {pg.pageItems.map((r) => (
                      <TableRow key={r.supplierId} className={`cursor-pointer hover:bg-amber-50/60 ${selected === r.supplierId ? "bg-amber-50" : ""}`} onClick={() => setSelected(r.supplierId)}>
                        <TableCell className="font-medium">{r.name}{r.phone && <div className="text-xs text-stone-500">{r.phone}</div>}</TableCell>
                        <TableCell className="text-right">{fmtMoney(r.bought)}</TableCell>
                        <TableCell className="text-right">{fmtMoney(r.paid)}</TableCell>
                        <TableCell className={`text-right font-medium ${r.overdue > 0 ? "text-rose-700" : ""}`}>{fmtMoney(r.owed)}{r.overdue > 0 && <Badge className="ml-2 bg-rose-600">Overdue</Badge>}</TableCell>
                        <TableCell>{fmtDate(r.lastPurchase)}</TableCell>
                        <TableCell className="text-right">{r.owed > 0 && <Button size="sm" className={AMBER_BUTTON} onClick={(e) => { e.stopPropagation(); setPaying(r) }}>Pay</Button>}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...pg.paginationProps} variant="records" />
              </div>
            )}
            {statement && (
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">{statement.name}: statement</CardTitle></CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>What</TableHead><TableHead className="text-right">Bought</TableHead><TableHead className="text-right">Paid</TableHead><TableHead className="text-right">Owed after</TableHead></TableRow></TableHeader>
                    <TableBody>
                      {statementPg.pageItems.map((l) => (
                        <TableRow key={`${l.kind}-${l.id}`}>
                          <TableCell>{fmtDate(l.date)}</TableCell>
                          <TableCell>{l.kind === "Purchase" ? <Link className="text-amber-800 hover:underline" href={`/livestock-purchases/${l.id}`}>{l.description}</Link> : l.description}</TableCell>
                          <TableCell className="text-right">{l.bought != null ? fmtMoney(l.bought) : ""}</TableCell>
                          <TableCell className="text-right">{l.paid != null ? fmtMoney(l.paid) : ""}</TableCell>
                          <TableCell className="text-right">{fmtMoney(l.balance)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  <DataPagination {...statementPg.paginationProps} variant="records" />
                </CardContent>
              </Card>
            )}
          </TabsContent>
          <TabsContent value="payments" className="pt-3">
            {payments.filter((p) => !p.isUpfront).length === 0 ? <EmptyState title="No supplier payments yet" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Supplier</TableHead><TableHead>From</TableHead><TableHead>Reference</TableHead><TableHead className="text-right">Amount</TableHead><TableHead /></TableRow></TableHeader>
                  <TableBody>
                    {paymentsPg.pageItems.map((p) => (
                      <TableRow key={p.paymentId} className={p.reversedAt ? "opacity-50" : undefined}>
                        <TableCell>{fmtDate(p.date)}</TableCell>
                        <TableCell>{p.supplierName}{p.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                        <TableCell>{p.accountName}</TableCell>
                        <TableCell>{p.reference ?? "—"}</TableCell>
                        <TableCell className="text-right">{fmtMoney(p.amount)}</TableCell>
                        <TableCell className="text-right">{!p.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(p)}>Reverse</Button>}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...paymentsPg.paginationProps} variant="records" />
              </div>
            )}
          </TabsContent>
        </Tabs>
      )}
      {paying && <PaySupplierDialog supplierId={paying.supplierId} supplierName={paying.name} owed={paying.owed} onClose={() => setPaying(null)} onDone={() => { setPaying(null); load() }} />}
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this payment?"
        description={reversing ? `${fmtMoney(reversing.amount)} to ${reversing.supplierName} goes back into ${reversing.accountName}, and is owed again.` : undefined}
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseSupplierPayment(reversing!.paymentId, reason); setReversing(null); load() }}
      />
    </LivestockPage>
  )
}

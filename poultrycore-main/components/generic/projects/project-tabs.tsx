"use client"

// The tabs of a project's workspace. Every figure comes from the engine (484)
// through lib/api/generic-projects; nothing is recomputed here except sums of
// rows the server already split.

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react"
import Link from "next/link"
import { AlertTriangle, ArrowRightLeft, CheckCircle2, Loader2, Pencil, Plus, Trash2, Undo2 } from "lucide-react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { getProducts, getStaff, type GenericProduct, type GenericStaff } from "@/lib/api/generic"
import {
  BUDGET_CATEGORIES, budgetCategoryLabel, deleteMilestone, getMilestones, getProjectBudget, getProjectInventory, getScopedCashFlow,
  reserveStock, saveMilestone, saveProjectBudget, undoReservation,
  type BudgetCategory, type MilestoneStatus, type ProjectBudget, type ProjectCashFlow, type ProjectInventory,
  type ProjectMilestone, type ProjectPnlRow, type ProjectTransactions,
} from "@/lib/api/generic-projects"
import { getInvoiceDocuments, type InvoiceDocumentRow } from "@/lib/api/generic-invoice-documents"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { ProjectPicker } from "./project-picker"

const SECTION_LABEL: Record<string, string> = {
  revenue: "Revenue", direct: "Cost of goods sold / direct costs", operating: "Operating expenses",
  other: "Depreciation & financing costs", owner: "Owner money (financing, not profit)",
  borrowing: "Loans (financing, not profit)", capital: "Capital spending (not an expense)",
}

/** Where to open the source transaction behind a row. */
export function sourceHref(type: string, id: number): string | null {
  switch (type) {
    case "Sale": case "SaleProduct": case "SaleLine": return `/generic-sales/${id}`
    case "Purchase": case "PurchaseLine": return `/generic-purchases/${id}`
    case "Expense": return `/generic-expenses?expenseId=${id}`
    case "OwnerEntry": return `/generic-owner-money`
    case "Loan": return `/generic-loans`
    case "PayrollRun": return `/generic-payroll`
    case "CapitalAsset": return `/generic-assets`
    default: return null
  }
}

function Empty({ children }: { children: ReactNode }) {
  return <p className="py-8 text-center text-sm text-slate-500">{children}</p>
}

function Share({ share }: { share: number }) {
  return share >= 0.9999 ? null : <span className="ml-1 text-xs text-slate-400">({Math.round(share * 1000) / 10}%)</span>
}

// ---------------------------------------------------------------- Transactions

export function TransactionsTab({ tx }: { tx: ProjectTransactions }) {
  const fmt = useFmt()
  const rows = tx.pnl
  if (rows.length === 0 && tx.purchases.length === 0 && tx.cash.rows.length === 0) {
    return <Card><CardContent><Empty>Nothing is assigned to this project yet. Record a purchase, expense or sale and pick this project on it, or link older transactions.</Empty></CardContent></Card>
  }
  return (
    <Card>
      <CardHeader><CardTitle className="text-base">Everything behind this project&apos;s numbers</CardTitle>
        <CardDescription>Each row is a real transaction (or the project&apos;s share of one). Click a reference to open it.</CardDescription></CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Reference</TableHead><TableHead>What</TableHead><TableHead>Line</TableHead><TableHead className="text-right">Amount</TableHead></TableRow></TableHeader>
          <TableBody>
            {rows.map((r, i) => {
              const href = sourceHref(r.sourceType, r.sourceId)
              return (
                <TableRow key={`p${i}`}>
                  <TableCell>{r.date}</TableCell>
                  <TableCell>{href ? <Link className="text-indigo-700 hover:underline" href={href}>{r.ref}</Link> : r.ref}<Share share={r.share} /></TableCell>
                  <TableCell className="max-w-xs truncate">{r.description}</TableCell>
                  <TableCell><span className="text-xs text-slate-500">{SECTION_LABEL[r.section] ?? r.section}</span><div>{r.line}</div></TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(r.amount)}</TableCell>
                </TableRow>
              )
            })}
            {tx.purchases.map((p, i) => (
              <TableRow key={`b${i}`}>
                <TableCell>{p.date}</TableCell>
                <TableCell><Link className="text-indigo-700 hover:underline" href={`/generic-purchases/${p.purchaseId}`}>{p.ref}</Link></TableCell>
                <TableCell>{p.productName ?? "Purchase"} × {p.quantity}</TableCell>
                <TableCell><span className="text-xs text-slate-500">Purchase (stock bought, not yet a cost)</span></TableCell>
                <TableCell className="text-right tabular-nums text-slate-500">{fmt(p.amount)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------- P&L

export function PnlStatement({ rows, projectId }: { rows: ProjectPnlRow[]; projectId: number }) {
  const fmt = useFmt()
  const by = useMemo(() => {
    const m = new Map<string, Map<string, number>>()
    for (const r of rows) {
      const s = m.get(r.section) ?? new Map<string, number>()
      s.set(r.line, (s.get(r.line) ?? 0) + r.amount)
      m.set(r.section, s)
    }
    return m
  }, [rows])
  const total = (s: string) => [...(by.get(s)?.values() ?? [])].reduce((a, b) => a + b, 0)
  const revenue = total("revenue"), direct = total("direct"), operating = total("operating"), other = total("other")
  const gross = revenue - direct, net = gross - operating - other
  const lines = (s: string) => [...(by.get(s)?.entries() ?? [])].map(([l, v]) => (
    <div key={l} className="flex justify-between py-0.5 pl-4 text-sm"><span className="text-slate-600">{l}</span><span className="tabular-nums">{fmt(v)}</span></div>
  ))
  const totalRow = (label: string, v: number, strong = false) => (
    <div className={`flex justify-between border-t py-1.5 text-sm ${strong ? "font-semibold" : "font-medium"}`}><span>{label}</span><span className={`tabular-nums ${v < 0 ? "text-rose-700" : ""}`}>{fmt(v)}</span></div>
  )
  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0">
        <div>
          <CardTitle className="text-base">Project Profit &amp; Loss</CardTitle>
          <CardDescription>Same rules as the company P&amp;L: revenue when sold, cost of goods when sold (not when bought), owner money and loans kept out.</CardDescription>
        </div>
        <Button variant="outline" size="sm" asChild><Link href={`/generic-profit-loss?project=${projectId}`}>Open in the full P&amp;L</Link></Button>
      </CardHeader>
      <CardContent className="max-w-2xl">
        <div className="text-xs font-semibold uppercase text-slate-500">Revenue</div>{lines("revenue")}
        {totalRow("Total revenue", revenue)}
        <div className="mt-3 text-xs font-semibold uppercase text-slate-500">Cost of goods sold / direct costs</div>{lines("direct")}
        {totalRow("Gross profit", gross, true)}
        <div className="mt-3 text-xs font-semibold uppercase text-slate-500">Operating expenses</div>{lines("operating")}
        {other !== 0 && <><div className="mt-3 text-xs font-semibold uppercase text-slate-500">Depreciation &amp; financing costs</div>{lines("other")}</>}
        {totalRow("Net project profit / contribution", net, true)}
        <div className="pt-1 text-sm text-slate-500">Margin: {revenue ? `${((net / revenue) * 100).toFixed(1)}%` : "—"}</div>
        {(by.has("owner") || by.has("borrowing") || by.has("capital")) && (
          <div className="mt-4 rounded-md bg-slate-50 p-3 text-sm">
            <div className="mb-1 text-xs font-semibold uppercase text-slate-500">Not in profit</div>
            {lines("owner")}{lines("borrowing")}{lines("capital")}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------- Sales & receivables

export function SalesTab({ tx, projectId }: { tx: ProjectTransactions; projectId?: number }) {
  const fmt = useFmt()
  const { showNew } = useGenericModules()
  const invoicingEnabled = showNew("enableInvoices")
  const sales = tx.pnl.filter((r) => r.section === "revenue")
  const owed = tx.balances.filter((b) => b.kind === "Receivable")
  const adv = tx.balances.filter((b) => b.kind === "CustomerAdvance")
  const received = tx.cash.byCategory.filter((c) => c.category === "Customer payments" || c.category === "Sales paid at the counter")
    .reduce((a, c) => a + c.net, 0)

  // Invoice documents for this project (fetched lazily)
  const [invoiceDocs, setInvoiceDocs] = useState<InvoiceDocumentRow[]>([])
  useEffect(() => {
    if (!invoicingEnabled || !projectId) return
    getInvoiceDocuments({ projectId }).then(setInvoiceDocs).catch(() => {})
  }, [invoicingEnabled, projectId])

  // Map saleId → invoice doc for quick lookup
  const invoiceBySale = useMemo(() => {
    const map = new Map<number, InvoiceDocumentRow>()
    for (const d of invoiceDocs) map.set(d.genericSaleId, d)
    return map
  }, [invoiceDocs])

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Mini label="Revenue earned" value={fmt(sales.reduce((a, r) => a + r.amount, 0))} />
        <Mini label="Collected" value={fmt(received)} />
        <Mini label="Still owed" value={fmt(owed.reduce((a, r) => a + r.amount, 0))} />
        <Mini label="Advances held" value={fmt(adv.reduce((a, r) => a + r.amount, 0))} />
      </div>
      <Card>
        <CardHeader><CardTitle className="text-base">Sales</CardTitle></CardHeader>
        <CardContent className="p-0">
          {sales.length === 0 ? <Empty>No sales for this project yet.</Empty> : (
            <Table><TableHeader><TableRow>
              <TableHead>Date</TableHead><TableHead>Sale</TableHead><TableHead>Customer</TableHead>
              {invoicingEnabled && <TableHead>Invoice</TableHead>}
              <TableHead className="text-right">Revenue</TableHead>
            </TableRow></TableHeader>
              <TableBody>{sales.map((r, i) => {
                const inv = invoiceBySale.get(r.sourceId)
                return (
                  <TableRow key={i}><TableCell>{r.date}</TableCell>
                    <TableCell><Link className="text-indigo-700 hover:underline" href={`/generic-sales/${r.sourceId}`}>{r.ref}</Link><Share share={r.share} /></TableCell>
                    <TableCell>{r.description}</TableCell>
                    {invoicingEnabled && (
                      <TableCell>
                        {inv ? (
                          <Link className="text-indigo-700 hover:underline font-mono text-xs" href={`/generic-invoice-documents/${inv.genericInvoiceDocumentId}`}>
                            {inv.invoiceNumber}
                          </Link>
                        ) : (
                          <span className="text-xs text-slate-400">—</span>
                        )}
                      </TableCell>
                    )}
                    <TableCell className="text-right tabular-nums">{fmt(r.amount)}</TableCell></TableRow>
                )
              })}</TableBody></Table>
          )}
        </CardContent>
      </Card>
      <BalanceTable title="Customer still owes" rows={owed} empty="Nothing owed." />
      {adv.length > 0 && <BalanceTable title="Customer advances (received, not yet earned)" rows={adv} empty="" />}
    </div>
  )
}

function Mini({ label, value }: { label: string; value: ReactNode }) {
  return <div className="rounded-lg border border-slate-200 bg-white p-3"><div className="text-xs text-slate-500">{label}</div><div className="text-lg font-semibold tabular-nums">{value}</div></div>
}

function BalanceTable({ title, rows, empty }: { title: string; rows: ProjectTransactions["balances"]; empty: string }) {
  const fmt = useFmt()
  const today = new Date().toISOString().slice(0, 10)
  return (
    <Card>
      <CardHeader><CardTitle className="text-base">{title}</CardTitle></CardHeader>
      <CardContent className="p-0">
        {rows.length === 0 ? <Empty>{empty}</Empty> : (
          <Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Document</TableHead><TableHead>Party</TableHead><TableHead>Due</TableHead><TableHead className="text-right">Amount</TableHead></TableRow></TableHeader>
            <TableBody>{rows.map((b, i) => {
              const href = sourceHref(b.documentType, b.documentId)
              return (
                <TableRow key={i}><TableCell>{b.date}</TableCell>
                  <TableCell>{href ? <Link className="text-indigo-700 hover:underline" href={href}>{b.ref}</Link> : b.ref}</TableCell>
                  <TableCell>{b.party ?? "—"}</TableCell>
                  <TableCell>{b.dueDate ? <span className={b.dueDate < today ? "font-medium text-rose-700" : ""}>{b.dueDate}{b.dueDate < today ? " (overdue)" : ""}</span> : "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(b.amount)}</TableCell></TableRow>
              )
            })}</TableBody></Table>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------- Expenses & costs

export function ExpensesTab({ tx }: { tx: ProjectTransactions }) {
  const fmt = useFmt()
  const costs = tx.pnl.filter((r) => r.section === "direct" || r.section === "operating" || r.section === "other")
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader><CardTitle className="text-base">Costs recognised in the project P&amp;L</CardTitle>
          <CardDescription>Cost of goods appears when goods are sold, not when they are bought. Shared expenses show only this project&apos;s part.</CardDescription></CardHeader>
        <CardContent className="p-0">
          {costs.length === 0 ? <Empty>No costs yet.</Empty> : (
            <Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Reference</TableHead><TableHead>Line</TableHead><TableHead>Kind</TableHead><TableHead className="text-right">Amount</TableHead></TableRow></TableHeader>
              <TableBody>{costs.map((r, i) => {
                const href = sourceHref(r.sourceType, r.sourceId)
                return (
                  <TableRow key={i}><TableCell>{r.date}</TableCell>
                    <TableCell>{href ? <Link className="text-indigo-700 hover:underline" href={href}>{r.ref}</Link> : r.ref}<Share share={r.share} /></TableCell>
                    <TableCell>{r.line}<div className="max-w-xs truncate text-xs text-slate-500">{r.description}</div></TableCell>
                    <TableCell>{r.costClass ? <Badge variant="secondary">{r.costClass}</Badge> : null}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmt(r.amount)}</TableCell></TableRow>
                )
              })}</TableBody></Table>
          )}
        </CardContent>
      </Card>
      <BalanceTable title="Owed to suppliers" rows={tx.balances.filter((b) => b.kind === "Payable")} empty="Nothing owed." />
      {tx.balances.some((b) => b.kind === "SupplierAdvance") && (
        <BalanceTable title="Supplier advances (paid ahead, not an expense)" rows={tx.balances.filter((b) => b.kind === "SupplierAdvance")} empty="" />
      )}
    </div>
  )
}

// ---------------------------------------------------------------- Cash flow & funding

export function CashTab({ cash }: { cash: ProjectCashFlow }) {
  const fmt = useFmt()
  const act = (k: string) => cash.byActivity?.[k] ?? 0
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <Mini label="Money in" value={fmt(cash.moneyIn)} />
        <Mini label="Money out" value={fmt(cash.moneyOut)} />
        <Mini label="Operating" value={fmt(act("Operating"))} />
        <Mini label="Investing" value={fmt(act("Investing"))} />
        <Mini label="Financing (owner money, loans)" value={fmt(act("Financing"))} />
      </div>
      <div className="rounded-md border border-slate-200 bg-white p-3 text-sm text-slate-600">
        Net attributable cash: <b className="text-slate-900">{fmt(cash.net)}</b>. This is the money that moved because of this project —
        it is not profit, and it is not a separate bank balance: the money sits in the company&apos;s usual accounts.
      </div>
      <Card>
        <CardHeader><CardTitle className="text-base">By kind</CardTitle></CardHeader>
        <CardContent className="p-0">
          <Table><TableHeader><TableRow><TableHead>Activity</TableHead><TableHead>Kind</TableHead><TableHead className="text-right">In</TableHead><TableHead className="text-right">Out</TableHead><TableHead className="text-right">Net</TableHead></TableRow></TableHeader>
            <TableBody>{cash.byCategory.map((c, i) => (
              <TableRow key={i}><TableCell>{c.activity}</TableCell><TableCell>{c.category}</TableCell>
                <TableCell className="text-right tabular-nums">{fmt(c.moneyIn)}</TableCell><TableCell className="text-right tabular-nums">{fmt(c.moneyOut)}</TableCell>
                <TableCell className="text-right tabular-nums font-medium">{fmt(c.net)}</TableCell></TableRow>
            ))}</TableBody></Table>
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle className="text-base">Every money movement</CardTitle></CardHeader>
        <CardContent className="p-0">
          {cash.rows.length === 0 ? <Empty>No money has moved for this project yet.</Empty> : (
            <Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Kind</TableHead><TableHead>Description</TableHead><TableHead className="text-right">Amount</TableHead></TableRow></TableHeader>
              <TableBody>{cash.rows.map((r) => (
                <TableRow key={`${r.cashTransactionId}`}><TableCell>{r.date}</TableCell><TableCell>{r.category}</TableCell>
                  <TableCell className="max-w-sm truncate">{r.description}<Share share={r.share} /></TableCell>
                  <TableCell className={`text-right tabular-nums ${r.amount < 0 ? "text-rose-700" : "text-emerald-700"}`}>{fmt(r.amount)}</TableCell></TableRow>
              ))}</TableBody></Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------- Purchases & inventory

export function InventoryTab({ projectId, tx }: { projectId: number; tx: ProjectTransactions }) {
  const fmt = useFmt()
  const { toast } = useToast()
  const { can } = usePermissions()
  const [inv, setInv] = useState<ProjectInventory | null>(null)
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [dlg, setDlg] = useState<null | { action: "Reserve" | "Release" | "Transfer"; productId?: number }>(null)
  const [qty, setQty] = useState("")
  const [product, setProduct] = useState<string>("")
  const [toProject, setToProject] = useState<number | null>(null)
  const [note, setNote] = useState("")
  const [undo, setUndo] = useState<{ entryId: number } | null>(null)
  const [undoReason, setUndoReason] = useState("")

  const load = useCallback(async () => {
    try { setInv(await getProjectInventory(projectId)) } catch (e: any) { toast({ title: "Could not load stock", description: e?.message, variant: "destructive" }) }
  }, [projectId, toast])
  useEffect(() => { void load(); getProducts().then((p) => setProducts(p.filter((x: any) => x.trackInventory !== false))).catch(() => {}) }, [load])

  const open = (action: "Reserve" | "Release" | "Transfer", productId?: number) => {
    setDlg({ action, productId }); setProduct(productId ? String(productId) : ""); setQty(""); setNote(""); setToProject(null)
  }
  const submit = async () => {
    if (!dlg) return
    try {
      setInv(await reserveStock(projectId, {
        productId: Number(product), action: dlg.action, quantity: Number(qty), note: note || undefined,
        toProjectId: dlg.action === "Transfer" ? toProject ?? undefined : undefined,
      }))
      setDlg(null)
      toast({ title: dlg.action === "Reserve" ? "Stock reserved" : dlg.action === "Release" ? "Reservation released" : "Moved to the other project",
        description: "Company stock on hand did not change." })
    } catch (e: any) { toast({ title: "Not done", description: e?.message, variant: "destructive" }) }
  }
  const doUndo = async () => {
    if (!undo) return
    try { setInv(await undoReservation(projectId, undo.entryId, undoReason)); setUndo(null); setUndoReason("") }
    catch (e: any) { toast({ title: "Not done", description: e?.message, variant: "destructive" }) }
  }
  const canReserve = can("generic.project-reservations.create")

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between space-y-0">
          <div>
            <CardTitle className="text-base">Stock for this project</CardTitle>
            <CardDescription>
              Reserving keeps goods on the shelf for this project without moving them: company stock stays the same until the goods are sold.
              Delivered = sold on sales assigned to this project.
            </CardDescription>
          </div>
          {canReserve && <Button size="sm" onClick={() => open("Reserve")}><Plus className="mr-1 h-4 w-4" />Reserve stock</Button>}
        </CardHeader>
        <CardContent className="p-0">
          {!inv ? <div className="p-6"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
            : inv.products.length === 0 ? <Empty>No stock bought, reserved or sold for this project yet.</Empty> : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Product</TableHead><TableHead className="text-right">Bought for project</TableHead><TableHead className="text-right">Reserved</TableHead>
                  <TableHead className="text-right">Delivered / sold</TableHead><TableHead className="text-right">Still reserved</TableHead>
                  <TableHead className="text-right">Company on hand</TableHead><TableHead className="text-right">Free for the company</TableHead><TableHead />
                </TableRow></TableHeader>
                <TableBody>{inv.products.map((p) => (
                  <TableRow key={p.productId}>
                    <TableCell className="font-medium">{p.productName}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.purchasedQuantity}<div className="text-xs text-slate-500">{fmt(p.purchasedValue)}</div></TableCell>
                    <TableCell className="text-right tabular-nums">{p.reservedQuantity}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.deliveredQuantity}<div className="text-xs text-slate-500">{fmt(p.deliveredValue)}</div></TableCell>
                    <TableCell className="text-right tabular-nums font-medium">{p.remainingReserved}<div className="text-xs text-slate-500">≈ {fmt(p.remainingReservedValue)} at cost</div></TableCell>
                    <TableCell className="text-right tabular-nums">{p.companyOnHand}</TableCell>
                    <TableCell className={`text-right tabular-nums ${p.availableToCompany < 0 ? "text-rose-700" : ""}`}>{p.availableToCompany}</TableCell>
                    <TableCell className="whitespace-nowrap text-right">
                      {canReserve && <>
                        <Button variant="ghost" size="sm" onClick={() => open("Reserve", p.productId)}>Reserve</Button>
                        {p.remainingReserved > 0 && <Button variant="ghost" size="sm" onClick={() => open("Release", p.productId)}>Release</Button>}
                        {p.remainingReserved > 0 && <Button variant="ghost" size="sm" onClick={() => open("Transfer", p.productId)}><ArrowRightLeft className="h-4 w-4" /></Button>}
                      </>}
                    </TableCell>
                  </TableRow>
                ))}</TableBody>
              </Table>
            )}
        </CardContent>
      </Card>

      {tx.purchases.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Purchases for this project</CardTitle>
            <CardDescription>The value of goods bought. It becomes a project cost only when the goods are sold or used.</CardDescription></CardHeader>
          <CardContent className="p-0">
            <Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Purchase</TableHead><TableHead>Supplier</TableHead><TableHead>Product</TableHead><TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Value</TableHead></TableRow></TableHeader>
              <TableBody>{tx.purchases.map((p, i) => (
                <TableRow key={i}><TableCell>{p.date}</TableCell>
                  <TableCell><Link className="text-indigo-700 hover:underline" href={`/generic-purchases/${p.purchaseId}`}>{p.ref}</Link></TableCell>
                  <TableCell>{p.supplier ?? "—"}</TableCell><TableCell>{p.productName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{p.quantity}</TableCell><TableCell className="text-right tabular-nums">{fmt(p.amount)}</TableCell></TableRow>
              ))}</TableBody></Table>
          </CardContent>
        </Card>
      )}

      {inv && inv.entries.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Reservation history</CardTitle></CardHeader>
          <CardContent className="p-0">
            <Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Product</TableHead><TableHead>Entry</TableHead><TableHead className="text-right">Qty</TableHead><TableHead>Note</TableHead><TableHead /></TableRow></TableHeader>
              <TableBody>{inv.entries.map((e) => (
                <TableRow key={e.entryId} className={e.reversedAt ? "text-slate-400 line-through" : ""}>
                  <TableCell>{e.date}</TableCell><TableCell>{e.productName}</TableCell>
                  <TableCell>{e.entryType === "TransferIn" ? `Moved in from ${e.otherProject}` : e.entryType === "TransferOut" ? `Moved to ${e.otherProject}` : e.entryType}</TableCell>
                  <TableCell className="text-right tabular-nums">{e.quantity}</TableCell>
                  <TableCell>{e.reversedAt ? `Undone: ${e.reversalReason}` : e.note}</TableCell>
                  <TableCell className="text-right">{!e.reversedAt && canReserve && <Button variant="ghost" size="sm" onClick={() => setUndo({ entryId: e.entryId })}><Undo2 className="h-4 w-4" /></Button>}</TableCell>
                </TableRow>
              ))}</TableBody></Table>
          </CardContent>
        </Card>
      )}

      <Dialog open={!!dlg} onOpenChange={(v) => !v && setDlg(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{dlg?.action === "Reserve" ? "Reserve stock for this project" : dlg?.action === "Release" ? "Release reserved stock" : "Move reserved stock to another project"}</DialogTitle>
            <DialogDescription>No stock moves and nothing is sold or expensed — this only says which project the goods on the shelf are for.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1"><Label>Product</Label>
              <Select value={product} onValueChange={setProduct}>
                <SelectTrigger><SelectValue placeholder="Choose a product" /></SelectTrigger>
                <SelectContent>{products.map((p) => <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>{p.productName}</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="space-y-1"><Label>Quantity</Label><NumberInput min={0} value={qty} onChange={(e: any) => setQty(e.target.value)} /></div>
            {dlg?.action === "Transfer" && <div className="space-y-1"><Label>To project</Label><ProjectPicker value={toProject} onChange={setToProject} allowGeneral={false} placeholder="Choose a project" /></div>}
            <div className="space-y-1"><Label>Note</Label><Input value={note} onChange={(e) => setNote(e.target.value)} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDlg(null)}>Cancel</Button>
            <Button onClick={submit} disabled={!product || !(Number(qty) > 0) || (dlg?.action === "Transfer" && !toProject)}>Save</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!undo} onOpenChange={(v) => !v && setUndo(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Undo this entry</DialogTitle><DialogDescription>The entry stays in the history, crossed out. Both halves of a move are undone together.</DialogDescription></DialogHeader>
          <div className="space-y-1"><Label>Why</Label><Input value={undoReason} onChange={(e) => setUndoReason(e.target.value)} /></div>
          <DialogFooter><Button variant="outline" onClick={() => setUndo(null)}>Cancel</Button><Button onClick={doUndo} disabled={!undoReason.trim()}>Undo</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// ---------------------------------------------------------------- Budget

const BASES = [
  { value: "committed", label: "Committed (approved purchases & expenses)" },
  { value: "cash", label: "Cash actually paid" },
  { value: "recognised", label: "Recognised cost in the P&L" },
] as const

export function BudgetTab({ projectId }: { projectId: number }) {
  const fmt = useFmt()
  const { toast } = useToast()
  const { can } = usePermissions()
  const [b, setB] = useState<ProjectBudget | null>(null)
  const [basis, setBasis] = useState<"committed" | "cash" | "recognised">("committed")
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState<Record<string, string>>({})

  const load = useCallback(async () => {
    try { setB(await getProjectBudget(projectId)) } catch (e: any) { toast({ title: "Could not load the budget", description: e?.message, variant: "destructive" }) }
  }, [projectId, toast])
  useEffect(() => { void load() }, [load])

  const startEdit = () => {
    const d: Record<string, string> = {}
    for (const l of b?.lines ?? []) if (l.planned != null) d[l.category] = String(l.planned)
    setDraft(d); setEditing(true)
  }
  const save = async () => {
    try {
      const lines = BUDGET_CATEGORIES.filter((c) => draft[c.value] !== undefined && draft[c.value] !== "")
        .map((c) => ({ category: c.value as BudgetCategory, plannedAmount: Number(draft[c.value]) }))
      setB(await saveProjectBudget(projectId, lines)); setEditing(false)
      toast({ title: "Budget saved", description: "Saved as a new version; earlier versions are kept." })
    } catch (e: any) { toast({ title: "Could not save", description: e?.message, variant: "destructive" }) }
  }
  if (!b) return <Loader2 className="h-5 w-5 animate-spin text-slate-400" />
  const actual = (l: ProjectBudget["lines"][number]) => l[basis]
  const variance = (l: ProjectBudget["lines"][number]) =>
    basis === "committed" ? l.varianceCommitted : basis === "cash" ? l.varianceCash : l.varianceRecognised

  return (
    <div className="space-y-4">
      {b.alerts.length > 0 && (
        <div className="space-y-1 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          {b.alerts.map((a) => <div key={a.category} className="flex gap-2"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />{a.message}</div>)}
          <div className="text-xs text-amber-700">A warning only — nothing is blocked.</div>
        </div>
      )}
      <Card>
        <CardHeader className="flex flex-row flex-wrap items-start justify-between gap-2 space-y-0">
          <div>
            <CardTitle className="text-base">Budget vs actual{b.version ? <span className="ml-2 text-xs font-normal text-slate-500">version {b.version}</span> : null}</CardTitle>
            <CardDescription>The three ways of measuring spend can differ a lot — pick the one you want to compare with.</CardDescription>
          </div>
          <div className="flex gap-2">
            <Select value={basis} onValueChange={(v) => setBasis(v as any)}>
              <SelectTrigger className="w-72"><SelectValue /></SelectTrigger>
              <SelectContent>{BASES.map((x) => <SelectItem key={x.value} value={x.value}>{x.label}</SelectItem>)}</SelectContent>
            </Select>
            {can("generic.project-budgets.edit") && !editing && <Button variant="outline" onClick={startEdit}><Pencil className="mr-1 h-4 w-4" />{b.version ? "Change budget" : "Set budget"}</Button>}
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader><TableRow><TableHead>Category</TableHead><TableHead className="text-right">Budget</TableHead><TableHead className="text-right">Actual</TableHead><TableHead className="text-right">Variance</TableHead></TableRow></TableHeader>
            <TableBody>{b.lines.map((l) => {
              const v = variance(l)
              return (
                <TableRow key={l.category}>
                  <TableCell>{budgetCategoryLabel(l.category)}</TableCell>
                  <TableCell className="text-right">
                    {editing
                      ? <NumberInput className="ml-auto w-36" min={0} value={draft[l.category] ?? ""} onChange={(e: any) => setDraft((d) => ({ ...d, [l.category]: e.target.value }))} />
                      : l.planned != null ? fmt(l.planned) : "—"}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(actual(l))}</TableCell>
                  <TableCell className={`text-right tabular-nums ${v != null && v < 0 ? "font-medium text-rose-700" : ""}`}>
                    {v == null ? "—" : fmt(v)}
                  </TableCell>
                </TableRow>
              )
            })}</TableBody>
          </Table>
          {editing && (
            <div className="flex justify-end gap-2 border-t p-3">
              <Button variant="outline" onClick={() => setEditing(false)}>Cancel</Button><Button onClick={save}>Save budget</Button>
            </div>
          )}
        </CardContent>
      </Card>
      <p className="text-xs text-slate-500">
        Purchases count as Materials and payroll as Labour. Expenses count against the budget line set on their expense category
        (otherwise Other direct costs; Overhead when assigned as overhead).
      </p>
    </div>
  )
}

// ---------------------------------------------------------------- Milestones

const MS_STATUS: { value: MilestoneStatus; label: string }[] = [
  { value: "Planned", label: "Planned" }, { value: "InProgress", label: "In progress" }, { value: "Completed", label: "Completed" },
  { value: "Missed", label: "Missed" }, { value: "Cancelled", label: "Cancelled" },
]
const SUGGESTED = ["Contract awarded", "Initial funding", "Materials purchased", "Goods delivered", "Invoice issued", "Payment received", "Project completed"]

export function MilestonesTab({ projectId, openNew }: { projectId: number; openNew?: boolean }) {
  const { toast } = useToast()
  const { can } = usePermissions()
  const fmt = useFmt()
  const [list, setList] = useState<ProjectMilestone[] | null>(null)
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [edit, setEdit] = useState<(Partial<ProjectMilestone> & { name: string }) | null>(null)

  const load = useCallback(async () => {
    try { setList(await getMilestones(projectId)) } catch (e: any) { toast({ title: "Could not load milestones", description: e?.message, variant: "destructive" }) }
  }, [projectId, toast])
  useEffect(() => { void load(); getStaff().then(setStaff).catch(() => {}) }, [load])
  useEffect(() => { if (openNew) setEdit({ name: "", status: "Planned" }) }, [openNew])

  const save = async () => {
    if (!edit) return
    try { setList(await saveMilestone(projectId, edit)); setEdit(null) }
    catch (e: any) { toast({ title: "Could not save", description: e?.message, variant: "destructive" }) }
  }
  const remove = async (m: ProjectMilestone) => {
    if (!window.confirm(`Remove "${m.name}"?`)) return
    try { await deleteMilestone(projectId, m.milestoneId); await load() } catch (e: any) { toast({ title: "Not removed", description: e?.message, variant: "destructive" }) }
  }
  const canEdit = can("generic.project-milestones.create")

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0">
        <div><CardTitle className="text-base">Milestones</CardTitle>
          <CardDescription>Progress only. Completing a milestone does not record revenue or a payment — record the sale or payment as usual.</CardDescription></div>
        {canEdit && <Button size="sm" onClick={() => setEdit({ name: "", status: "Planned" })}><Plus className="mr-1 h-4 w-4" />Add milestone</Button>}
      </CardHeader>
      <CardContent className="p-0">
        {!list ? <div className="p-6"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
          : list.length === 0 ? <Empty>No milestones yet.</Empty> : (
            <Table><TableHeader><TableRow><TableHead>Milestone</TableHead><TableHead>Planned</TableHead><TableHead>Done</TableHead><TableHead>Status</TableHead><TableHead>Responsible</TableHead><TableHead className="text-right">Amount</TableHead><TableHead /></TableRow></TableHeader>
              <TableBody>{list.map((m) => (
                <TableRow key={m.milestoneId}>
                  <TableCell><div className="font-medium">{m.name}</div>{m.description && <div className="text-xs text-slate-500">{m.description}</div>}</TableCell>
                  <TableCell className={m.isLate ? "font-medium text-rose-700" : ""}>{m.plannedDate ?? "—"}{m.isLate ? " (late)" : ""}</TableCell>
                  <TableCell>{m.completedDate ? <span className="flex items-center gap-1 text-emerald-700"><CheckCircle2 className="h-4 w-4" />{m.completedDate}</span> : "—"}</TableCell>
                  <TableCell>{MS_STATUS.find((s) => s.value === m.status)?.label}</TableCell>
                  <TableCell>{m.responsibleName ?? "—"}</TableCell>
                  <TableCell className="text-right">{m.amount != null ? fmt(m.amount) : "—"}{m.billingReference && <div className="text-xs text-slate-500">{m.billingReference}</div>}</TableCell>
                  <TableCell className="whitespace-nowrap text-right">{canEdit && <>
                    <Button variant="ghost" size="sm" onClick={() => setEdit({ ...m })}><Pencil className="h-4 w-4" /></Button>
                    <Button variant="ghost" size="sm" onClick={() => remove(m)}><Trash2 className="h-4 w-4" /></Button></>}</TableCell>
                </TableRow>
              ))}</TableBody></Table>
          )}
      </CardContent>

      <Dialog open={!!edit} onOpenChange={(v) => !v && setEdit(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>{edit?.milestoneId ? "Edit milestone" : "Add milestone"}</DialogTitle></DialogHeader>
          {edit && (
            <div className="grid gap-3 md:grid-cols-2">
              <div className="space-y-1 md:col-span-2"><Label>Name</Label>
                <Input list="ms-suggest" value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} />
                <datalist id="ms-suggest">{SUGGESTED.map((s) => <option key={s} value={s} />)}</datalist></div>
              <div className="space-y-1"><Label>Planned date</Label><Input type="date" value={edit.plannedDate ?? ""} onChange={(e) => setEdit({ ...edit, plannedDate: e.target.value })} /></div>
              <div className="space-y-1"><Label>Status</Label>
                <Select value={edit.status ?? "Planned"} onValueChange={(v) => setEdit({ ...edit, status: v as MilestoneStatus })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{MS_STATUS.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
                </Select></div>
              {edit.status === "Completed" && <div className="space-y-1"><Label>Completed on</Label><Input type="date" value={edit.completedDate ?? ""} onChange={(e) => setEdit({ ...edit, completedDate: e.target.value })} /></div>}
              <div className="space-y-1"><Label>Responsible</Label>
                <Select value={edit.responsibleStaffId ? String(edit.responsibleStaffId) : "none"} onValueChange={(v) => setEdit({ ...edit, responsibleStaffId: v === "none" ? null : Number(v) })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent><SelectItem value="none">No one</SelectItem>{staff.map((s) => <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>{`${s.firstName} ${s.lastName}`}</SelectItem>)}</SelectContent>
                </Select></div>
              <div className="space-y-1"><Label>Amount (optional)</Label><NumberInput min={0} value={edit.amount ?? ""} onChange={(e: any) => setEdit({ ...edit, amount: e.target.value === "" ? null : Number(e.target.value) })} /></div>
              <div className="space-y-1"><Label>Billing reference</Label><Input value={edit.billingReference ?? ""} onChange={(e) => setEdit({ ...edit, billingReference: e.target.value })} /></div>
              <div className="space-y-1 md:col-span-2"><Label>Description / notes</Label><Textarea rows={2} value={edit.description ?? ""} onChange={(e) => setEdit({ ...edit, description: e.target.value })} /></div>
            </div>
          )}
          <DialogFooter><Button variant="outline" onClick={() => setEdit(null)}>Cancel</Button><Button onClick={save} disabled={!edit?.name.trim()}>Save</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  )
}

// ---------------------------------------------------------------- scoped cash flow (Cash Flow page filter)

/** The Cash Flow page with a Project / Contract filter: actual money for that scope, from the cash ledger. */
export function ScopedCashPanel({ project, fromDate, toDate }: { project: string; fromDate?: string; toDate?: string }) {
  const [cash, setCash] = useState<ProjectCashFlow | null>(null)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => {
    let alive = true
    setCash(null); setError(null)
    getScopedCashFlow(project, { fromDate, toDate })
      .then((c) => { if (alive) setCash(c) })
      .catch((e) => { if (alive) setError(e?.message ?? String(e)) })
    return () => { alive = false }
  }, [project, fromDate, toDate])
  if (error) return <p className="text-sm text-rose-600">{error}</p>
  if (!cash) return <div className="py-10 text-center"><Loader2 className="mx-auto h-5 w-5 animate-spin text-slate-400" /></div>
  return (
    <div className="space-y-3">
      <p className="text-sm text-slate-600">
        Money that moved for {project === "general" ? "work not assigned to any project" : "the selected project(s)"} in this period.
        Transfers between your own accounts are left out. Switch back to <b>All projects</b> for the full company statement.
      </p>
      <CashTab cash={cash} />
    </div>
  )
}

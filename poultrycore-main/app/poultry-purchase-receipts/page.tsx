"use client"

// Purchase Receipts (migration 345) -- the home of Receive Purchase.
//
// A receipt is one supplier invoice: its items became stock lots (the cost
// layers FIFO/LIFO/HIFO draw from), its unpaid part is a supplier balance, and
// anything paid on the spot is one supplier payment. This page lists them,
// opens one, and reverses one -- append-only: the lots, payment and allocation
// rows stay, an opposite stock adjustment is written, and the receipt reads
// Reversed. Paying a balance later happens where every supplier balance is
// paid: Supplier Balances.
//
// ?receive=1 opens the Receive Purchase form straight away (nav deep link).

import { Suspense, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { Loader2, Lock, PackageCheck, RefreshCw, Undo2 } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { MobileCardList, HIGHLIGHT_TONES } from "@/components/ui/mobile-card-list"
import { ListFilters } from "@/components/ui/list-filters"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { usePagination } from "@/hooks/use-pagination"
import { usePermissions } from "@/hooks/use-permissions"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { getUserContext } from "@/lib/utils/user-context"
import { currentCompanyTimeZone, fmtDateTime, fmtInstant } from "@/lib/utils/company-datetime"
import { listPoultryRawMaterialItems, type PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { getSuppliers, type Supplier } from "@/lib/api/supplier"
import {
  getPurchaseReceipt, listPurchaseReceipts, reversePurchaseReceipt,
  type PurchaseReceipt, type PurchaseReceiptPaymentStatus,
} from "@/lib/api/poultry-purchase-receipts"
import { ReceivePurchaseDialog } from "@/components/poultry/receive-purchase-dialog"

const day = (v: string | null | undefined) => (v ? v.slice(0, 10) : "—")

/** The company's business date, yyyy-mm-dd (en-CA formats as ISO). */
function companyToday(): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: currentCompanyTimeZone() }).format(new Date())
  } catch {
    return new Date().toISOString().slice(0, 10)
  }
}

const STATUS_TONE: Record<PurchaseReceiptPaymentStatus, string> = {
  Paid: "bg-emerald-100 text-emerald-800 border-emerald-300",
  "Part paid": "bg-amber-100 text-amber-800 border-amber-300",
  Unpaid: "bg-rose-100 text-rose-800 border-rose-300",
  Reversed: "bg-slate-100 text-slate-600 border-slate-300",
}

function StatusBadge({ r }: { r: PurchaseReceipt }) {
  return (
    <span className="inline-flex items-center gap-1">
      <Badge variant="outline" className={STATUS_TONE[r.paymentStatus]}>{r.paymentStatus}</Badge>
      {r.isOverdue && <Badge variant="outline" className="bg-rose-50 text-rose-700 border-rose-300">Overdue</Badge>}
    </span>
  )
}

function PurchaseReceiptsInner() {
  const router = useRouter()
  const params = useSearchParams()
  const { toast } = useToast()
  const logout = useLogout()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const canView = permissions.can("poultry.purchase-receipts.view")
  const canReceive = permissions.can("poultry.purchase-receipts.create")
  const canReverse = permissions.can("poultry.purchase-receipts.approve")
  const canPay = permissions.can("poultry.supplier-payments.create")

  const [rows, setRows] = useState<PurchaseReceipt[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [status, setStatus] = useState<"All" | "Open" | "Paid" | "Reversed">("All")
  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])
  const [receiveOpen, setReceiveOpen] = useState(false)
  const [detail, setDetail] = useState<PurchaseReceipt | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [reversing, setReversing] = useState<PurchaseReceipt | null>(null)
  const today = useMemo(() => companyToday(), [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    void loadLookups()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  useEffect(() => {
    if (params.get("receive") === "1" && canReceive) setReceiveOpen(true)
  }, [params, canReceive])

  async function load() {
    setLoading(true)
    try {
      setRows(await listPurchaseReceipts())
    } catch (e: any) {
      toast({ title: "Could not load purchase receipts", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  async function loadLookups() {
    const { farmId, userId } = getUserContext()
    const [it, ca, sup] = await Promise.all([
      listPoultryRawMaterialItems().catch(() => [] as PoultryRawMaterialItem[]),
      listPoultryCashAccounts().catch(() => [] as PoultryCashAccount[]),
      farmId && userId ? getSuppliers(userId, farmId) : Promise.resolve({ success: false, data: [] as Supplier[] }),
    ])
    setItems(it); setCashAccounts(ca)
    setSuppliers((sup.success && sup.data) ? [...sup.data].sort((a, b) => a.name.localeCompare(b.name)) : [])
  }

  async function openDetail(id: number) {
    setDetailLoading(true)
    setDetail(rows.find((r) => r.poultryPurchaseReceiptId === id) ?? null)
    try {
      setDetail(await getPurchaseReceipt(id))
    } catch (e: any) {
      toast({ title: "Could not open the receipt", description: e?.message, variant: "destructive" })
    } finally {
      setDetailLoading(false)
    }
  }

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((r) => {
      if (status === "Open" && !(r.status === "Posted" && r.balance > 0)) return false
      if (status === "Paid" && r.paymentStatus !== "Paid") return false
      if (status === "Reversed" && r.status !== "Reversed") return false
      if (!q) return true
      return [r.receiptNumber, r.supplierName, r.referenceNo, r.itemSummary].some((v) => (v ?? "").toLowerCase().includes(q))
    })
  }, [rows, search, status])
  const pg = usePagination(filtered)

  const posted = rows.filter((r) => r.status === "Posted")
  const outstanding = posted.reduce((s, r) => s + r.balance, 0)
  const overdue = posted.filter((r) => r.isOverdue).reduce((s, r) => s + r.balance, 0)
  const awaitingPl = posted.reduce((s, r) => s + r.deferredCost, 0)

  if (!permissions.isLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-4 md:p-6">
            <Card><CardContent className="p-8 text-center text-slate-600">
              <Lock className="mx-auto mb-2 h-6 w-6 text-slate-400" />
              You do not have access to Purchase Receipts.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <PackageCheck className="h-6 w-6 text-emerald-600" /> Purchase Receipts
              </h1>
              <p className="text-sm text-slate-600 max-w-2xl">
                Receive a supplier invoice in one step: the stock, what you owe and anything paid now.
                Balances are paid later from <Link href="/supplier-balances" className="text-blue-700 hover:underline">Supplier Balances</Link>.
              </p>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => void load()} disabled={loading} className="h-10">
                <RefreshCw className={loading ? "h-4 w-4 mr-1 animate-spin" : "h-4 w-4 mr-1"} /> Refresh
              </Button>
              {canReceive && (
                <Button className="h-10" onClick={() => setReceiveOpen(true)}>
                  <PackageCheck className="h-4 w-4 mr-1" /> Receive purchase
                </Button>
              )}
            </div>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <Tile label="Receipts" value={posted.length.toLocaleString()} />
            <Tile label="Owed to suppliers" value={gh(outstanding)} tone="amber" />
            <Tile label="Overdue" value={gh(overdue)} tone={overdue > 0 ? "rose" : undefined} />
            <Tile label="Held as stock until used" value={gh(awaitingPl)} tone="violet" />
          </div>

          <div className="flex flex-col sm:flex-row gap-2 sm:items-center">
            <div className="flex-1">
              <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search receipt, supplier, invoice or item" />
            </div>
            <Select value={status} onValueChange={(v) => setStatus(v as typeof status)}>
              <SelectTrigger className="sm:w-44 h-10"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="All">All receipts</SelectItem>
                <SelectItem value="Open">With a balance</SelectItem>
                <SelectItem value="Paid">Paid</SelectItem>
                <SelectItem value="Reversed">Reversed</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : filtered.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  {rows.length === 0 ? "No purchase has been received yet." : "Nothing matches these filters."}
                </div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.poultryPurchaseReceiptId}
                  primary={(r) => <button className="text-left text-blue-700" onClick={() => void openDetail(r.poultryPurchaseReceiptId)}>{r.receiptNumber} · {r.supplierName}</button>}
                  secondary={(r) => <span>{fmtDateTime(r.purchaseDate, r)}{r.referenceNo ? ` · Inv ${r.referenceNo}` : ""}</span>}
                  trailing={(r) => <StatusBadge r={r} />}
                  highlights={(r) => [
                    { label: "Total", value: gh(r.totalCost), accent: "slate" },
                    { label: "Balance", value: gh(r.balance), accent: r.balance > 0 ? "amber" : "emerald" },
                  ]}
                  details={(r) => [
                    { label: "Items", value: r.itemSummary || "—" },
                    { label: "Paid", value: gh(r.amountPaid) },
                    { label: "Due", value: r.balance > 0 ? day(r.dueDate) : "—" },
                  ]}
                  actions={(r) => (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => void openDetail(r.poultryPurchaseReceiptId)}>Open</Button>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Receipt</TableHead><TableHead>Date</TableHead><TableHead>Supplier</TableHead>
                            <TableHead>Invoice</TableHead><TableHead>Items</TableHead>
                            <TableHead className="text-right">Total</TableHead><TableHead className="text-right">Paid</TableHead>
                            <TableHead className="text-right">Balance</TableHead><TableHead>Status</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r) => (
                            <TableRow key={r.poultryPurchaseReceiptId} className={cn("cursor-pointer", r.status === "Reversed" && "text-slate-400")}
                              onClick={() => void openDetail(r.poultryPurchaseReceiptId)}>
                              <TableCell className="font-medium text-blue-700">{r.receiptNumber}</TableCell>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(r.purchaseDate, r)}</TableCell>
                              <TableCell>{r.supplierName}</TableCell>
                              <TableCell>{r.referenceNo || "—"}</TableCell>
                              <TableCell className="max-w-[220px] truncate" title={r.itemSummary ?? ""}>{r.itemSummary}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.totalCost)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.amountPaid)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{gh(r.balance)}</TableCell>
                              <TableCell><StatusBadge r={r} /></TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <ReceivePurchaseDialog
        open={receiveOpen}
        onOpenChange={(o) => {
          setReceiveOpen(o)
          if (!o && params.get("receive") === "1") router.replace("/poultry-purchase-receipts")
        }}
        items={items}
        suppliers={suppliers}
        cashAccounts={cashAccounts}
        today={today}
        canPay={canPay}
        onReceived={async (r) => {
          await Promise.all([load(), loadLookups()])
          void openDetail(r.poultryPurchaseReceiptId)
        }}
      />

      <ReceiptDetailDialog
        receipt={detail}
        loading={detailLoading}
        canReverse={canReverse}
        onClose={() => setDetail(null)}
        onReverse={(r) => setReversing(r)}
      />

      <PromptDialog
        open={reversing != null}
        onOpenChange={(o) => { if (!o) setReversing(null) }}
        title={reversing ? `Reverse ${reversing.receiptNumber}?` : "Reverse receipt"}
        description={
          <span>
            The stock comes back out, any payment made on this receipt is reversed and its cash returns to the account,
            and the supplier no longer owes anything for it. Nothing is deleted: the receipt stays here marked Reversed.
          </span>
        }
        label="Reason"
        placeholder="e.g. Entered against the wrong supplier"
        confirmLabel="Reverse receipt"
        confirmVariant="destructive"
        onSubmit={async (reason) => {
          if (!reversing) return
          try {
            const res = await reversePurchaseReceipt(reversing.poultryPurchaseReceiptId, reason)
            toast({ title: `${reversing.receiptNumber} reversed`, description: `${res.linesReversed} item${res.linesReversed === 1 ? "" : "s"} taken back out of stock.` })
            setReversing(null)
            if (res.receipt) setDetail(res.receipt)
            await load()
          } catch (e: any) {
            toast({ title: "Could not reverse the receipt", description: e?.message, variant: "destructive" })
            throw e
          }
        }}
      />
    </div>
  )
}

function Tile({ label, value, tone }: { label: string; value: string; tone?: "amber" | "rose" | "violet" }) {
  const t = tone ? HIGHLIGHT_TONES[tone] : null
  return (
    <div className={cn("rounded-lg border px-3 py-2 shadow-sm", t ? t.tile : "bg-white border-slate-200")}>
      <div className={cn("text-xs", t ? t.label : "text-slate-500")}>{label}</div>
      <div className={cn("text-xl font-semibold tabular-nums", t ? t.value : "text-slate-900")}>{value}</div>
    </div>
  )
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return <div className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">{children}</div>
}

function Figure({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-md border border-slate-200 bg-white p-2.5">
      <div className="text-[11px] leading-tight text-slate-500">{label}</div>
      <div className="text-base font-semibold tabular-nums leading-snug">{value}</div>
    </div>
  )
}

function ReceiptDetailDialog({
  receipt, loading, canReverse, onClose, onReverse,
}: {
  receipt: PurchaseReceipt | null
  loading: boolean
  canReverse: boolean
  onClose: () => void
  onReverse: (r: PurchaseReceipt) => void
}) {
  const gh = useFmt()
  const r = receipt
  return (
    <Dialog open={r != null} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        {r && (
          <>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><PackageCheck className="h-5 w-5 text-emerald-600" /> {r.receiptNumber} <StatusBadge r={r} /></DialogTitle>
              <DialogDescription>
                {r.supplierName} · {fmtDateTime(r.purchaseDate, r)}{r.referenceNo ? ` · Invoice ${r.referenceNo}` : ""}
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <section className="space-y-2">
                <SectionLabel>Money</SectionLabel>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                  <Figure label="Total" value={gh(r.totalCost)} />
                  <Figure label="Paid" value={gh(r.amountPaid)} />
                  <Figure label="Balance" value={gh(r.balance)} />
                  <Figure label="Due" value={r.balance > 0 ? day(r.dueDate) || "Supplier terms" : "—"} />
                </div>
                <div className="text-xs text-slate-600 space-y-0.5">
                  {r.additionalCosts > 0 && <div>Includes {gh(r.additionalCosts)} additional costs{r.additionalCostsNote ? ` (${r.additionalCostsNote})` : ""}, spread over the items.</div>}
                  {r.amountPaidAtReceipt > 0 && (
                    <div>
                      {gh(r.amountPaidAtReceipt)} paid on receipt from {r.cashAccountName ?? "a cash account"}{r.paymentMethod ? ` (${r.paymentMethod})` : ""}
                      {r.poultrySupplierPaymentId ? <> — supplier payment #{r.poultrySupplierPaymentId}</> : null}.
                    </div>
                  )}
                  {r.expensedAtPurchaseCost > 0 && <div>{gh(r.expensedAtPurchaseCost)} of items are expensed as they are paid.</div>}
                  {r.deferredCost > 0 && <div>{gh(r.deferredCost)} of items reach Profit &amp; Loss only when used.</div>}
                  {r.status === "Posted" && r.balance > 0 && (
                    <div>Pay the balance from <Link href="/supplier-balances" className="text-blue-700 hover:underline">Supplier Balances</Link>.</div>
                  )}
                </div>
              </section>

              <section className="space-y-2">
                <SectionLabel>Items {loading && <Loader2 className="inline h-3 w-3 animate-spin" />}</SectionLabel>
                {(r.lines ?? []).map((l) => (
                  <div key={l.poultryPurchaseReceiptLineId} className="rounded-md border p-3 space-y-1">
                    <div className="flex items-start justify-between gap-2">
                      <div className="font-medium text-slate-800">{l.itemName}</div>
                      <div className="font-semibold tabular-nums">{gh(l.lineTotal)}</div>
                    </div>
                    <div className="text-xs text-slate-600">
                      {l.quantity.toLocaleString()} × {gh(l.unitCost)}
                      {l.allocatedAdditionalCost > 0 && <> + {gh(l.allocatedAdditionalCost)} additional · landed {gh(l.landedUnitCost)}</>}
                      {l.productionUnitsPerPurchaseUnit && l.productionUnitsPerPurchaseUnit !== 1
                        ? <> · {l.productionQuantity.toLocaleString()} {l.unitOfMeasure ?? ""} into stock</> : null}
                    </div>
                    <div className="flex flex-wrap gap-1.5 text-xs">
                      <Badge variant="outline">{l.recognitionLabel}</Badge>
                      {r.status === "Posted" && l.consumedQuantity > 0 && <Badge variant="outline" className="border-amber-300 text-amber-800">{l.consumedQuantity.toLocaleString()} used</Badge>}
                      {r.status === "Posted" && l.balance > 0 && <Badge variant="outline" className="border-amber-300 text-amber-800">{gh(l.balance)} owed</Badge>}
                    </div>
                  </div>
                ))}
              </section>

              {r.notes && (
                <section className="space-y-1">
                  <SectionLabel>Notes</SectionLabel>
                  <p className="text-sm text-slate-700 whitespace-pre-wrap">{r.notes}</p>
                </section>
              )}

              <section className="space-y-2">
                <SectionLabel>Reversal</SectionLabel>
                {r.status === "Reversed" ? (
                  <p className="text-sm text-slate-600">
                    Reversed {fmtInstant(r.reversedAt ?? null)}{r.reversalReason ? ` — ${r.reversalReason}` : ""}. The stock was taken back
                    out with an opposite adjustment; the lots and the payment remain in the history.
                  </p>
                ) : r.reversalBlocker ? (
                  <p className="text-sm text-amber-800 rounded-md border border-amber-200 bg-amber-50 p-2.5">
                    Can&apos;t be reversed yet: {r.reversalBlocker}
                  </p>
                ) : canReverse ? (
                  <Button variant="outline" className="text-rose-700 border-rose-300" onClick={() => onReverse(r)}>
                    <Undo2 className="h-4 w-4 mr-1" /> Reverse receipt
                  </Button>
                ) : (
                  <p className="text-sm text-slate-500">You don&apos;t have permission to reverse receipts.</p>
                )}
              </section>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}

export default function PurchaseReceiptsPage() {
  return (
    <Suspense fallback={null}>
      <PurchaseReceiptsInner />
    </Suspense>
  )
}

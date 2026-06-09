"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import {
  ArrowLeft, Loader2, Truck, Receipt, Users, Package, Coins,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterDriverReturns, listWaterVehicleLoadings,
  listWaterVehicleLoadingItems, listWaterDriverReturnItems,
  listWaterDriverReturnCustomerSales, listWaterDriverReturnExpenses,
  type WaterDriverReturn, type WaterVehicleLoading,
  type WaterVehicleLoadingItem, type WaterDriverReturnItem,
  type WaterDriverReturnCustomerSaleRow, type WaterDeliveryExpense,
} from "@/lib/api/water"
import { useFmt, useCurrency } from "@/lib/currency"

const LOAD_STATUS: Record<string, string> = {
  Loaded: "bg-blue-100 text-blue-700",
  Returned: "bg-amber-100 text-amber-700",
  Reconciled: "bg-green-100 text-green-700",
  Cancelled: "bg-slate-100 text-slate-700",
  Draft: "bg-slate-100 text-slate-600",
  Approved: "bg-green-100 text-green-700",
}

export default function WaterDeliveryRunDetailsPage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const gh = useFmt()
  // Column-header / Stat-card unit suffix. Hardcoding " (GHC)" leaked the
  // currency symbol even when the user toggled "Show currency symbol" off in
  // setup (and was always wrong when the currency wasn't GHC). Drive it from
  // the same store fmtMoney reads so labels and values flip together.
  const { symbol, showSymbol } = useCurrency()
  // James (2026-05-30): currency symbols belong on the *values* (driven by
  // fmtMoney + the showCurrencySymbol toggle), never duplicated into the
  // column header. Force empty so headers stay clean regardless of toggle.
  const cur = ""

  // The :id segment is a WaterVehicleLoadingId — that's the canonical "delivery
  // run" identifier. The return (if any) links back via its WaterVehicleLoadingId.
  const loadingId = Number(params?.id)

  const [loading, setLoading] = useState<WaterVehicleLoading | null>(null)
  const [items, setItems] = useState<WaterVehicleLoadingItem[]>([])
  const [ret, setRet] = useState<WaterDriverReturn | null>(null)
  const [retItems, setRetItems] = useState<WaterDriverReturnItem[]>([])
  const [customerSales, setCustomerSales] = useState<WaterDriverReturnCustomerSaleRow[]>([])
  const [expenses, setExpenses] = useState<WaterDeliveryExpense[]>([])
  const [busy, setBusy] = useState(true)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Water") { router.replace("/dashboard"); return }
    if (!loadingId || Number.isNaN(loadingId)) { router.replace("/water-driver-returns"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, loadingId])

  async function load() {
    setBusy(true)
    try {
      // No direct getById on the list endpoints — pull all and filter.
      // Cheap given the dev datasets; can be replaced with /vehicle-loadings/{id}
      // direct fetch later if needed.
      const [allLoadings, allReturns, loadingItems] = await Promise.all([
        listWaterVehicleLoadings(),
        listWaterDriverReturns(),
        listWaterVehicleLoadingItems(loadingId).catch(() => []),
      ])
      const l = allLoadings.find(x => x.waterVehicleLoadingId === loadingId)
      if (!l) {
        toast({ title: "Delivery run not found", description: `Delivery run #${loadingId} not found in the list. It may have been deleted.`, variant: "destructive" })
        setLoading(null)
        return
      }
      setLoading(l)
      setItems(loadingItems)

      const r = allReturns.find(x => x.waterVehicleLoadingId === loadingId)
      setRet(r ?? null)
      if (r) {
        const [ri, cs, ex] = await Promise.all([
          listWaterDriverReturnItems(r.waterDriverReturnId).catch(() => []),
          listWaterDriverReturnCustomerSales(r.waterDriverReturnId).catch(() => []),
          listWaterDriverReturnExpenses(r.waterDriverReturnId).catch(() => []),
        ])
        setRetItems(ri); setCustomerSales(cs); setExpenses(ex)
      } else {
        setRetItems([]); setCustomerSales([]); setExpenses([])
      }
    } catch (e: any) {
      toast({ title: "Could not load delivery run", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  // Derived display values. "Cost / bag" not relevant for delivery; we surface
  // bag accounting + cash reconciliation.
  const totalExpectedCash = useMemo(
    () => items.reduce((s, it) => s + (it.expectedAmount ?? it.bagsLoaded * it.unitPrice), 0) || (loading?.expectedCash ?? 0),
    [items, loading],
  )
  const totalCollected =
    (ret?.cashCollected ?? 0) + (ret?.moMoCollected ?? 0) + (ret?.bankCollected ?? 0) + (ret?.creditSalesAmount ?? 0)
  const expensesTotal = expenses.filter(e => e.isApproved).reduce((s, e) => s + e.amount, 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center gap-2">
            <Link href="/water-driver-returns">
              <Button variant="ghost" size="sm" className="gap-1">
                <ArrowLeft className="h-4 w-4" /> Back to Deliveries
              </Button>
            </Link>
          </div>

          {busy ? (
            <Card><CardContent className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading delivery run…</CardContent></Card>
          ) : !loading ? (
            <Card><CardContent className="p-6 text-slate-500">Delivery run not found.</CardContent></Card>
          ) : (
            <>
              {/* Header */}
              <div className="mb-4 flex items-start gap-3">
                <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                  <Truck className="h-5 w-5 text-sky-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-semibold text-slate-900">
                    Delivery run #{loading.waterVehicleLoadingId}
                  </h1>
                  <div className="text-xs sm:text-sm text-slate-500 flex flex-wrap gap-2">
                    <Badge className={LOAD_STATUS[loading.status] ?? ""}>{loading.status}</Badge>
                    <span>{loading.loadDate.split("T")[0]}</span>
                    {loading.driverName && <span>· Driver: <strong>{loading.driverName}</strong></span>}
                    {loading.vehicleName && <span>· {loading.vehicleName}</span>}
                    {loading.routeName && <span>· {loading.routeName}</span>}
                  </div>
                </div>
              </div>

              {/* Summary cards */}
              <div className="mb-4 grid grid-cols-2 md:grid-cols-4 gap-3">
                <SummaryCard label="Total loaded (bags)" value={items.reduce((s, it) => s + it.bagsLoaded, 0).toLocaleString() || String(loading.bagsLoaded)} />
                <SummaryCard label={`Expected${cur}`} value={gh(totalExpectedCash)} />
                <SummaryCard label={`Collected${cur}`} value={ret ? gh(totalCollected) : "—"} />
                <SummaryCard
                  label={(ret?.shortageAmount ?? 0) > 0 ? `Shortage${cur}` : `Overage${cur}`}
                  value={ret ? gh((ret.shortageAmount ?? 0) > 0 ? (ret.shortageAmount ?? 0) : (ret.overageAmount ?? 0)) : "—"}
                  tone={(ret?.shortageAmount ?? 0) > 0 ? "rose" : "green"}
                />
              </div>

              {/* Products loaded */}
              <Section title="Products loaded" icon={<Package className="h-4 w-4 text-slate-500" />}>
                {items.length === 0 ? (
                  <Empty>No item rows. Legacy single-product loading.</Empty>
                ) : (
                  <MobileCardList
                    items={items}
                    getKey={(it) => it.waterVehicleLoadingItemId}
                    primary={(it) => it.productName ?? `Product #${it.waterProductId}`}
                    secondary={(it) => <span>{it.bagsLoaded} bags · {gh(it.expectedAmount ?? it.bagsLoaded * it.unitPrice)}</span>}
                    details={(it) => [
                      { label: "Loaded (bags)", value: it.bagsLoaded },
                      { label: `Unit price${cur}`, value: gh(it.unitPrice) },
                      { label: `Expected${cur}`, value: gh(it.expectedAmount ?? it.bagsLoaded * it.unitPrice) },
                    ]}
                    desktopTable={
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Product</TableHead>
                            <TableHead className="text-right">Loaded (bags)</TableHead>
                            <TableHead className="text-right">Unit price{cur}</TableHead>
                            <TableHead className="text-right">Expected{cur}</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {items.map(it => (
                            <TableRow key={it.waterVehicleLoadingItemId}>
                              <TableCell className="font-medium">{it.productName ?? `Product #${it.waterProductId}`}</TableCell>
                              <TableCell className="text-right tabular-nums">{it.bagsLoaded}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(it.unitPrice)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(it.expectedAmount ?? it.bagsLoaded * it.unitPrice)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    }
                  />
                )}
              </Section>

              {/* Prompt 2 Part 1 §2 — explicit reversal history banner.
                  spWaterDriverReturn_Reverse stamps the Notes field with
                  "Reversed by X. Reason: Y" — surface it visibly instead of
                  burying it in the audit-trail card. */}
              {ret?.notes && /reversed by/i.test(ret.notes) && (
                <Card className="mb-4 border-amber-200 bg-amber-50">
                  <CardContent className="p-3 text-sm text-amber-900">
                    <div className="font-semibold mb-1">Reversal history</div>
                    <pre className="whitespace-pre-wrap text-xs font-mono">{ret.notes}</pre>
                  </CardContent>
                </Card>
              )}

              {/* Return summary + per-product reconciliation */}
              {ret ? (
                <>
                  <Section title="Return reconciliation" icon={<Receipt className="h-4 w-4 text-slate-500" />}>
                    <div className="mb-3 text-xs text-slate-600">
                      <Badge className={LOAD_STATUS[ret.status ?? ""] ?? ""}>{ret.status}</Badge>
                      <span className="ml-2">Return date: {ret.returnDate.split("T")[0]}</span>
                      {ret.approvedBy && <span className="ml-2">· Approved by {ret.approvedBy}</span>}
                      {ret.approvedAt && <span className="ml-2">at {ret.approvedAt.split(".")[0].replace("T", " ")}</span>}
                    </div>
                    {retItems.length > 0 ? (
                      <MobileCardList
                        items={retItems}
                        getKey={(ri) => ri.waterDriverReturnItemId}
                        primary={(ri) => ri.productName ?? `Product #${ri.waterProductId}`}
                        secondary={(ri) => <span>Sold {ri.bagsSold} · {gh(ri.expectedSales ?? ri.bagsSold * ri.unitPrice)}</span>}
                        details={(ri) => [
                          { label: "Loaded", value: ri.bagsLoaded },
                          { label: "Sold", value: ri.bagsSold },
                          { label: "Returned", value: ri.bagsReturned },
                          { label: "Damaged", value: ri.bagsDamaged },
                          { label: `Unit price${cur}`, value: gh(ri.unitPrice) },
                          { label: `Sales${cur}`, value: gh(ri.expectedSales ?? ri.bagsSold * ri.unitPrice) },
                        ]}
                        desktopTable={
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Product</TableHead>
                                <TableHead className="text-right">Loaded</TableHead>
                                <TableHead className="text-right">Sold</TableHead>
                                <TableHead className="text-right">Returned</TableHead>
                                <TableHead className="text-right">Damaged</TableHead>
                                <TableHead className="text-right">Unit price{cur}</TableHead>
                                <TableHead className="text-right">Sales{cur}</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {retItems.map(ri => (
                                <TableRow key={ri.waterDriverReturnItemId}>
                                  <TableCell className="font-medium">{ri.productName ?? `Product #${ri.waterProductId}`}</TableCell>
                                  <TableCell className="text-right tabular-nums">{ri.bagsLoaded}</TableCell>
                                  <TableCell className="text-right tabular-nums">{ri.bagsSold}</TableCell>
                                  <TableCell className="text-right tabular-nums">{ri.bagsReturned}</TableCell>
                                  <TableCell className="text-right tabular-nums">{ri.bagsDamaged}</TableCell>
                                  <TableCell className="text-right tabular-nums">{gh(ri.unitPrice)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{gh(ri.expectedSales ?? ri.bagsSold * ri.unitPrice)}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        }
                      />
                    ) : (
                      <div className="text-xs text-slate-500">Legacy single-product return — totals: sold {ret.bagsSold}, returned {ret.bagsReturned}, damaged {ret.bagsDamaged}.</div>
                    )}

                    {/* Payments collected */}
                    <div className="border-t mt-3 pt-3 grid grid-cols-2 md:grid-cols-5 gap-2 text-sm">
                      <div><span className="text-slate-500">Cash:</span> <span className="font-semibold tabular-nums">{gh(ret.cashCollected)}</span></div>
                      <div><span className="text-slate-500">MoMo:</span> <span className="font-semibold tabular-nums">{gh(ret.moMoCollected)}</span></div>
                      <div><span className="text-slate-500">Bank:</span> <span className="font-semibold tabular-nums">{gh(ret.bankCollected)}</span></div>
                      <div><span className="text-slate-500">Credit:</span> <span className="font-semibold tabular-nums">{gh(ret.creditSalesAmount)}</span></div>
                      <div><span className="text-slate-500">Driver float returned:</span> <span className="font-semibold tabular-nums">{gh(ret.cashReturnedByDriver ?? 0)}</span></div>
                    </div>
                  </Section>

                  {/* Customer breakdown */}
                  <Section title={`Customer sales breakdown (${customerSales.length})`} icon={<Users className="h-4 w-4 text-slate-500" />}>
                    {customerSales.length === 0 ? (
                      <Empty>Summary-only return — no per-customer breakdown was recorded.</Empty>
                    ) : (
                      <div className="space-y-3">
                        {customerSales.map(cs => (
                          <div key={cs.waterDriverReturnCustomerSaleId} className="border rounded-md p-3">
                            <div className="flex items-center justify-between gap-2 mb-2">
                              <div className="font-medium">
                                {cs.customerName ?? cs.customerLabel ?? "Walk-in"}
                              </div>
                              {cs.generatedWaterSaleId ? (
                                <Link
                                  href={`/water-sales?focus=${cs.generatedWaterSaleId}`}
                                  className="text-xs text-sky-700 hover:underline"
                                >
                                  → Sale #{cs.generatedWaterSaleId}
                                </Link>
                              ) : (
                                <span className="text-xs text-slate-500">No sale yet (Draft return)</span>
                              )}
                            </div>
                            {cs.items.length > 0 && (
                              <div className="space-y-1">
                                {cs.items.map(it => (
                                  <div key={it.waterDriverReturnCustomerSaleItemId} className="flex items-center justify-between gap-2 text-sm rounded bg-slate-50 px-2 py-1.5">
                                    <span className="font-medium min-w-0 truncate">{it.productName ?? `Product #${it.waterProductId}`}</span>
                                    <span className="shrink-0 tabular-nums text-slate-600">{it.quantity} × {gh(it.unitPrice)} = <span className="font-semibold text-slate-900">{gh(it.lineTotal)}</span></span>
                                  </div>
                                ))}
                              </div>
                            )}
                            <div className="border-t mt-2 pt-2 text-xs grid grid-cols-2 md:grid-cols-5 gap-2">
                              <div><span className="text-slate-500">Total:</span> <span className="font-semibold tabular-nums">{gh(cs.totalAmount)}</span></div>
                              <div><span className="text-slate-500">Cash:</span> <span className="tabular-nums">{gh(cs.cashPaid)}</span></div>
                              <div><span className="text-slate-500">MoMo:</span> <span className="tabular-nums">{gh(cs.moMoPaid)}</span></div>
                              <div><span className="text-slate-500">Bank:</span> <span className="tabular-nums">{gh(cs.bankPaid)}</span></div>
                              <div>
                                <span className="text-slate-500">Credit:</span>{" "}
                                <span className={`tabular-nums ${cs.creditAmount > 0 ? "text-rose-600 font-semibold" : ""}`}>{gh(cs.creditAmount)}</span>
                              </div>
                            </div>
                            {cs.notes && <div className="text-xs text-slate-600 mt-1 italic">"{cs.notes}"</div>}
                          </div>
                        ))}
                      </div>
                    )}
                  </Section>

                  {/* Expenses */}
                  <Section title={`Delivery expenses (${gh(expensesTotal)})`} icon={<Coins className="h-4 w-4 text-slate-500" />}>
                    {expenses.length === 0 ? (
                      <Empty>No delivery expenses logged.</Empty>
                    ) : (
                      <MobileCardList
                        items={expenses}
                        getKey={(e) => e.waterDeliveryExpenseId}
                        primary={(e) => e.expenseCategory}
                        secondary={(e) => (
                          <>
                            <span>{gh(e.amount)}</span>
                            <Badge className={e.isApproved ? "bg-green-100 text-green-700" : "bg-amber-100 text-amber-700"}>{e.isApproved ? "Approved" : "Pending"}</Badge>
                          </>
                        )}
                        details={(e) => [
                          { label: `Amount${cur}`, value: gh(e.amount) },
                          { label: "Description", value: e.description ?? "—" },
                          { label: "Status", value: e.isApproved ? "Approved" : "Pending" },
                        ]}
                        desktopTable={
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Category</TableHead>
                                <TableHead className="text-right">Amount{cur}</TableHead>
                                <TableHead>Description</TableHead>
                                <TableHead>Status</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {expenses.map(e => (
                                <TableRow key={e.waterDeliveryExpenseId}>
                                  <TableCell>{e.expenseCategory}</TableCell>
                                  <TableCell className="text-right tabular-nums">{gh(e.amount)}</TableCell>
                                  <TableCell className="text-slate-600">{e.description ?? "—"}</TableCell>
                                  <TableCell>
                                    <Badge className={e.isApproved ? "bg-green-100 text-green-700" : "bg-amber-100 text-amber-700"}>
                                      {e.isApproved ? "Approved" : "Pending"}
                                    </Badge>
                                  </TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        }
                      />
                    )}
                  </Section>
                </>
              ) : (
                <Section title="Return reconciliation" icon={<Receipt className="h-4 w-4 text-slate-500" />}>
                  <Empty>No return recorded yet. {loading.status === "Loaded" && "Use the Record Return action on the Deliveries page."}</Empty>
                </Section>
              )}

              {/* Audit trail */}
              <Section title="Audit trail">
                <dl className="grid grid-cols-1 md:grid-cols-2 gap-y-1 gap-x-4 text-sm">
                  <Row label="Loading created" value={loading.loadDate.split("T")[0]} />
                  {loading.driverName && <Row label="Driver" value={loading.driverName} />}
                  {loading.vehicleName && <Row label="Vehicle" value={loading.vehicleName} />}
                  {loading.routeName && <Row label="Route" value={loading.routeName} />}
                  {loading.openingCashWithDriver ? <Row label="Opening cash float" value={gh(loading.openingCashWithDriver)} /> : null}
                  {ret?.createdBy && <Row label="Return created by" value={ret.createdBy} />}
                  {ret?.approvedBy && <Row label="Return approved by" value={ret.approvedBy} />}
                  {ret?.approvedAt && <Row label="Approved at" value={ret.approvedAt.split(".")[0].replace("T", " ")} />}
                  {loading.notes && <Row label="Loading notes" value={loading.notes} />}
                  {ret?.notes && <Row label="Return notes" value={ret.notes} />}
                </dl>
              </Section>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function SummaryCard({ label, value, tone }: { label: string; value: string; tone?: "rose" | "green" }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs text-slate-500">{label}</div>
        <div className={`text-xl font-semibold tabular-nums ${tone === "rose" ? "text-rose-600" : tone === "green" ? "text-emerald-600" : ""}`}>
          {value}
        </div>
      </CardContent>
    </Card>
  )
}

function Section({ title, icon, children }: { title: string; icon?: React.ReactNode; children: React.ReactNode }) {
  return (
    <Card className="mb-4">
      <CardContent className="p-4">
        <div className="mb-3 flex items-center gap-2 font-medium text-slate-800">
          {icon} {title}
        </div>
        <div>{children}</div>
      </CardContent>
    </Card>
  )
}

function Empty({ children }: { children: React.ReactNode }) {
  return <div className="text-xs text-slate-500 py-2">{children}</div>
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <>
      <dt className="text-slate-500">{label}</dt>
      <dd className="text-slate-900 break-words">{value}</dd>
    </>
  )
}

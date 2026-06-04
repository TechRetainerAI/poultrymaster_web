"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { Check, Loader2, Package, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { approvePurchase, getPurchases, type GenericPurchase } from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Cancelled"] as const

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericPurchasesPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const status = sp.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericPurchase[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true)
    try {
      const data = await getPurchases(status === "All" ? null : status)
      setRows(data)
    } catch (e: any) {
      toast({ title: "Could not load purchases", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, status])

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["supplierName", "status", "notes"],
      dateKey: "purchaseDate",
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onApprove = async (id: number) => {
    try {
      await approvePurchase(id)
      toast({ title: `Purchase #${id} approved`, description: "Inventory and cash/supplier balances updated." })
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Package className="h-6 w-6 text-orange-600" /> Purchases
              </h1>
              <p className="text-sm text-slate-500">{rows.length} purchase(s)</p>
            </div>
            <Button asChild className="w-full sm:w-auto h-11 sm:h-10"><Link href="/generic-purchases/new"><Plus className="h-4 w-4 mr-1" />New purchase</Link></Button>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-purchases" : `/generic-purchases?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No purchases yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search supplier, status or notes"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(p) => p.genericPurchaseId}
                  primary={(p) => `#${p.genericPurchaseId} · ${p.supplierName ?? "–"}`}
                  secondary={(p) => (
                    <>
                      <span>{new Date(p.purchaseDate).toLocaleDateString()}</span>
                      {p.invoiceNumber && <><span>·</span><span className="text-xs">Inv {p.invoiceNumber}</span></>}
                    </>
                  )}
                  trailing={(p) => <Badge className={badgeClass(p.status)}>{p.status}</Badge>}
                  details={(p) => [
                    { label: "Date", value: new Date(p.purchaseDate).toLocaleDateString() },
                    { label: "Supplier", value: p.supplierName ?? "–" },
                    { label: "Invoice", value: p.invoiceNumber ?? "–" },
                    { label: "Total", value: fmt(p.totalAmount) },
                    { label: "Paid", value: fmt(p.amountPaid) },
                    { label: "Balance", value: <span className={p.balance > 0 ? "text-rose-700 font-semibold" : ""}>{fmt(p.balance)}</span> },
                  ]}
                  actions={(p) => (
                    <>
                      {p.status === "Draft" && (
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200">
                              <Check className="h-4 w-4 mr-1" /> Approve
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Approve purchase #{p.genericPurchaseId}?</AlertDialogTitle>
                              <AlertDialogDescription>Inventory will go up, cash will go down by the amount paid, and any unpaid balance will be added to the supplier ledger. All atomic.</AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancel</AlertDialogCancel>
                              <AlertDialogAction onClick={() => onApprove(p.genericPurchaseId)}>Approve</AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>#</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Supplier</TableHead>
                          <TableHead>Invoice</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead className="text-right">Paid</TableHead>
                          <TableHead className="text-right">Balance</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((p) => (
                          <TableRow key={p.genericPurchaseId}>
                            <TableCell>#{p.genericPurchaseId}</TableCell>
                            <TableCell>{new Date(p.purchaseDate).toLocaleDateString()}</TableCell>
                            <TableCell>{p.supplierName ?? "–"}</TableCell>
                            <TableCell>{p.invoiceNumber ?? "–"}</TableCell>
                            <TableCell className="text-right">{fmt(p.totalAmount)}</TableCell>
                            <TableCell className="text-right">{fmt(p.amountPaid)}</TableCell>
                            <TableCell className={`text-right ${p.balance > 0 ? "text-rose-700 font-semibold" : ""}`}>{fmt(p.balance)}</TableCell>
                            <TableCell><Badge className={badgeClass(p.status)}>{p.status}</Badge></TableCell>
                            <TableCell>
                              {p.status === "Draft" && (
                                <AlertDialog>
                                  <AlertDialogTrigger asChild>
                                    <Button size="sm" variant="default" className="bg-emerald-600 hover:bg-emerald-700"><Check className="h-3 w-3 mr-1" />Approve</Button>
                                  </AlertDialogTrigger>
                                  <AlertDialogContent>
                                    <AlertDialogHeader>
                                      <AlertDialogTitle>Approve purchase #{p.genericPurchaseId}?</AlertDialogTitle>
                                      <AlertDialogDescription>Inventory will go up, cash will go down by the amount paid, and any unpaid balance will be added to the supplier ledger. All atomic.</AlertDialogDescription>
                                    </AlertDialogHeader>
                                    <AlertDialogFooter>
                                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                                      <AlertDialogAction onClick={() => onApprove(p.genericPurchaseId)}>Approve</AlertDialogAction>
                                    </AlertDialogFooter>
                                  </AlertDialogContent>
                                </AlertDialog>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

export default function GenericPurchasesPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericPurchasesPageInner />
    </Suspense>
  )
}

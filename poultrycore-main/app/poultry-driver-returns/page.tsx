"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Plus, Loader2, Truck, XCircle, Trash2, ChevronDown, ChevronRight,
  Users2, MapPin, Undo2, RefreshCw, Eye, CheckCircle2, Pencil,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  listPoultryVehicleLoadings, createPoultryVehicleLoading, approvePoultryVehicleLoading, voidPoultryVehicleLoading,
  reloadPoultryVehicleLoading,
  listPoultryDriverReturns, createPoultryDriverReturn, approvePoultryDriverReturn, cancelPoultryDriverReturn,
  reversePoultryDriverReturn, uncancelPoultryDriverReturn, deletePoultryDriverReturn,
  listPoultryVehicleLoadingItems, listPoultryDriverReturnItems,
  listPoultryDriverReturnCustomerSales, listPoultryDriverReturnExpenses,
  listPoultryVehicles, listPoultryRoutes, listPoultryDrivers,
  approveReconcilePoultryDriverReturn,
  type PoultryVehicleLoading, type PoultryDriverReturn, type PoultryVehicle, type PoultryRoute,
  type PoultryDriver, type PoultryDriverReturnInput,
} from "@/lib/api/poultry-distribution"
import { listPoultryProducts, ensurePoultryDefaults, type PoultryProduct } from "@/lib/api/poultry-inventory"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { fmtMoney } from "@/lib/currency"

const gh = (n: number) => fmtMoney(n)
// Currency symbols belong on the *values* (driven by fmtMoney + the
// showCurrencySymbol toggle), never duplicated into the column header.
const cur = ""

const LOAD_STATUS: Record<string, string> = {
  Loaded: "bg-blue-100 text-blue-700",
  Returned: "bg-amber-100 text-amber-700",
  Reconciled: "bg-green-100 text-green-700",
  Cancelled: "bg-slate-100 text-slate-700",
}

const EXPENSE_CATEGORIES = ["Fuel", "ChopMoney", "LoadingBoys", "Toll", "Repair", "PhoneCredit", "Other"]
// Display label: split PascalCase so "ChopMoney" → "Chop Money" (value stays raw).
const prettyCategory = (c: string) => c.replace(/([a-z])([A-Z])/g, "$1 $2")

// In-memory shapes for the dialogs. Closer to the UI than the API types.
type LoadItem = {
  poultryProductId: number
  cratesLoaded: number
  unitPrice: number
  eggsPerCrate: number
  notes: string
}

type ReturnItem = {
  poultryProductId: number
  productName: string
  cratesLoaded: number   // snapshot from loading items
  cratesSold: number
  cratesReturned: number
  cratesDamaged: number
  unitPrice: number
}

type BreakdownItem = {
  poultryProductId: number
  quantity: number
  unitPrice: number
}

// No poultry customer master exists — walk-in shops are captured by a free-text
// customerLabel. customerId stays optional/loose for callers that already have
// an id from elsewhere; the UI only edits the label.
type BreakdownRow = {
  customerId: number | null
  customerLabel: string
  cashPaid: number
  moMoPaid: number
  bankPaid: number
  creditAmount: number
  notes: string
  items: BreakdownItem[]
}

type ExpenseRow = {
  expenseCategory: string
  amount: number
  description: string
  isApproved: boolean
}

export default function PoultryDriverReturnsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  // Gate admin-only actions (Delete on a Cancelled return). Staff users see no
  // Delete button; the backend SP also rejects delete on non-Cancelled rows.
  const permissions = usePermissions()

  // Synchronous re-entry locks. State-based "disabled" relies on React
  // re-rendering before the next click registers, which isn't reliable on
  // rapid double-clicks. Refs flip immediately so the second invocation aborts.
  const loadInflight = useRef(false)
  const returnInflight = useRef(false)

  // Confirmation dialog for the Void action on a Loaded delivery row.
  const [voidTarget, setVoidTarget] = useState<PoultryVehicleLoading | null>(null)
  // Reverse Reconciliation — captures the return about to be reversed so the
  // PromptDialog can prompt for a reason.
  const [reverseTarget, setReverseTarget] = useState<PoultryDriverReturn | null>(null)
  // "Edit" on a Reconciled row reuses the Reverse flow (no Update endpoint
  // exists) — after reverse we re-open the Record Return dialog pre-filled with
  // the existing return, the operator changes what they need, Save re-creates.
  const [editAfterReverse, setEditAfterReverse] = useState(false)

  // Styled approve-&-reconcile confirmation (replaces the native window.confirm).
  const [approveTarget, setApproveTarget] = useState<PoultryDriverReturn | null>(null)
  function approveDraftReturn(r: PoultryDriverReturn) {
    setApproveTarget(r)
  }

  async function cancelDraftReturn(r: PoultryDriverReturn) {
    try { await cancelPoultryDriverReturn(r.poultryDriverReturnId); toast({ title: "Return cancelled" }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }
  // Uncancel a Cancelled return so it can be re-approved (Cancelled → Draft).
  async function uncancelDraftReturn(r: PoultryDriverReturn) {
    try { await uncancelPoultryDriverReturn(r.poultryDriverReturnId); toast({ title: "Return uncancelled — back to Draft. Approve to reconcile." }); await load() }
    catch (e: any) { toast({ title: "Uncancel failed", description: e?.message, variant: "destructive" }) }
  }
  // Admin-only hard delete of a Cancelled return.
  const [deleteTarget, setDeleteTarget] = useState<PoultryDriverReturn | null>(null)
  async function performDeleteCancelledReturn(r: PoultryDriverReturn) {
    try { await deletePoultryDriverReturn(r.poultryDriverReturnId); toast({ title: `Cancelled return #${r.poultryDriverReturnId} deleted` }); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  // "Edit" on a Draft return — re-open the Record Return dialog pre-filled with
  // the existing return, and on save replace it (cancel old → create new →
  // delete old) so the operator keeps exactly one active return per loading.
  const editReturnTargetRef = useRef<PoultryDriverReturn | null>(null)
  function openEditReturnDlg(r: PoultryDriverReturn) {
    const l = loadings.find(x => x.poultryVehicleLoadingId === r.poultryVehicleLoadingId)
    if (!l) {
      toast({ title: "Loading not found", description: "Can't find the delivery run this return belongs to.", variant: "destructive" })
      return
    }
    editReturnTargetRef.current = r
    void prefillFromExistingReturn(l, r)
  }

  // Reload — clone this loading into a fresh delivery run (no update SP exists
  // for loadings, so "reload" re-dispatches the same products).
  async function doReload(l: PoultryVehicleLoading) {
    try {
      await reloadPoultryVehicleLoading(l.poultryVehicleLoadingId)
      toast({ title: "Delivery reloaded — a fresh run was created" })
      await load()
    } catch (e: any) {
      toast({ title: "Reload failed", description: e?.message, variant: "destructive" })
    }
  }

  const [loadings, setLoadings] = useState<PoultryVehicleLoading[]>([])
  const [returns, setReturns] = useState<PoultryDriverReturn[]>([])
  const [vehicles, setVehicles] = useState<PoultryVehicle[]>([])
  const [routes, setRoutes] = useState<PoultryRoute[]>([])
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [drivers, setDrivers] = useState<PoultryDriver[]>([])
  const [loading, setLoading] = useState(true)

  // ===== Search/date filters (Active loads + Returns tabs) =====
  const [loadingsSearch, setLoadingsSearch] = useState("")
  const [loadingsDateFrom, setLoadingsDateFrom] = useState("")
  const [loadingsDateTo, setLoadingsDateTo] = useState("")
  const [returnsSearch, setReturnsSearch] = useState("")
  const [returnsDateFrom, setReturnsDateFrom] = useState("")
  const [returnsDateTo, setReturnsDateTo] = useState("")
  const [filterDriver,  setFilterDriver]  = useState<string>("ALL")
  const [filterVehicle, setFilterVehicle] = useState<string>("ALL")
  const [filterRoute,   setFilterRoute]   = useState<string>("ALL")
  const [filterStatus,  setFilterStatus]  = useState<string>("ALL")

  const matchesDropdowns = (row: { poultryDriverId?: number | null, poultryVehicleId?: number | null, poultryRouteId?: number | null, status?: string | null }) => {
    if (filterDriver  !== "ALL" && String(row.poultryDriverId  ?? "") !== filterDriver)  return false
    if (filterVehicle !== "ALL" && String(row.poultryVehicleId ?? "") !== filterVehicle) return false
    if (filterRoute   !== "ALL" && String(row.poultryRouteId   ?? "") !== filterRoute)   return false
    if (filterStatus  !== "ALL" && (row.status ?? "") !== filterStatus)                   return false
    return true
  }

  const visibleLoadings = useMemo(
    () => filterByDateAndSearch(loadings, {
      search: loadingsSearch, dateFrom: loadingsDateFrom, dateTo: loadingsDateTo,
      searchKeys: ["driverName", "vehicleName", "routeName"],
      dateKey: "loadDate",
    }).filter(matchesDropdowns),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [loadings, loadingsSearch, loadingsDateFrom, loadingsDateTo, filterDriver, filterVehicle, filterRoute, filterStatus],
  )

  const visibleReturns = useMemo(
    () => filterByDateAndSearch(returns, {
      search: returnsSearch, dateFrom: returnsDateFrom, dateTo: returnsDateTo,
      searchKeys: ["driverName", "vehicleName", "routeName"],
      dateKey: "returnDate",
    }).filter((r: any) => {
      const parent = loadings.find(l => l.poultryVehicleLoadingId === r.poultryVehicleLoadingId)
      return matchesDropdowns({
        poultryDriverId:  parent?.poultryDriverId,
        poultryVehicleId: parent?.poultryVehicleId,
        poultryRouteId:   parent?.poultryRouteId,
        status:           r.status,
      })
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [returns, loadings, returnsSearch, returnsDateFrom, returnsDateTo, filterDriver, filterVehicle, filterRoute, filterStatus],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pgReturns = usePagination(visibleReturns)

  // ===== Load Vehicle dialog state =====
  const [loadDlg, setLoadDlg] = useState(false)
  const [loadForm, setLoadForm] = useState({
    poultryVehicleId: 0,
    poultryDriverId: 0 as number | 0,
    poultryRouteId: 0,
    openingCashWithDriver: 0,
    notes: "",
    loadDate: new Date().toISOString().split("T")[0],
  })
  const [loadItems, setLoadItems] = useState<LoadItem[]>([])
  const [savingLoad, setSavingLoad] = useState(false)

  // ===== Driver Return dialog state =====
  const [returnDlg, setReturnDlg] = useState<{ open: boolean; loading?: PoultryVehicleLoading }>({ open: false })
  const [returnItems, setReturnItems] = useState<ReturnItem[]>([])
  const [returnPayments, setReturnPayments] = useState({
    cashCollected: 0,
    moMoCollected: 0,
    bankCollected: 0,
    creditSalesAmount: 0,
    cashReturnedByDriver: 0,
  })
  const [returnNotes, setReturnNotes] = useState("")
  const [returnDate, setReturnDate] = useState(new Date().toISOString().split("T")[0])
  const [breakdownOpen, setBreakdownOpen] = useState(false)
  const [breakdown, setBreakdown] = useState<BreakdownRow[]>([])
  const [expensesOpen, setExpensesOpen] = useState(false)
  const [expenses, setExpenses] = useState<ExpenseRow[]>([])
  const [savingReturn, setSavingReturn] = useState(false)
  const [overrideMismatch, setOverrideMismatch] = useState(false)
  // Sales posting mode. There is no poultry customer master, so the water
  // "OneCustomer" (pick a primary customer) mode is dropped:
  //   Summary  = post to the company's General Delivery default customer
  //   Detailed = free-text per-customer breakdown rows (walk-in labels)
  const [postingMode, setPostingMode] = useState<"Detailed" | "Summary">("Summary")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // Summary-only isn't allowed once there are credit sales — flip the operator
  // to the detailed flow so the credit lands on a named (free-text) customer.
  useEffect(() => {
    if (postingMode === "Summary" && returnPayments.creditSalesAmount > 0) setPostingMode("Detailed")
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [returnPayments.creditSalesAmount, postingMode])

  async function load() {
    setLoading(true)
    await ensurePoultryDefaults().catch(() => {})
    // Each lookup is independent — tolerate per-call failures and only surface a
    // banner when EVERY call failed (offline / API fully down).
    const results = await Promise.allSettled([
      listPoultryVehicleLoadings(), listPoultryDriverReturns(),
      listPoultryVehicles(), listPoultryRoutes(), listPoultryProducts(),
      listPoultryDrivers(),
    ])
    const [ls, rs, vs, rts, ps, ds] = results
    const failures: string[] = []
    if (ls.status === "fulfilled") setLoadings(ls.value)         ; else failures.push(`loadings: ${ls.reason?.message ?? ls.reason}`)
    if (rs.status === "fulfilled") setReturns(rs.value)          ; else failures.push(`returns: ${rs.reason?.message ?? rs.reason}`)
    if (vs.status === "fulfilled") setVehicles(vs.value)         ; else failures.push(`vehicles: ${vs.reason?.message ?? vs.reason}`)
    if (rts.status === "fulfilled") setRoutes(rts.value)         ; else failures.push(`routes: ${rts.reason?.message ?? rts.reason}`)
    if (ps.status === "fulfilled") {
      // Only sellable/finished poultry products can be loaded — eggs are the
      // sellable product (isRawEggProduct); bird products + explicit
      // FinishedGoods qualify too.
      setProducts(ps.value.filter(p => p.isActive && (p.isRawEggProduct || p.isBirdProduct || (p.productType ?? "FinishedGood") === "FinishedGood")))
    } else failures.push(`products: ${ps.reason?.message ?? ps.reason}`)
    if (ds.status === "fulfilled") setDrivers(ds.value)          ; else failures.push(`drivers: ${ds.reason?.message ?? ds.reason}`)

    if (failures.length === results.length) {
      toast({ title: "Couldn't load this page", description: failures[0], variant: "destructive" })
    } else if (failures.length > 0) {
      console.warn("poultry-driver-returns partial reload failure:", failures)
    }
    setLoading(false)
  }

  // ===== Load Vehicle handlers =====
  function openLoadDlg() {
    const v = vehicles.find(v => v.status === "Active")
    setLoadForm({
      poultryVehicleId: v?.poultryVehicleId ?? 0,
      poultryDriverId: drivers.find(d => d.isActive)?.poultryDriverId ?? 0,
      poultryRouteId: routes[0]?.poultryRouteId ?? 0,
      openingCashWithDriver: 0,
      notes: "",
      loadDate: new Date().toISOString().split("T")[0],
    })
    setLoadItems(products.length > 0
      ? [{ poultryProductId: products[0].poultryProductId, cratesLoaded: 0, unitPrice: products[0].unitPrice ?? 0, eggsPerCrate: 30, notes: "" }]
      : [],
    )
    setLoadDlg(true)
  }

  function addLoadItem() {
    const taken = new Set(loadItems.map(i => i.poultryProductId))
    const next = products.find(p => !taken.has(p.poultryProductId)) ?? products[0]
    if (!next) return toast({ title: "No more products to add", variant: "destructive" })
    setLoadItems([
      ...loadItems,
      { poultryProductId: next.poultryProductId, cratesLoaded: 0, unitPrice: next.unitPrice ?? 0, eggsPerCrate: 30, notes: "" },
    ])
  }

  function removeLoadItem(idx: number) {
    setLoadItems(loadItems.filter((_, i) => i !== idx))
  }

  function updateLoadItem(idx: number, patch: Partial<LoadItem>) {
    setLoadItems(loadItems.map((it, i) => i === idx ? { ...it, ...patch } : it))
  }

  async function saveLoad() {
    if (loadInflight.current) return
    if (!loadForm.poultryVehicleId) return toast({ title: "Pick a vehicle", variant: "destructive" })
    if (!loadForm.poultryDriverId) return toast({ title: "Driver is required", description: "Drivers carry the stock and the money — the system needs to know who.", variant: "destructive" })
    if (loadItems.length === 0) return toast({ title: "Add at least one product line", variant: "destructive" })
    if (loadItems.some(i => !i.poultryProductId || i.cratesLoaded <= 0)) {
      return toast({ title: "Each line needs a product and a quantity > 0", variant: "destructive" })
    }
    const dupes = new Set<number>()
    for (const it of loadItems) {
      if (dupes.has(it.poultryProductId)) return toast({ title: "Duplicate product line", description: "Each product can only appear once per load.", variant: "destructive" })
      dupes.add(it.poultryProductId)
    }

    loadInflight.current = true
    setSavingLoad(true)
    try {
      const itemsPayload = loadItems.map(it => ({
        poultryProductId: it.poultryProductId,
        cratesLoaded:     it.cratesLoaded,
        unitPrice:        it.unitPrice,
        eggsPerCrate:     it.eggsPerCrate,
        notes:            it.notes || null,
      }))

      const created = await createPoultryVehicleLoading({
        poultryVehicleId:      loadForm.poultryVehicleId,
        poultryDriverId:       loadForm.poultryDriverId  || null,
        poultryRouteId:        loadForm.poultryRouteId   || null,
        openingCashWithDriver: loadForm.openingCashWithDriver,
        notes:                 loadForm.notes,
        loadDate:              new Date(loadForm.loadDate).toISOString(),
        items:                 itemsPayload,
      })
      // Approve immediately so stock moves out — matches the "load and go"
      // operator flow. If approve fails we void the orphan Draft so it can't
      // masquerade as a duplicate next to the real Loaded row.
      if (!created?.poultryVehicleLoadingId) {
        throw new Error("The load was created but the server did not return its id — please retry.")
      }
      try {
        await approvePoultryVehicleLoading(created.poultryVehicleLoadingId)
      } catch (apErr: any) {
        try { await voidPoultryVehicleLoading(created.poultryVehicleLoadingId) } catch { /* best effort */ }
        throw new Error(apErr?.message ? `Load could not be confirmed: ${apErr.message}` : "Load could not be confirmed — please retry.")
      }
      toast({ title: "Delivery run loaded — stock moved out" })
      setLoadDlg(false); await load()
    } catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
    finally { setSavingLoad(false); loadInflight.current = false }
  }

  // "Edit" on a Reconciled row. There's no Update SP for returns — the
  // supported way to change one is reverse-then-re-record.
  function openEditReconciledDlg(l: PoultryVehicleLoading) {
    const r = returns.find(x => x.poultryVehicleLoadingId === l.poultryVehicleLoadingId && x.status === "Approved")
    if (!r) {
      toast({
        title: "No approved return found",
        description: "This loading is reconciled but has no Approved return row to edit.",
        variant: "destructive",
      })
      return
    }
    setEditAfterReverse(true)
    setReverseTarget(r)
  }

  // Pre-fill state from an existing return + its items. Called after a
  // successful reverse (or on Draft edit) so the Record Return dialog opens with
  // what the operator previously recorded.
  async function prefillFromExistingReturn(l: PoultryVehicleLoading, r: PoultryDriverReturn) {
    editReturnTargetRef.current = r
    setReturnNotes(r.notes ?? "")
    setReturnDate((r.returnDate ?? new Date().toISOString()).split("T")[0])
    setBreakdownOpen(false)
    setExpensesOpen(false)
    setBreakdown([])
    setExpenses([])
    setOverrideMismatch(false)
    const mode = r.salesPostingMode === "Detailed" ? "Detailed" : "Summary"
    setPostingMode(mode)
    setReturnPayments({
      cashCollected:      r.cashCollected      ?? 0,
      moMoCollected:      r.moMoCollected      ?? 0,
      bankCollected:      r.bankCollected      ?? 0,
      creditSalesAmount:  r.creditSalesAmount  ?? 0,
      cashReturnedByDriver: r.cashReturnedByDriver ?? (l.openingCashWithDriver ?? 0),
    })
    setReturnDlg({ open: true, loading: l })
    try {
      const [items, customerSales, savedExpenses] = await Promise.all([
        listPoultryDriverReturnItems(r.poultryDriverReturnId),
        listPoultryDriverReturnCustomerSales(r.poultryDriverReturnId).catch(() => []),
        listPoultryDriverReturnExpenses(r.poultryDriverReturnId).catch(() => []),
      ])

      if (items.length > 0) {
        setReturnItems(items.map(it => ({
          poultryProductId: it.poultryProductId,
          productName: it.productName ?? products.find(p => p.poultryProductId === it.poultryProductId)?.name ?? `Product #${it.poultryProductId}`,
          cratesLoaded: it.cratesLoaded ?? 0,
          cratesSold: it.cratesSold,
          cratesReturned: it.cratesReturned,
          cratesDamaged: it.cratesDamaged,
          unitPrice: it.unitPrice ?? 0,
        })))
      } else {
        await openReturnDlg(l)
      }

      // Restore the detailed customer breakdown (Detailed mode). The saved rows
      // carry only aggregate payment splits (no per-item lines are persisted on
      // the customer-sale row), so items start empty and can be re-added.
      if (customerSales.length > 0) {
        setBreakdown(customerSales.map(cs => ({
          customerId: cs.customerId ?? null,
          customerLabel: cs.customerLabel ?? "",
          cashPaid: cs.cashPaid ?? 0,
          moMoPaid: cs.moMoPaid ?? 0,
          bankPaid: cs.bankPaid ?? 0,
          creditAmount: cs.creditAmount ?? 0,
          notes: cs.notes ?? "",
          items: [],
        })))
        if (mode === "Detailed") setBreakdownOpen(true)
      }

      if (savedExpenses.length > 0) {
        setExpenses(savedExpenses.map(e => ({
          expenseCategory: e.expenseCategory,
          amount: e.amount ?? 0,
          description: e.description ?? "",
          isApproved: e.isApproved ?? true,
        })))
        setExpensesOpen(true)
      }
    } catch (e) {
      console.warn("prefill from existing return failed; falling back to fresh dialog", e)
      await openReturnDlg(l)
    }
  }

  // ===== Driver Return handlers =====
  async function openReturnDlg(l: PoultryVehicleLoading) {
    // A delivery can have only one open return. If a draft already exists for
    // this loading, continue/edit it. An already-approved one must be reversed.
    const existing = returns.find(r => r.poultryVehicleLoadingId === l.poultryVehicleLoadingId && r.status !== "Cancelled")
    if (existing) {
      if (existing.status === "Draft") {
        toast({ title: "Continuing this delivery's draft return", description: "Edit the figures and Approve & Reconcile when ready." })
        await prefillFromExistingReturn(l, existing)
      } else {
        toast({ title: "This delivery is already reconciled", description: "Reverse it from the Reconciled tab to make changes.", variant: "destructive" })
      }
      return
    }
    editReturnTargetRef.current = null
    setReturnNotes("")
    setReturnDate((l.loadDate ?? new Date().toISOString()).split("T")[0])
    setBreakdownOpen(false)
    setExpensesOpen(false)
    setBreakdown([])
    setExpenses([])
    setOverrideMismatch(false)
    setPostingMode("Summary")
    setReturnPayments({
      cashCollected: 0, moMoCollected: 0, bankCollected: 0,
      creditSalesAmount: 0, cashReturnedByDriver: l.openingCashWithDriver ?? 0,
    })
    setReturnDlg({ open: true, loading: l })
    try {
      const items = await listPoultryVehicleLoadingItems(l.poultryVehicleLoadingId)
      if (items.length > 0) {
        setReturnItems(items.map(it => ({
          poultryProductId: it.poultryProductId,
          productName: it.productName ?? products.find(p => p.poultryProductId === it.poultryProductId)?.name ?? `Product #${it.poultryProductId}`,
          cratesLoaded: it.cratesLoaded,
          // Default actuals to "all sold" — the operator adjusts when there
          // were returns.
          cratesSold: it.cratesLoaded,
          cratesReturned: 0,
          cratesDamaged: 0,
          unitPrice: it.unitPrice ?? 0,
        })))
      } else {
        // Legacy single-product loading.
        setReturnItems([{
          poultryProductId: l.poultryProductId ?? 0,
          productName: l.productName ?? products.find(p => p.poultryProductId === l.poultryProductId)?.name ?? "Product",
          cratesLoaded: l.cratesLoaded,
          cratesSold: l.cratesLoaded, cratesReturned: 0, cratesDamaged: 0,
          unitPrice: l.expectedSellingPricePerCrate ?? 0,
        }])
      }
    } catch (e) {
      console.warn("loading items fetch failed", e)
      setReturnItems([])
    }
  }

  function updateReturnItem(idx: number, patch: Partial<ReturnItem>) {
    setReturnItems(returnItems.map((it, i) => i === idx ? { ...it, ...patch } : it))
  }

  // ===== Customer breakdown handlers =====
  function addBreakdownRow() {
    setBreakdown([
      ...breakdown,
      {
        customerId: null, customerLabel: "",
        cashPaid: 0, moMoPaid: 0, bankPaid: 0, creditAmount: 0,
        notes: "",
        items: [],
      },
    ])
  }
  function removeBreakdownRow(idx: number) {
    setBreakdown(breakdown.filter((_, i) => i !== idx))
  }
  function updateBreakdownRow(idx: number, patch: Partial<BreakdownRow>) {
    setBreakdown(breakdown.map((r, i) => i === idx ? { ...r, ...patch } : r))
  }
  function addBreakdownItem(rowIdx: number) {
    const first = products[0]
    if (!first) return
    setBreakdown(breakdown.map((r, i) => i === rowIdx
      ? { ...r, items: [...r.items, { poultryProductId: first.poultryProductId, quantity: 1, unitPrice: first.unitPrice ?? 0 }] }
      : r,
    ))
  }
  function updateBreakdownItem(rowIdx: number, itemIdx: number, patch: Partial<BreakdownItem>) {
    setBreakdown(breakdown.map((r, i) => i === rowIdx
      ? { ...r, items: r.items.map((it, j) => j === itemIdx ? { ...it, ...patch } : it) }
      : r,
    ))
  }
  function removeBreakdownItem(rowIdx: number, itemIdx: number) {
    setBreakdown(breakdown.map((r, i) => i === rowIdx
      ? { ...r, items: r.items.filter((_, j) => j !== itemIdx) }
      : r,
    ))
  }

  function useSummaryOnly() {
    setBreakdown([])
    setBreakdownOpen(false)
  }

  // ===== Expenses handlers =====
  function addExpense() {
    setExpenses([...expenses, { expenseCategory: "Fuel", amount: 0, description: "", isApproved: true }])
  }
  function removeExpense(idx: number) {
    setExpenses(expenses.filter((_, i) => i !== idx))
  }
  function updateExpense(idx: number, patch: Partial<ExpenseRow>) {
    setExpenses(expenses.map((e, i) => i === idx ? { ...e, ...patch } : e))
  }

  // ===== Derived totals for the return modal =====
  const totalSold     = returnItems.reduce((s, it) => s + it.cratesSold, 0)
  const totalReturned = returnItems.reduce((s, it) => s + it.cratesReturned, 0)
  const totalDamaged  = returnItems.reduce((s, it) => s + it.cratesDamaged, 0)
  const totalLoadedItems = returnItems.reduce((s, it) => s + it.cratesLoaded, 0)
  const totalLoaded = returnDlg.loading?.cratesLoaded ?? totalLoadedItems
  const perItemBalanced = returnItems.every(it => (it.cratesSold + it.cratesReturned + it.cratesDamaged) === it.cratesLoaded)
  const overallBalanced = (totalSold + totalReturned + totalDamaged) === totalLoaded

  const expectedFromItems = returnItems.reduce((s, it) => s + (it.cratesSold * it.unitPrice), 0)
  const expectedCash = expectedFromItems ||
    (returnDlg.loading ? totalSold * (returnDlg.loading.expectedSellingPricePerCrate ?? 0) : 0)

  const collected = returnPayments.cashCollected + returnPayments.moMoCollected
                  + returnPayments.bankCollected + returnPayments.creditSalesAmount
  const shortage = Math.max(expectedCash - collected, 0)
  const overage  = Math.max(collected - expectedCash, 0)

  // Breakdown totals — compared against summary for the balance check.
  const breakdownTotals = useMemo(() => {
    let cash = 0, momo = 0, bank = 0, credit = 0
    const productQty = new Map<number, number>()
    for (const r of breakdown) {
      cash += r.cashPaid; momo += r.moMoPaid; bank += r.bankPaid; credit += r.creditAmount
      for (const it of r.items) {
        productQty.set(it.poultryProductId, (productQty.get(it.poultryProductId) ?? 0) + it.quantity)
      }
    }
    return { cash, momo, bank, credit, productQty }
  }, [breakdown])

  const breakdownProvided = breakdown.length > 0
  const breakdownPaymentsBalance =
    breakdownTotals.cash   === returnPayments.cashCollected &&
    breakdownTotals.momo   === returnPayments.moMoCollected &&
    breakdownTotals.bank   === returnPayments.bankCollected &&
    breakdownTotals.credit === returnPayments.creditSalesAmount
  const breakdownQtyBalance = returnItems.every(ri =>
    (breakdownTotals.productQty.get(ri.poultryProductId) ?? 0) === ri.cratesSold,
  )
  const breakdownBalanced = breakdownPaymentsBalance && breakdownQtyBalance

  // Validate credit-to-customer. No customer master exists, so a credit row is
  // considered assigned when it carries a free-text customer label.
  const isDetailed = postingMode === "Detailed"
  const creditWithoutCustomer = isDetailed
    && returnPayments.creditSalesAmount > 0
    && !breakdownProvided
  const detailedCreditUnassigned = isDetailed
    && breakdownProvided
    && breakdown.some(r => r.creditAmount > 0 && !r.customerLabel.trim())

  const expensesTotal = expenses.reduce((s, e) => s + (e.isApproved ? e.amount : 0), 0)

  // The cash the driver returns must reconcile with the float they left with
  // (opening cash) less any approved expenses paid from that float.
  const openingCashFloat = returnDlg.loading?.openingCashWithDriver ?? 0
  const expectedFloatBack = Math.max(openingCashFloat - expensesTotal, 0)
  const floatBalanced = Math.abs((returnPayments.cashReturnedByDriver ?? 0) - expectedFloatBack) < 0.01

  async function saveAndApproveReconcile() {
    await saveReturn({ approveAfter: true })
  }

  async function saveReturn(opts?: { approveAfter?: boolean }) {
    if (returnInflight.current) return
    if (!returnDlg.loading) return
    if (!perItemBalanced) {
      return toast({
        title: "Per-product crates don't reconcile",
        description: "Each product line's Sold + Returned + Damaged must equal Loaded.",
        variant: "destructive",
      })
    }
    if (!overallBalanced) {
      return toast({
        title: "Totals don't reconcile",
        description: `Sold(${totalSold}) + Returned(${totalReturned}) + Damaged(${totalDamaged}) != Loaded(${totalLoaded})`,
        variant: "destructive",
      })
    }
    if (isDetailed && breakdownProvided && !breakdownBalanced && !overrideMismatch) {
      return toast({
        title: "Customer breakdown doesn't match summary",
        description: "Match the totals, click \"Use Summary Only\", or tick the override.",
        variant: "destructive",
      })
    }
    if (detailedCreditUnassigned && !overrideMismatch) {
      return toast({
        title: "Credit not assigned to customers",
        description: "Give each credit row a customer label, or tick the admin override.",
        variant: "destructive",
      })
    }

    returnInflight.current = true
    setSavingReturn(true)
    try {
      const editedFrom = editReturnTargetRef.current
      // No replaceReturnId exists on the poultry API — cancel the return we're
      // replacing first so the create doesn't trip the one-active-return guard.
      if (editedFrom) {
        try { await cancelPoultryDriverReturn(editedFrom.poultryDriverReturnId) } catch { /* best effort */ }
      }

      const input: PoultryDriverReturnInput = {
        poultryVehicleLoadingId: returnDlg.loading.poultryVehicleLoadingId,
        returnDate: new Date(returnDate).toISOString(),
        cratesSold: totalSold,
        cratesReturned: totalReturned,
        cratesDamaged: totalDamaged,
        missingCrates: 0,
        cashCollected: returnPayments.cashCollected,
        moMoCollected: returnPayments.moMoCollected,
        bankCollected: returnPayments.bankCollected,
        creditSalesAmount: returnPayments.creditSalesAmount,
        cashReturnedByDriver: returnPayments.cashReturnedByDriver,
        approvedDeliveryExpenses: expensesTotal,
        salesPostingMode: postingMode,
        primaryCustomerId: null,
        notes: returnNotes || null,
        items: returnItems.map(it => ({
          poultryProductId: it.poultryProductId,
          cratesSold: it.cratesSold,
          cratesReturned: it.cratesReturned,
          cratesDamaged: it.cratesDamaged,
          unitPrice: it.unitPrice,
        })),
        customerSales: (isDetailed && breakdownProvided) ? breakdown.map(r => ({
          customerId: r.customerId ?? null,
          customerLabel: r.customerLabel || null,
          cashPaid: r.cashPaid, moMoPaid: r.moMoPaid, bankPaid: r.bankPaid,
          creditAmount: r.creditAmount,
          notes: r.notes || null,
          items: r.items.map(it => ({ poultryProductId: it.poultryProductId, quantity: it.quantity, unitPrice: it.unitPrice })),
        })) : undefined,
        expenses: expenses.length > 0 ? expenses.map(e => ({
          expenseCategory: e.expenseCategory,
          amount: e.amount,
          description: e.description || null,
          isApproved: e.isApproved,
        })) : undefined,
      }

      // approveAfter = validate + materialise in one shot (creates the return,
      // posts sales/payments/inventory, marks it Reconciled). Otherwise create a
      // Draft the operator can approve later from the Returns tab.
      if (opts?.approveAfter) {
        await approveReconcilePoultryDriverReturn(input)
      } else {
        await createPoultryDriverReturn(input)
      }

      // Editing must leave EXACTLY ONE record — remove the old (now Cancelled)
      // return after the replacement is in.
      if (editedFrom) {
        try { await deletePoultryDriverReturn(editedFrom.poultryDriverReturnId) }
        catch (e: any) {
          console.warn("could not remove replaced return", editedFrom.poultryDriverReturnId, e)
        }
        editReturnTargetRef.current = null
      }

      toast({
        title: opts?.approveAfter
          ? "Return reconciled"
          : (editedFrom ? "Edited return saved as Draft" : "Return recorded as Draft"),
        description: opts?.approveAfter
          ? "Sales, payments, inventory and customer balances updated."
          : "Approve from the Returns tab when you're ready to reconcile.",
      })
      setReturnDlg({ open: false }); await load()
    } catch (e: any) { toast({ title: "Return failed", description: e?.message, variant: "destructive" }) }
    finally { setSavingReturn(false); returnInflight.current = false }
  }

  // ===== Stats =====
  const totals = useMemo(() => ({
    openLoadings: loadings.filter(l => l.status === "Loaded").length,
    totalShortage: returns.reduce((s, r) => s + (r.shortageAmount ?? 0), 0),
    todayReturns: returns.filter(r => r.returnDate?.slice(0, 10) === new Date().toISOString().slice(0, 10)).length,
    activeDrivers: drivers.filter(d => d.isActive).length,
  }), [loadings, returns, drivers])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Truck className="h-6 w-6 text-sky-600" /> Deliveries
            </h1>
            <Button onClick={openLoadDlg} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> Load vehicle</Button>
          </div>

          <Tabs defaultValue="active">
            <TabsList className="flex flex-wrap h-auto items-stretch w-full gap-1">
              <TabsTrigger value="active" className="flex-1 min-w-fit">Active loads ({loadings.filter(l => l.status === "Loaded").length})</TabsTrigger>
              <TabsTrigger value="returns" className="flex-1 min-w-fit">Returns ({returns.length})</TabsTrigger>
              <TabsTrigger value="reconciled" className="flex-1 min-w-fit">Reconciled ({loadings.filter(l => l.status === "Reconciled").length})</TabsTrigger>
              <TabsTrigger value="setup" className="flex-1 min-w-fit">Setup</TabsTrigger>
            </TabsList>

            <TabsContent value="active">
              <ListFilters
                search={loadingsSearch} setSearch={setLoadingsSearch}
                dateFrom={loadingsDateFrom} setDateFrom={setLoadingsDateFrom}
                dateTo={loadingsDateTo} setDateTo={setLoadingsDateTo}
                searchPlaceholder="Search driver, vehicle or route"
                extras={<DeliveryDropdowns
                  drivers={drivers} vehicles={vehicles} routes={routes}
                  driver={filterDriver} setDriver={setFilterDriver}
                  vehicle={filterVehicle} setVehicle={setFilterVehicle}
                  route={filterRoute} setRoute={setFilterRoute}
                  status={filterStatus} setStatus={setFilterStatus}
                  statusOptions={["Draft", "Loaded", "Returned", "Reconciled", "Cancelled"]}
                />}
              />
              <Card>
                <CardContent className="p-0">
                  {loading ? (
                    <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                  ) : loadings.filter(l => l.status === "Loaded" || l.status === "Draft").length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No active loads. Click <span className="font-medium">Load vehicle</span> above to dispatch a delivery.</div>
                  ) : (
                    <DeliveriesTable
                      rows={visibleLoadings.filter(l => l.status === "Loaded" || l.status === "Draft")}
                      onRecordReturn={openReturnDlg}
                      onVoid={setVoidTarget}
                      onReload={doReload}
                      showActions
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="returns">
              <ListFilters
                search={returnsSearch} setSearch={setReturnsSearch}
                dateFrom={returnsDateFrom} setDateFrom={setReturnsDateFrom}
                dateTo={returnsDateTo} setDateTo={setReturnsDateTo}
                searchPlaceholder="Search driver, vehicle or route"
                extras={<DeliveryDropdowns
                  drivers={drivers} vehicles={vehicles} routes={routes}
                  driver={filterDriver} setDriver={setFilterDriver}
                  vehicle={filterVehicle} setVehicle={setFilterVehicle}
                  route={filterRoute} setRoute={setFilterRoute}
                  status={filterStatus} setStatus={setFilterStatus}
                  statusOptions={["Draft", "Approved", "Cancelled"]}
                />}
              />
              <Card>
                <CardContent className="p-4">
                  {returns.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No driver returns recorded yet.</div>
                  ) : (
                    <MobileCardList
                      items={pgReturns.pageItems}
                      pagination={pgReturns.paginationProps}
                      getKey={(r) => r.poultryDriverReturnId}
                      primary={(r) => `Delivery #${r.poultryVehicleLoadingId} · ${r.vehicleName ?? "Vehicle —"} · ${r.cratesSold} crates sold`}
                      secondary={(r) => (
                        <>
                          <span>{r.returnDate.split("T")[0]}</span>
                          {r.driverName && <span>· {r.driverName}</span>}
                          {r.routeName && <span>· {r.routeName}</span>}
                          {(r.shortageAmount ?? 0) > 0 && <span className="text-rose-600">· Short {gh(r.shortageAmount ?? 0)}</span>}
                        </>
                      )}
                      details={(r) => [
                        { label: "Delivery #", value: r.poultryVehicleLoadingId },
                        { label: "Date", value: r.returnDate.split("T")[0] },
                        { label: "Vehicle", value: r.vehicleName ?? "—" },
                        { label: "Driver", value: r.driverName ?? "—" },
                        { label: "Route", value: r.routeName ?? "—" },
                        { label: "Status", value: r.status },
                        { label: "Sold (crates)", value: r.cratesSold },
                        { label: "Returned (crates)", value: r.cratesReturned },
                        { label: "Damaged (crates)", value: r.cratesDamaged },
                        { label: `Cash${cur}`, value: gh(r.cashCollected) },
                        { label: `MoMo${cur}`, value: gh(r.moMoCollected) },
                        { label: `Credit${cur}`, value: gh(r.creditSalesAmount) },
                        { label: `Shortage${cur}`, value: <span className={(r.shortageAmount ?? 0) > 0 ? "text-rose-600" : ""}>{gh(r.shortageAmount ?? 0)}</span> },
                      ]}
                      actions={(r) => (
                        <>
                          <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                            <Link href={`/poultry-driver-returns/${r.poultryVehicleLoadingId}`}>View details</Link>
                          </Button>
                          {r.status === "Draft" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEditReturnDlg(r)}>
                              <Pencil className="h-4 w-4 mr-1" /> Edit
                            </Button>
                          )}
                          {r.status === "Draft" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => approveDraftReturn(r)}>
                              <CheckCircle2 className="h-4 w-4 mr-1" /> Approve &amp; Reconcile
                            </Button>
                          )}
                          {r.status === "Draft" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => cancelDraftReturn(r)}>
                              <XCircle className="h-4 w-4 mr-1" /> Cancel
                            </Button>
                          )}
                          {r.status === "Approved" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => setReverseTarget(r)}>
                              <Undo2 className="h-4 w-4 mr-1" /> Reverse
                            </Button>
                          )}
                          {r.status === "Cancelled" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => uncancelDraftReturn(r)}>
                              <Undo2 className="h-4 w-4 mr-1" /> Uncancel
                            </Button>
                          )}
                          {r.status === "Cancelled" && permissions.isAdmin && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(r)}>
                              <Trash2 className="h-4 w-4 mr-1" /> Delete
                            </Button>
                          )}
                        </>
                      )}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Delivery #</TableHead>
                                <TableHead>Date</TableHead>
                                <TableHead>Vehicle</TableHead>
                                <TableHead>Driver</TableHead>
                                <TableHead>Status</TableHead>
                                <TableHead className="text-right">Sold (crates)</TableHead>
                                <TableHead className="text-right">Returned (crates)</TableHead>
                                <TableHead className="text-right">Damaged (crates)</TableHead>
                                <TableHead className="text-right">Cash{cur}</TableHead>
                                <TableHead className="text-right">MoMo{cur}</TableHead>
                                <TableHead className="text-right">Credit{cur}</TableHead>
                                <TableHead className="text-right">Shortage{cur}</TableHead>
                                <TableHead className="text-right">Actions</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pgReturns.pageItems.map((r) => (
                            <TableRow key={r.poultryDriverReturnId}>
                              <TableCell className="font-medium tabular-nums">#{r.poultryVehicleLoadingId}</TableCell>
                              <TableCell>{r.returnDate.split("T")[0]}</TableCell>
                              <TableCell className="font-medium">{r.vehicleName ?? "—"}</TableCell>
                              <TableCell>{r.driverName ?? "—"}</TableCell>
                              <TableCell><Badge className={r.status === "Approved" ? "bg-green-100 text-green-700" : r.status === "Cancelled" ? "bg-slate-100 text-slate-600" : "bg-amber-100 text-amber-700"}>{r.status}</Badge></TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesReturned}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.cratesDamaged}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.cashCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.moMoCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.creditSalesAmount)}</TableCell>
                                <TableCell className={`text-right tabular-nums ${(r.shortageAmount ?? 0) > 0 ? "text-rose-600" : ""}`}>{gh(r.shortageAmount ?? 0)}</TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                <Button asChild size="sm" variant="ghost" title="View details">
                                  <Link href={`/poultry-driver-returns/${r.poultryVehicleLoadingId}`}><Eye className="h-4 w-4" /></Link>
                                </Button>
                                {r.status === "Draft" && (
                                  <Button size="sm" variant="ghost" onClick={() => openEditReturnDlg(r)} title="Edit this Draft (pre-fills the Record Return dialog)">
                                    <Pencil className="h-4 w-4 text-sky-700" />
                                  </Button>
                                )}
                                {r.status === "Draft" && (
                                  <Button size="sm" variant="ghost" onClick={() => approveDraftReturn(r)} title="Approve & Reconcile">
                                    <CheckCircle2 className="h-4 w-4 text-green-600" />
                                  </Button>
                                )}
                                {r.status === "Draft" && (
                                  <Button size="sm" variant="ghost" onClick={() => cancelDraftReturn(r)} title="Cancel return">
                                    <XCircle className="h-4 w-4 text-rose-500" />
                                  </Button>
                                )}
                                {r.status === "Approved" && (
                                  <Button size="sm" variant="ghost" onClick={() => setReverseTarget(r)} title="Reverse reconciliation">
                                    <Undo2 className="h-4 w-4 text-amber-600" />
                                  </Button>
                                )}
                                {r.status === "Cancelled" && (
                                  <Button size="sm" variant="ghost" onClick={() => uncancelDraftReturn(r)} title="Uncancel (back to Draft so it can be re-approved)">
                                    <Undo2 className="h-4 w-4 text-emerald-600" />
                                  </Button>
                                )}
                                {r.status === "Cancelled" && permissions.isAdmin && (
                                  <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(r)} title="Delete this cancelled return (admin only, hard delete)">
                                    <Trash2 className="h-4 w-4 text-red-500" />
                                  </Button>
                                )}
                              </TableCell>
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
            </TabsContent>

            <TabsContent value="reconciled">
              <ListFilters
                search={loadingsSearch} setSearch={setLoadingsSearch}
                dateFrom={loadingsDateFrom} setDateFrom={setLoadingsDateFrom}
                dateTo={loadingsDateTo} setDateTo={setLoadingsDateTo}
                searchPlaceholder="Search driver, vehicle or route"
                extras={<DeliveryDropdowns
                  drivers={drivers} vehicles={vehicles} routes={routes}
                  driver={filterDriver} setDriver={setFilterDriver}
                  vehicle={filterVehicle} setVehicle={setFilterVehicle}
                  route={filterRoute} setRoute={setFilterRoute}
                  status={filterStatus} setStatus={setFilterStatus}
                  statusOptions={["Reconciled"]}
                />}
              />
              <Card>
                <CardContent className="p-0">
                  {loadings.filter(l => l.status === "Reconciled").length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No reconciled loadings yet.</div>
                  ) : (
                    <DeliveriesTable
                      rows={visibleLoadings.filter(l => l.status === "Reconciled")}
                      onRecordReturn={openReturnDlg}
                      onVoid={setVoidTarget}
                      onReverse={(l) => {
                        const r = returns.find(x => x.poultryVehicleLoadingId === l.poultryVehicleLoadingId && x.status === "Approved")
                        if (!r) {
                          toast({ title: "No approved return found", description: "This loading is reconciled but has no Approved return row to reverse.", variant: "destructive" })
                          return
                        }
                        setReverseTarget(r)
                      }}
                      onEditReconciled={openEditReconciledDlg}
                      showActions={false}
                    />
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="setup">
              <Card>
                <CardContent className="p-4 grid grid-cols-1 md:grid-cols-3 gap-3">
                  <Link href="/poultry-drivers" className="border rounded-md p-4 hover:bg-slate-50 transition">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <Users2 className="h-4 w-4 text-sky-600" /> Drivers
                    </div>
                    <div className="text-xs text-slate-500 mt-1">{drivers.filter(d => d.isActive).length} active · manage drivers, base pay, commissions</div>
                  </Link>
                  <Link href="/poultry-vehicles" className="border rounded-md p-4 hover:bg-slate-50 transition">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <Truck className="h-4 w-4 text-sky-600" /> Vehicles
                    </div>
                    <div className="text-xs text-slate-500 mt-1">{vehicles.filter(v => v.status === "Active").length} active · manage vehicles and capacity</div>
                  </Link>
                  <Link href="/poultry-routes" className="border rounded-md p-4 hover:bg-slate-50 transition">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <MapPin className="h-4 w-4 text-sky-600" /> Routes
                    </div>
                    <div className="text-xs text-slate-500 mt-1">{routes.length} configured · manage delivery routes</div>
                  </Link>
                  <Link href="/poultry-driver-report" className="border rounded-md p-4 hover:bg-slate-50 transition md:col-span-3">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <Truck className="h-4 w-4 text-sky-600" /> Driver collection report
                    </div>
                    <div className="text-xs text-slate-500 mt-1">Per-driver per-product loaded / sold / returned / damaged with cash + shortage roll-up</div>
                  </Link>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>

          {/* Page-level KPIs — summarise across all tabs (not filtered by the
              per-tab ListFilters). */}
          <div className="mt-4 mb-3 grid grid-cols-2 md:grid-cols-5 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Vehicles out</div><div className="text-xl font-semibold">{totals.openLoadings}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Returns today</div><div className="text-xl font-semibold">{totals.todayReturns}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total shortages</div><div className="text-xl font-semibold tabular-nums">{gh(totals.totalShortage)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Active vehicles</div><div className="text-xl font-semibold">{vehicles.filter(v => v.status === "Active").length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Active drivers</div><div className="text-xl font-semibold">{totals.activeDrivers}</div></CardContent></Card>
          </div>
        </main>
      </div>

      {/* ===================================================================
          Load Vehicle / Create Delivery Run dialog
          =================================================================== */}
      <Dialog open={loadDlg} onOpenChange={setLoadDlg}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Truck className="w-5 h-5 text-blue-600" />
              Create delivery run — load driver
            </DialogTitle>
            <DialogDescription>
              Assign a driver, pick the vehicle + route, and list the products being loaded. Stock moves out of the warehouse on save.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="Driver & route" color="indigo" columns={3}>
              <FormField label="Driver *">
                <Select value={String(loadForm.poultryDriverId)} onValueChange={(v) => {
                  const driverId = Number(v)
                  const d = drivers.find(x => x.poultryDriverId === driverId)
                  setLoadForm({
                    ...loadForm,
                    poultryDriverId: driverId,
                    poultryVehicleId: d?.defaultVehicleId ?? loadForm.poultryVehicleId,
                  })
                }}>
                  <SelectTrigger><SelectValue placeholder="Pick driver" /></SelectTrigger>
                  <SelectContent>{drivers.filter(d => d.isActive).map(d => (
                    <SelectItem key={d.poultryDriverId} value={String(d.poultryDriverId)}>{d.driverName}</SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Vehicle *">
                <Select value={String(loadForm.poultryVehicleId)} onValueChange={(v) => setLoadForm({ ...loadForm, poultryVehicleId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Pick vehicle" /></SelectTrigger>
                  <SelectContent>{vehicles.filter(v => v.status === "Active").map(v => (
                    <SelectItem key={v.poultryVehicleId} value={String(v.poultryVehicleId)}>{v.vehicleName}{v.vehicleType ? ` (${v.vehicleType})` : ""}</SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Route">
                <Select value={String(loadForm.poultryRouteId)} onValueChange={(v) => {
                  const routeId = Number(v)
                  const r = routes.find(x => x.poultryRouteId === routeId)
                  setLoadForm({
                    ...loadForm,
                    poultryRouteId: routeId,
                    poultryVehicleId: loadForm.poultryVehicleId || (r?.defaultVehicleId ?? loadForm.poultryVehicleId),
                  })
                }}>
                  <SelectTrigger><SelectValue placeholder="Pick route" /></SelectTrigger>
                  <SelectContent>{routes.map(r => (
                    <SelectItem key={r.poultryRouteId} value={String(r.poultryRouteId)}>{r.routeName}</SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
              <FormField label={`Opening cash with driver${cur}`} hint="Cash float given to driver before departure (change, fuel, small expenses). Separate from sales cash.">
                <NumberInput min={0} step="0.01" value={loadForm.openingCashWithDriver}
                  onChange={(e) => setLoadForm({ ...loadForm, openingCashWithDriver: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Load date">
                <Input type="date" value={loadForm.loadDate} onChange={(e) => setLoadForm({ ...loadForm, loadDate: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white flex items-center justify-between gap-2">
                <span>Products loaded</span>
                <Button type="button" variant="secondary" size="sm" onClick={addLoadItem}>
                  <Plus className="h-4 w-4 mr-1" /> Add product
                </Button>
              </div>
              <div className="p-4 bg-white">
                <div className="text-xs text-slate-500 mb-2">One row per product on this run.</div>

            {loadItems.length === 0 ? (
              <div className="text-xs text-slate-500 px-2 py-3">No products. Click "Add product" to add one.</div>
            ) : (
              <>
                {/* Desktop table */}
                <div className="hidden lg:block overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="min-w-[180px]">Product</TableHead>
                        <TableHead className="text-right">Quantity (crates)</TableHead>
                        <TableHead className="text-right">Eggs / crate</TableHead>
                        <TableHead className="text-right">Unit price{cur}</TableHead>
                        <TableHead className="text-right">Expected{cur}</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {loadItems.map((it, idx) => {
                        const exp = it.cratesLoaded * it.unitPrice
                        return (
                          <TableRow key={idx}>
                            <TableCell>
                              <Select value={String(it.poultryProductId)} onValueChange={(v) => {
                                const id = Number(v)
                                const p = products.find(x => x.poultryProductId === id)
                                updateLoadItem(idx, { poultryProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                              }}>
                                <SelectTrigger><SelectValue /></SelectTrigger>
                                <SelectContent>{products.map(p => (
                                  <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>
                                ))}</SelectContent>
                              </Select>
                            </TableCell>
                            <TableCell className="text-right">
                              <NumberInput min={0} value={it.cratesLoaded}
                                onChange={(e) => updateLoadItem(idx, { cratesLoaded: Number(e.target.value) || 0 })}
                                className="w-24 ml-auto text-right" />
                            </TableCell>
                            <TableCell className="text-right">
                              <NumberInput min={0} value={it.eggsPerCrate}
                                onChange={(e) => updateLoadItem(idx, { eggsPerCrate: Number(e.target.value) || 0 })}
                                className="w-20 ml-auto text-right" />
                            </TableCell>
                            <TableCell className="text-right">
                              <NumberInput min={0} step="0.01" value={it.unitPrice}
                                onChange={(e) => updateLoadItem(idx, { unitPrice: Number(e.target.value) || 0 })}
                                className="w-24 ml-auto text-right" />
                            </TableCell>
                            <TableCell className="text-right tabular-nums">{gh(exp)}</TableCell>
                            <TableCell>
                              <Button size="sm" variant="ghost" onClick={() => removeLoadItem(idx)}>
                                <Trash2 className="h-4 w-4 text-red-500" />
                              </Button>
                            </TableCell>
                          </TableRow>
                        )
                      })}
                    </TableBody>
                  </Table>
                </div>

                {/* Mobile card stack */}
                <div className="lg:hidden space-y-2">
                  {loadItems.map((it, idx) => {
                    const exp = it.cratesLoaded * it.unitPrice
                    return (
                      <div key={idx} className="rounded-lg border border-slate-200 bg-white p-3 space-y-2">
                        <div className="flex items-center gap-2">
                          <div className="flex-1 min-w-0">
                            <Select value={String(it.poultryProductId)} onValueChange={(v) => {
                              const id = Number(v)
                              const p = products.find(x => x.poultryProductId === id)
                              updateLoadItem(idx, { poultryProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                            }}>
                              <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                              <SelectContent>{products.map(p => (
                                <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>
                              ))}</SelectContent>
                            </Select>
                          </div>
                          <Button size="sm" variant="ghost" onClick={() => removeLoadItem(idx)} className="shrink-0">
                            <Trash2 className="h-4 w-4 text-red-500" />
                          </Button>
                        </div>
                        <div className="grid grid-cols-3 gap-2 items-end">
                          <div>
                            <label className="text-xs text-slate-500">Qty (crates)</label>
                            <NumberInput min={0} value={it.cratesLoaded}
                              onChange={(e) => updateLoadItem(idx, { cratesLoaded: Number(e.target.value) || 0 })}
                              className="text-right w-full" />
                          </div>
                          <div>
                            <label className="text-xs text-slate-500">Unit price{cur}</label>
                            <NumberInput min={0} step="0.01" value={it.unitPrice}
                              onChange={(e) => updateLoadItem(idx, { unitPrice: Number(e.target.value) || 0 })}
                              className="text-right w-full" />
                          </div>
                          <div className="text-right">
                            <div className="text-xs text-slate-500">Expected{cur}</div>
                            <div className="font-semibold tabular-nums text-sm">{gh(exp)}</div>
                          </div>
                        </div>
                      </div>
                    )
                  })}
                </div>
              </>
            )}
              </div>
            </div>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Textarea value={loadForm.notes} onChange={(e) => setLoadForm({ ...loadForm, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm flex items-center justify-between">
              <span className="text-slate-500">Total expected cash:</span>
              <span className="font-semibold tabular-nums">
                {gh(loadItems.reduce((s, it) => s + (it.cratesLoaded * it.unitPrice), 0))}
              </span>
            </div>

            <div className="flex flex-col-reverse sm:flex-row gap-2 sm:gap-3 sm:justify-end pt-2">
              <Button type="button" onClick={() => setLoadDlg(false)} className="bg-red-600 hover:bg-red-700 text-white w-full sm:w-auto h-11 sm:h-10">Cancel</Button>
              <Button onClick={saveLoad} disabled={savingLoad} className="w-full sm:w-auto h-11 sm:h-10">
                {savingLoad ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Load & approve"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* ===================================================================
          Record Driver Return dialog — multi-product + breakdown + expenses
          =================================================================== */}
      <Dialog open={returnDlg.open} onOpenChange={(v) => { if (!v) { setReturnDlg({ open: false }); editReturnTargetRef.current = null } }}>
        <DialogContent className="w-[98vw] max-w-[1800px] max-h-[92vh] overflow-y-auto overflow-x-hidden p-3 sm:p-6">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Truck className="w-5 h-5 text-blue-600" />
              Record driver return — {returnDlg.loading?.driverName ?? "—"} / {returnDlg.loading?.vehicleName} / {returnDlg.loading?.routeName ?? "—"}
            </DialogTitle>
            <DialogDescription>
              Reconcile crates sold / returned / damaged per product, then enter the payment summary. Optionally add the per-customer breakdown and delivery expenses.
            </DialogDescription>
          </DialogHeader>

          {returnDlg.loading && (
            <div className="space-y-4 min-w-0 w-full">
              <div className="flex items-center gap-2">
                <label className="text-sm text-slate-600 shrink-0">Return date</label>
                <Input type="date" value={returnDate} onChange={(e) => setReturnDate(e.target.value)} className="max-w-[200px]" />
              </div>
              <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs">
                  <div>
                    <div className="text-slate-500">Loaded</div>
                    <div className="text-base font-semibold tabular-nums text-slate-900">{totalLoaded} crates</div>
                  </div>
                  <div>
                    <div className="text-slate-500">Accounted</div>
                    <div className={`text-base font-semibold tabular-nums ${overallBalanced && perItemBalanced ? "text-emerald-700" : "text-amber-700"}`}>
                      {totalSold + totalReturned + totalDamaged} / {totalLoaded}
                    </div>
                  </div>
                  <div>
                    <div className="text-slate-500">Expected cash</div>
                    <div className="text-base font-semibold tabular-nums text-slate-900">{gh(expectedCash)}</div>
                  </div>
                  <div>
                    <div className="text-slate-500">Collected</div>
                    <div className={`text-base font-semibold tabular-nums ${shortage > 0 ? "text-rose-600" : overage > 0 ? "text-green-700" : "text-slate-900"}`}>
                      {gh(collected)}
                    </div>
                  </div>
                </div>
                {(shortage > 0 || overage > 0) && (
                  <div className="mt-2 text-xs text-slate-600 flex flex-wrap gap-x-4 gap-y-1">
                    {shortage > 0 && <span>Shortage: <strong className="text-rose-600 tabular-nums">{gh(shortage)}</strong></span>}
                    {overage > 0 && <span>Overage: <strong className="text-green-700 tabular-nums">{gh(overage)}</strong></span>}
                    {expensesTotal > 0 && <span>Approved expenses: <strong className="tabular-nums">{gh(expensesTotal)}</strong></span>}
                  </div>
                )}
              </div>

              {/* Per-product reconciliation */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white flex flex-col sm:flex-row sm:items-center sm:justify-between gap-1 sm:gap-2">
                  <span>Step 1 · Reconcile crates per product</span>
                  <span className="text-xs font-normal text-amber-50">Sold + Returned + Damaged must equal Loaded</span>
                </div>

                <div className="bg-white p-4 space-y-4">
                  {returnItems.map((it, idx) => {
                    const total = it.cratesSold + it.cratesReturned + it.cratesDamaged
                    const balanced = total === it.cratesLoaded
                    const expected = it.cratesSold * it.unitPrice
                    const rowClass = "flex items-center justify-between gap-3 min-w-0"
                    const labelClass = "text-sm text-slate-700 truncate"
                    const valueWrapClass = "w-32 sm:w-36 shrink-0"
                    return (
                      <div
                        key={idx}
                        className={`rounded-lg border p-4 space-y-3 ${
                          balanced ? "border-slate-200 bg-white" : "border-amber-300 bg-amber-50"
                        }`}
                      >
                        <div className="flex items-center justify-between gap-2">
                          <div className="font-semibold text-slate-900 break-words min-w-0">
                            {it.productName}
                          </div>
                          <div
                            className={`text-xs whitespace-nowrap font-semibold ${
                              balanced ? "text-emerald-600" : "text-amber-700"
                            }`}
                          >
                            {balanced
                              ? "✓ Balanced"
                              : total - it.cratesLoaded > 0
                                ? `+${total - it.cratesLoaded}`
                                : `${total - it.cratesLoaded}`}
                          </div>
                        </div>

                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2">
                          <div className={rowClass}>
                            <div className={labelClass}>Loaded (crates)</div>
                            <div className={valueWrapClass}>
                              <div className="text-right tabular-nums font-medium pr-3">{it.cratesLoaded}</div>
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Expected{cur}</div>
                            <div className={valueWrapClass}>
                              <div className="text-right tabular-nums font-semibold pr-3">{gh(expected)}</div>
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Sold (crates)</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                value={it.cratesSold}
                                onChange={(e) => updateReturnItem(idx, { cratesSold: Number(e.target.value) || 0 })}
                              />
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Unit price{cur}</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                step="0.01"
                                value={it.unitPrice}
                                onChange={(e) => updateReturnItem(idx, { unitPrice: Number(e.target.value) || 0 })}
                              />
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Returned (crates)</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                value={it.cratesReturned}
                                onChange={(e) => updateReturnItem(idx, { cratesReturned: Number(e.target.value) || 0 })}
                              />
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Damaged (crates)</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                value={it.cratesDamaged}
                                onChange={(e) => updateReturnItem(idx, { cratesDamaged: Number(e.target.value) || 0 })}
                              />
                            </div>
                          </div>
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>

              {/* Payment summary */}
              <FormSection title={`Step 2 · Money collected${cur}`} color="green" columns={1}>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
                  {[
                    { key: "cashCollected",     label: "Cash",          hint: "Physical cash the driver collected on the run." },
                    { key: "moMoCollected",     label: "MoMo",          hint: "Mobile Money (MTN, Vodafone, AirtelTigo)." },
                    { key: "bankCollected",     label: "Bank",          hint: "Bank transfers / cheque deposits received today." },
                    { key: "creditSalesAmount", label: "Credit sales",  hint: "Goods given on credit — to be paid later." },
                  ].map((row) => (
                    <div key={row.key} className="flex items-center justify-between gap-3 min-w-0">
                      <div className="min-w-0 flex-1">
                        <div className="text-sm font-medium text-slate-700">{row.label}</div>
                        <div className="text-[11px] text-slate-500 truncate">{row.hint}</div>
                      </div>
                      <div className="w-28 sm:w-36 shrink-0">
                        <NumberInput
                          className="text-right tabular-nums"
                          min={0}
                          step="0.01"
                          value={returnPayments[row.key as keyof typeof returnPayments]}
                          onChange={(e) =>
                            setReturnPayments({
                              ...returnPayments,
                              [row.key]: Number(e.target.value) || 0,
                            })
                          }
                        />
                      </div>
                    </div>
                  ))}
                </div>
                <div className="flex items-center justify-between gap-3 min-w-0 rounded-md bg-slate-50 px-3 py-2">
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium text-slate-700">Unaccounted cash{cur}</div>
                    <div className="text-[11px] text-slate-500 truncate">Expected sales minus everything collected (cash + MoMo + bank + credit).</div>
                  </div>
                  <div className={`shrink-0 text-right font-semibold tabular-nums ${shortage > 0 ? "text-rose-600" : overage > 0 ? "text-amber-600" : "text-slate-700"}`}>
                    {shortage > 0 ? gh(shortage) : overage > 0 ? `+${gh(overage)} over` : gh(0)}
                  </div>
                </div>
                {!floatBalanced && (
                  <div className="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-xs text-rose-800">
                    Cash returned ({gh(returnPayments.cashReturnedByDriver ?? 0)}) doesn't match the expected float of {gh(expectedFloatBack)}
                    {expensesTotal > 0 ? ` (opening ${gh(openingCashFloat)} − approved expenses ${gh(expensesTotal)})` : ` (opening cash ${gh(openingCashFloat)})`}.
                    You can still save as Draft, but Approve &amp; Reconcile is blocked until it balances.
                  </div>
                )}
                <div className="flex items-center justify-between gap-3 min-w-0 border-t border-slate-200 pt-3">
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium text-slate-700">Cash returned by driver</div>
                    <div className="text-[11px] text-slate-500 truncate">
                      The driver's float coming back (opening cash, minus any approved cash expenses). Not a sale.
                    </div>
                  </div>
                  <div className="w-40 sm:w-48 shrink-0">
                    <NumberInput
                      className="text-right tabular-nums"
                      min={0}
                      step="0.01"
                      value={returnPayments.cashReturnedByDriver}
                      onChange={(e) =>
                        setReturnPayments({
                          ...returnPayments,
                          cashReturnedByDriver: Number(e.target.value) || 0,
                        })
                      }
                    />
                  </div>
                </div>
              </FormSection>

              {/* Sales Posting Mode. Detailed reveals the per-customer breakdown
                  below; Summary posts to the General Delivery default customer. */}
              <FormSection title="How should this delivery sale be posted?" color="purple" columns={1}>
                <div className="space-y-2 text-sm">
                  <label className={`flex items-start gap-2 ${returnPayments.creditSalesAmount > 0 ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}`}>
                    <input
                      type="radio"
                      className="mt-1"
                      disabled={returnPayments.creditSalesAmount > 0}
                      checked={postingMode === "Summary"}
                      onChange={() => { if (returnPayments.creditSalesAmount <= 0) setPostingMode("Summary") }}
                    />
                    <span><strong>Summary only</strong><br/>
                      <span className="text-slate-500">Posts to the company's <em>General Delivery Customer</em>. No per-shop tracking.</span>
                      {returnPayments.creditSalesAmount > 0 && (
                        <span className="block text-amber-700">Unavailable while there are credit sales — use the detailed breakdown.</span>
                      )}</span>
                  </label>

                  <label className="flex items-start gap-2 cursor-pointer">
                    <input type="radio" className="mt-1" checked={postingMode === "Detailed"} onChange={() => setPostingMode("Detailed")} />
                    <span><strong>Detailed customer breakdown</strong><br/>
                      <span className="text-slate-500">Record real customer/shop sales one-by-one (free-text names for walk-ins). The breakdown appears right below when selected.</span></span>
                  </label>
                </div>
              </FormSection>

              {/* Step 3 only renders in "Detailed" mode. */}
              {postingMode === "Detailed" && (
              <div className="mt-3 border rounded-md">
                <button
                  type="button"
                  onClick={() => setBreakdownOpen(!breakdownOpen)}
                  className="w-full px-3 py-2 flex items-center justify-between text-left bg-slate-50 hover:bg-slate-100 transition"
                >
                  <div className="flex items-center gap-2">
                    {breakdownOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                    <span className="font-medium text-sm">Customer sales breakdown</span>
                    <span className="text-xs text-slate-500">— record each customer/shop sale; posts to Sales + Payments on approve</span>
                  </div>
                  <span className="text-xs text-slate-500">{breakdown.length} customer{breakdown.length === 1 ? "" : "s"}</span>
                </button>

                {breakdownOpen && (
                  <div className="p-3 space-y-3">
                    <div className="flex gap-2">
                      <Button size="sm" variant="outline" onClick={addBreakdownRow}>
                        <Plus className="h-4 w-4 mr-1" /> Add customer sale
                      </Button>
                      <Button size="sm" variant="ghost" onClick={useSummaryOnly}>Use summary only</Button>
                    </div>

                    {breakdown.map((row, rowIdx) => {
                      const lineTotal = row.items.reduce((s, it) => s + (it.quantity * it.unitPrice), 0)
                      const paid = row.cashPaid + row.moMoPaid + row.bankPaid
                      const total = paid + row.creditAmount
                      const mismatch = Math.abs(lineTotal - total) > 0.01
                      return (
                        <div key={rowIdx} className="border rounded-md p-3 space-y-2 bg-white">
                          <div className="flex items-center justify-between gap-2">
                            <div className="font-medium text-sm">Customer {rowIdx + 1}</div>
                            <Button size="sm" variant="ghost" onClick={() => removeBreakdownRow(rowIdx)}>
                              <Trash2 className="h-4 w-4 text-red-500" />
                            </Button>
                          </div>
                          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                            <div><Label>Customer / shop name</Label>
                              <Input value={row.customerLabel} onChange={(e) => updateBreakdownRow(rowIdx, { customerLabel: e.target.value })} placeholder="Walk-in / shop name" /></div>
                            <div><Label>Notes</Label>
                              <Input value={row.notes} onChange={(e) => updateBreakdownRow(rowIdx, { notes: e.target.value })} placeholder="Optional" /></div>
                          </div>

                          {/* Items per row */}
                          <div className="border rounded-md">
                            <div className="flex items-center justify-between px-2 py-1 text-xs bg-slate-50">
                              <span>Items sold to this customer</span>
                              <Button size="sm" variant="ghost" onClick={() => addBreakdownItem(rowIdx)}>
                                <Plus className="h-3 w-3 mr-1" /> Add item
                              </Button>
                            </div>
                            {row.items.length === 0 ? (
                              <div className="px-3 py-2 text-xs text-slate-500">No items yet.</div>
                            ) : (
                              <>
                                <div className="hidden xl:block overflow-x-auto">
                                  <Table>
                                    <TableHeader>
                                      <TableRow>
                                        <TableHead>Product</TableHead>
                                        <TableHead className="text-right">Qty (crates)</TableHead>
                                        <TableHead className="text-right">Price{cur}</TableHead>
                                        <TableHead className="text-right">Total{cur}</TableHead>
                                        <TableHead></TableHead>
                                      </TableRow>
                                    </TableHeader>
                                    <TableBody>
                                      {row.items.map((it, itIdx) => (
                                        <TableRow key={itIdx}>
                                          <TableCell>
                                            <Select value={String(it.poultryProductId)} onValueChange={(v) => {
                                              const id = Number(v)
                                              const p = products.find(x => x.poultryProductId === id)
                                              updateBreakdownItem(rowIdx, itIdx, { poultryProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                                            }}>
                                              <SelectTrigger><SelectValue /></SelectTrigger>
                                              <SelectContent>{products.map(p => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
                                            </Select>
                                          </TableCell>
                                          <TableCell className="text-right">
                                            <NumberInput min={1} value={it.quantity}
                                              onChange={(e) => updateBreakdownItem(rowIdx, itIdx, { quantity: Number(e.target.value) || 0 })}
                                              className="w-16 ml-auto text-right" />
                                          </TableCell>
                                          <TableCell className="text-right">
                                            <NumberInput min={0} step="0.01" value={it.unitPrice}
                                              onChange={(e) => updateBreakdownItem(rowIdx, itIdx, { unitPrice: Number(e.target.value) || 0 })}
                                              className="w-20 ml-auto text-right" />
                                          </TableCell>
                                          <TableCell className="text-right tabular-nums">{gh(it.quantity * it.unitPrice)}</TableCell>
                                          <TableCell>
                                            <Button size="sm" variant="ghost" onClick={() => removeBreakdownItem(rowIdx, itIdx)}>
                                              <Trash2 className="h-4 w-4 text-red-500" />
                                            </Button>
                                          </TableCell>
                                        </TableRow>
                                      ))}
                                    </TableBody>
                                  </Table>
                                </div>

                                <div className="xl:hidden p-2 space-y-2">
                                  {row.items.map((it, itIdx) => (
                                    <div key={itIdx} className="rounded-md border p-2 space-y-2 bg-white">
                                      <div className="flex items-center gap-2">
                                        <div className="flex-1 min-w-0">
                                          <Select value={String(it.poultryProductId)} onValueChange={(v) => {
                                            const id = Number(v)
                                            const p = products.find(x => x.poultryProductId === id)
                                            updateBreakdownItem(rowIdx, itIdx, { poultryProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                                          }}>
                                            <SelectTrigger><SelectValue /></SelectTrigger>
                                            <SelectContent>{products.map(p => <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>)}</SelectContent>
                                          </Select>
                                        </div>
                                        <Button size="sm" variant="ghost" onClick={() => removeBreakdownItem(rowIdx, itIdx)}>
                                          <Trash2 className="h-4 w-4 text-red-500" />
                                        </Button>
                                      </div>
                                      <div className="grid grid-cols-3 gap-2 items-end">
                                        <div>
                                          <label className="text-xs text-slate-500">Qty (crates)</label>
                                          <NumberInput min={1} value={it.quantity}
                                            onChange={(e) => updateBreakdownItem(rowIdx, itIdx, { quantity: Number(e.target.value) || 0 })}
                                            className="text-right" />
                                        </div>
                                        <div>
                                          <label className="text-xs text-slate-500">Price{cur}</label>
                                          <NumberInput min={0} step="0.01" value={it.unitPrice}
                                            onChange={(e) => updateBreakdownItem(rowIdx, itIdx, { unitPrice: Number(e.target.value) || 0 })}
                                            className="text-right" />
                                        </div>
                                        <div className="text-right">
                                          <div className="text-xs text-slate-500">Total</div>
                                          <div className="font-semibold tabular-nums text-sm">{gh(it.quantity * it.unitPrice)}</div>
                                        </div>
                                      </div>
                                    </div>
                                  ))}
                                </div>
                              </>
                            )}
                          </div>

                          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                            <div><Label className="text-xs">Cash paid{cur}</Label>
                              <NumberInput min={0} step="0.01" value={row.cashPaid}
                                onChange={(e) => updateBreakdownRow(rowIdx, { cashPaid: Number(e.target.value) || 0 })} /></div>
                            <div><Label className="text-xs">MoMo paid{cur}</Label>
                              <NumberInput min={0} step="0.01" value={row.moMoPaid}
                                onChange={(e) => updateBreakdownRow(rowIdx, { moMoPaid: Number(e.target.value) || 0 })} /></div>
                            <div><Label className="text-xs">Bank paid{cur}</Label>
                              <NumberInput min={0} step="0.01" value={row.bankPaid}
                                onChange={(e) => updateBreakdownRow(rowIdx, { bankPaid: Number(e.target.value) || 0 })} /></div>
                            <div><Label className="text-xs">Credit{cur}</Label>
                              <NumberInput min={0} step="0.01" value={row.creditAmount}
                                onChange={(e) => updateBreakdownRow(rowIdx, { creditAmount: Number(e.target.value) || 0 })} /></div>
                          </div>

                          <div className={`text-xs flex justify-between items-center pt-1 ${mismatch ? "text-amber-700" : "text-slate-500"}`}>
                            <span>Items total: <strong className="tabular-nums">{gh(lineTotal)}</strong></span>
                            <span>Payments + credit: <strong className="tabular-nums">{gh(total)}</strong></span>
                          </div>
                        </div>
                      )
                    })}

                    {breakdown.length > 0 && (
                      <div className={`text-xs rounded-md border px-3 py-2 ${breakdownBalanced ? "bg-emerald-50 border-emerald-200 text-emerald-800" : "bg-amber-50 border-amber-200 text-amber-800"}`}>
                        {breakdownBalanced ? "✓ Customer breakdown matches the return summary." : (
                          <div className="space-y-0.5">
                            <div>Customer breakdown does not match the return summary.</div>
                            {!breakdownPaymentsBalance && (
                              <div className="font-mono">
                                Cash {gh(breakdownTotals.cash)} vs {gh(returnPayments.cashCollected)} ·
                                MoMo {gh(breakdownTotals.momo)} vs {gh(returnPayments.moMoCollected)} ·
                                Bank {gh(breakdownTotals.bank)} vs {gh(returnPayments.bankCollected)} ·
                                Credit {gh(breakdownTotals.credit)} vs {gh(returnPayments.creditSalesAmount)}
                              </div>
                            )}
                            {!breakdownQtyBalance && <div>Per-product quantities don't match Sold totals.</div>}
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </div>
              )}

              {/* Delivery expenses */}
              <div className="mt-3 border rounded-md">
                <button
                  type="button"
                  onClick={() => setExpensesOpen(!expensesOpen)}
                  className="w-full px-3 py-2 flex items-center justify-between text-left bg-slate-50 hover:bg-slate-100 transition"
                >
                  <div className="flex items-center gap-2">
                    {expensesOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                    <span className="font-medium text-sm">Step 4 · Delivery expenses</span>
                    <span className="text-xs text-slate-500">— fuel, toll, loading boys, etc.</span>
                  </div>
                  <span className="text-xs text-slate-500">{gh(expensesTotal)}</span>
                </button>
                {expensesOpen && (
                  <div className="p-3 space-y-2">
                    <Button size="sm" variant="outline" onClick={addExpense}>
                      <Plus className="h-4 w-4 mr-1" /> Add expense
                    </Button>
                    {expenses.length === 0 ? (
                      <div className="text-xs text-slate-500">No expenses logged.</div>
                    ) : (
                      <>
                        <div className="hidden xl:block overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Category</TableHead>
                                <TableHead className="text-right">Amount{cur}</TableHead>
                                <TableHead>Description</TableHead>
                                <TableHead className="text-center">Approved</TableHead>
                                <TableHead></TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {expenses.map((e, idx) => (
                                <TableRow key={idx}>
                                  <TableCell>
                                    <Select value={e.expenseCategory} onValueChange={(v) => updateExpense(idx, { expenseCategory: v })}>
                                      <SelectTrigger><SelectValue /></SelectTrigger>
                                      <SelectContent>{EXPENSE_CATEGORIES.map(c => <SelectItem key={c} value={c}>{prettyCategory(c)}</SelectItem>)}</SelectContent>
                                    </Select>
                                  </TableCell>
                                  <TableCell className="text-right">
                                    <NumberInput min={0} step="0.01" value={e.amount}
                                      onChange={(ev) => updateExpense(idx, { amount: Number(ev.target.value) || 0 })}
                                      className="w-24 ml-auto text-right" />
                                  </TableCell>
                                  <TableCell>
                                    <Input value={e.description} onChange={(ev) => updateExpense(idx, { description: ev.target.value })} />
                                  </TableCell>
                                  <TableCell className="text-center">
                                    <input type="checkbox" checked={e.isApproved} onChange={(ev) => updateExpense(idx, { isApproved: ev.target.checked })} />
                                  </TableCell>
                                  <TableCell>
                                    <Button size="sm" variant="ghost" onClick={() => removeExpense(idx)}>
                                      <Trash2 className="h-4 w-4 text-red-500" />
                                    </Button>
                                  </TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>

                        <div className="xl:hidden space-y-2">
                          {expenses.map((e, idx) => (
                            <div key={idx} className="rounded-md border bg-white p-3 space-y-2">
                              <div className="grid grid-cols-2 gap-2">
                                <div>
                                  <label className="text-xs text-slate-500">Category</label>
                                  <Select value={e.expenseCategory} onValueChange={(v) => updateExpense(idx, { expenseCategory: v })}>
                                    <SelectTrigger><SelectValue /></SelectTrigger>
                                    <SelectContent>{EXPENSE_CATEGORIES.map(c => <SelectItem key={c} value={c}>{prettyCategory(c)}</SelectItem>)}</SelectContent>
                                  </Select>
                                </div>
                                <div>
                                  <label className="text-xs text-slate-500">Amount{cur}</label>
                                  <NumberInput min={0} step="0.01" value={e.amount}
                                    onChange={(ev) => updateExpense(idx, { amount: Number(ev.target.value) || 0 })}
                                    className="text-right" />
                                </div>
                              </div>
                              <div>
                                <label className="text-xs text-slate-500">Description</label>
                                <Input value={e.description} onChange={(ev) => updateExpense(idx, { description: ev.target.value })} />
                              </div>
                              <div className="flex items-center justify-between gap-2 pt-1">
                                <label className="text-sm flex items-center gap-2 text-slate-700">
                                  <input type="checkbox" checked={e.isApproved} onChange={(ev) => updateExpense(idx, { isApproved: ev.target.checked })} />
                                  Approved
                                </label>
                                <Button size="sm" variant="outline" className="text-red-600 border-red-200 hover:bg-red-50" onClick={() => removeExpense(idx)}>
                                  <Trash2 className="h-4 w-4 mr-1" /> Remove
                                </Button>
                              </div>
                            </div>
                          ))}
                        </div>
                      </>
                    )}
                  </div>
                )}
              </div>

              <FormSection title="Notes" color="slate" columns={1}>
                <FormField label="Notes">
                  <Textarea value={returnNotes} onChange={(e) => setReturnNotes(e.target.value)} />
                </FormField>
              </FormSection>

              {/* Live overall reconciliation */}
              <div className={`rounded-xl border px-4 py-3 text-sm flex flex-wrap items-center justify-between gap-2 ${overallBalanced && perItemBalanced ? "border-emerald-200 bg-emerald-50 text-emerald-800" : "border-rose-200 bg-rose-50 text-rose-800"}`}>
                <span className="min-w-0">
                  Sold {totalSold} + Returned {totalReturned} + Damaged {totalDamaged} = <strong className="tabular-nums">{totalSold + totalReturned + totalDamaged}</strong> of Loaded <strong className="tabular-nums">{totalLoaded}</strong>
                </span>
                <span className="font-semibold whitespace-nowrap">{overallBalanced && perItemBalanced ? "✓ Crates balanced" : "✗ Crates don't balance"}</span>
              </div>

              {creditWithoutCustomer && (
                <div className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-3 py-2">
                  Credit sales are not assigned to customers. Customer balances will not be accurate unless credit is linked via the breakdown.
                </div>
              )}
              {detailedCreditUnassigned && (
                <div className="text-xs text-rose-800 bg-rose-50 border border-rose-200 rounded-md px-3 py-2">
                  One or more customer rows have credit but no customer label. Add a label or tick the admin override below.
                </div>
              )}
              {((isDetailed && breakdownProvided && !breakdownBalanced) || detailedCreditUnassigned) && (
                <label className="text-xs flex items-center gap-2 text-slate-700">
                  <input type="checkbox" checked={overrideMismatch} onChange={(e) => setOverrideMismatch(e.target.checked)} />
                  Admin override — approve anyway
                </label>
              )}

              <div className={`rounded-xl border px-4 py-3 grid grid-cols-2 md:grid-cols-5 gap-2 text-sm ${shortage > 0 ? "border-rose-200 bg-rose-50" : overage > 0 ? "border-amber-200 bg-amber-50" : "border-slate-200 bg-slate-50"}`}>
                <div><div className="text-xs text-slate-500">Expected cash</div><div className="font-semibold tabular-nums">{gh(expectedCash)}</div></div>
                <div><div className="text-xs text-slate-500">Collected</div><div className="font-semibold tabular-nums">{gh(collected)}</div></div>
                <div><div className="text-xs text-slate-500">Shortage</div><div className={`font-semibold tabular-nums ${shortage > 0 ? "text-rose-600" : "text-slate-400"}`}>{gh(shortage)}</div></div>
                <div><div className="text-xs text-slate-500">Overage</div><div className={`font-semibold tabular-nums ${overage > 0 ? "text-green-700" : "text-slate-400"}`}>{gh(overage)}</div></div>
                <div><div className="text-xs text-slate-500">Approved expenses</div><div className="font-semibold tabular-nums">{gh(expensesTotal)}</div></div>
              </div>

              {(!overallBalanced || !perItemBalanced) && (
                <div className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
                  Approve &amp; Reconcile is disabled because the crate counts don't reconcile yet (each product's Sold + Returned + Damaged must equal Loaded).
                </div>
              )}
              <div className="flex flex-col-reverse sm:flex-row gap-2 sm:gap-3 sm:justify-end pt-2">
                <Button type="button" onClick={() => setReturnDlg({ open: false })} className="bg-red-600 hover:bg-red-700 text-white w-full sm:w-auto h-11 sm:h-10">Cancel</Button>
                <Button onClick={() => saveReturn()}
                  disabled={savingReturn || !overallBalanced || !perItemBalanced}
                  title={!overallBalanced || !perItemBalanced ? "Reconcile per-product crates before saving" : "Saves as Draft; approve from the Returns tab"}
                  variant="outline"
                  className="w-full sm:w-auto h-11 sm:h-10"
                >
                  {savingReturn ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Record return (Draft)"}
                </Button>
                <Button onClick={saveAndApproveReconcile}
                  disabled={savingReturn || !overallBalanced || !perItemBalanced}
                  title={
                    (!overallBalanced || !perItemBalanced) ? "Reconcile the crate counts first (Sold + Returned + Damaged = Loaded)."
                    : "Validate, save, and finalize reconciliation in one step."
                  }
                  className="w-full sm:w-auto h-11 sm:h-10 bg-emerald-600 hover:bg-emerald-700 text-white"
                >
                  {savingReturn ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Working…</>) : "Approve & Reconcile"}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Admin-only hard delete of a Cancelled return. */}
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title={`Delete cancelled return #${deleteTarget?.poultryDriverReturnId ?? ""}?`}
        description="This permanently removes the return header, per-product items, customer-sale rows, and delivery expense rows. Only available for Cancelled returns. The action cannot be undone."
        confirmLabel="Delete return"
        successTitle="Cancelled return deleted"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteTarget) await performDeleteCancelledReturn(deleteTarget)
        }}
      />

      {/* Styled Approve & Reconcile confirmation (Draft → Reconciled). */}
      <ConfirmDeleteDialog
        open={!!approveTarget}
        onOpenChange={(o) => { if (!o) setApproveTarget(null) }}
        tone="default"
        title="Approve & reconcile this return?"
        description="This finalizes the return, updates inventory, posts sales/payments if applicable, and marks the delivery as reconciled."
        confirmLabel="Approve & Reconcile"
        busyLabel="Working…"
        successTitle="Return reconciled"
        errorTitle="Approve & Reconcile failed"
        onConfirm={async () => {
          if (approveTarget) {
            await approvePoultryDriverReturn(approveTarget.poultryDriverReturnId)
            await load()
          }
        }}
      />

      {/* Void confirmation. Reverses LoadOut stock when status is Loaded. */}
      <ConfirmDeleteDialog
        open={!!voidTarget}
        onOpenChange={(o) => { if (!o) setVoidTarget(null) }}
        title="Void this delivery?"
        description={voidTarget
          ? `Void delivery ${voidTarget.driverName ?? voidTarget.vehicleName} (${voidTarget.cratesLoaded} crates${voidTarget.expectedCash ? `, expected ${gh(voidTarget.expectedCash)}` : ""})? ${voidTarget.status === "Loaded"
              ? "This will return the crates to warehouse stock via an Adjust transaction. Blocked if a driver return is already recorded."
              : "Draft loadings have no stock to reverse."}`
          : undefined}
        confirmLabel="Void delivery"
        successTitle="Delivery voided — stock returned to warehouse"
        errorTitle="Void failed"
        onConfirm={async () => {
          if (voidTarget) {
            await voidPoultryVehicleLoading(voidTarget.poultryVehicleLoadingId)
            await load()
          }
        }}
      />

      {/* Reverse Reconciliation dialog. The poultry reverse SP takes no reason
          argument, so the collected reason is used only for the operator's own
          confirmation UX. */}
      <PromptDialog
        open={!!reverseTarget}
        onOpenChange={(o) => { if (!o) { setReverseTarget(null); setEditAfterReverse(false) } }}
        title={editAfterReverse ? "Edit reconciled return?" : "Reverse this reconciliation?"}
        description={editAfterReverse ? (
          <>
            There's no direct "update return" endpoint — to change a reconciled
            return we first reverse the current reconciliation (undoing the
            linked sales, payments, inventory movements, customer balance
            updates, and shortage/overage records), then re-open the Record
            Return dialog pre-filled with your existing data so you can change
            what you need. Saving re-records and re-approves.
          </>
        ) : (
          <>
            This will undo the linked sales, payments, inventory movements,
            customer balance updates, and shortage/overage records created by
            this reconciliation. You can then edit and reconcile the delivery
            again.
          </>
        )}
        label={editAfterReverse ? "Reason for edit" : "Reason for reversal"}
        placeholder="e.g. wrong customer assigned / late MoMo correction"
        confirmLabel={editAfterReverse ? "Reverse & edit" : "Reverse"}
        confirmVariant="destructive"
        onSubmit={async () => {
          if (!reverseTarget) return
          const target = reverseTarget
          const wantsEdit = editAfterReverse
          try {
            await reversePoultryDriverReturn(target.poultryDriverReturnId)
            if (wantsEdit) {
              toast({ title: "Reverted — re-opening the return for edit" })
              setReverseTarget(null); setEditAfterReverse(false)
              await load()
              const reloaded = await listPoultryVehicleLoadings()
              const l = reloaded.find(x => x.poultryVehicleLoadingId === target.poultryVehicleLoadingId)
                ?? loadings.find(x => x.poultryVehicleLoadingId === target.poultryVehicleLoadingId)
              if (l) await prefillFromExistingReturn(l, target)
            } else {
              toast({
                title: "Reconciliation reversed",
                description: "The load is back in Active loads — click Record return on it to re-record with the new values.",
              })
              setReverseTarget(null); setEditAfterReverse(false); await load()
            }
          } catch (e: any) {
            toast({ title: editAfterReverse ? "Edit failed" : "Reverse failed", description: e?.message, variant: "destructive" })
          }
        }}
      />
    </div>
  )
}

// Dropdown filters for Driver / Vehicle / Route / Status. Rendered inside
// ListFilters' `extras` slot so the search/date row keeps its layout.
function DeliveryDropdowns({
  drivers, vehicles, routes,
  driver, setDriver, vehicle, setVehicle, route, setRoute, status, setStatus,
  statusOptions,
}: {
  drivers: PoultryDriver[]
  vehicles: PoultryVehicle[]
  routes: PoultryRoute[]
  driver: string; setDriver: (v: string) => void
  vehicle: string; setVehicle: (v: string) => void
  route: string; setRoute: (v: string) => void
  status: string; setStatus: (v: string) => void
  statusOptions: string[]
}) {
  return (
    <div className="flex flex-wrap gap-2">
      <Select value={driver} onValueChange={setDriver}>
        <SelectTrigger className="w-36 h-9 text-xs"><SelectValue placeholder="All drivers" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="ALL">All drivers</SelectItem>
          {drivers.filter(d => d.isActive).map((d) => (
            <SelectItem key={d.poultryDriverId} value={String(d.poultryDriverId)}>{d.driverName}</SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select value={vehicle} onValueChange={setVehicle}>
        <SelectTrigger className="w-36 h-9 text-xs"><SelectValue placeholder="All vehicles" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="ALL">All vehicles</SelectItem>
          {vehicles.filter(v => v.status === "Active").map((v) => (
            <SelectItem key={v.poultryVehicleId} value={String(v.poultryVehicleId)}>{v.vehicleName}</SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select value={route} onValueChange={setRoute}>
        <SelectTrigger className="w-36 h-9 text-xs"><SelectValue placeholder="All routes" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="ALL">All routes</SelectItem>
          {routes.map((r) => (
            <SelectItem key={r.poultryRouteId} value={String(r.poultryRouteId)}>{r.routeName}</SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select value={status} onValueChange={setStatus}>
        <SelectTrigger className="w-32 h-9 text-xs"><SelectValue placeholder="All statuses" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="ALL">All statuses</SelectItem>
          {statusOptions.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
        </SelectContent>
      </Select>
    </div>
  )
}

// Compact loadings table reused in both Active and Reconciled tabs.
function DeliveriesTable({
  rows, onRecordReturn, onVoid, onReload, onReverse, onEditReconciled, showActions,
}: {
  rows: PoultryVehicleLoading[]
  onRecordReturn: (l: PoultryVehicleLoading) => void
  onVoid: (l: PoultryVehicleLoading) => void
  onReload?: (l: PoultryVehicleLoading) => void
  onReverse?: (l: PoultryVehicleLoading) => void
  onEditReconciled?: (l: PoultryVehicleLoading) => void
  showActions: boolean
}) {
  // Client-side paging for the deliveries (vehicle loadings) list.
  const pg = usePagination(rows)
  return (
    <MobileCardList
      items={pg.pageItems}
      pagination={pg.paginationProps}
      getKey={(l) => l.poultryVehicleLoadingId}
      primary={(l) => (
        <Link href={`/poultry-driver-returns/${l.poultryVehicleLoadingId}`} className="text-sky-700 hover:underline">
          {l.driverName ?? "—"} · {l.loadDate.split("T")[0]}
        </Link>
      )}
      secondary={(l) => (
        <>
          <span>{l.vehicleName ?? "—"}</span>
          <Badge className={LOAD_STATUS[l.status] ?? ""}>{l.status}</Badge>
        </>
      )}
      details={(l) => [
        { label: "Date", value: l.loadDate.split("T")[0] },
        { label: "Driver", value: l.driverName ?? "—" },
        { label: "Vehicle", value: l.vehicleName ?? "—" },
        { label: "Route", value: l.routeName ?? "—" },
        { label: "Loaded (crates)", value: l.cratesLoaded },
        { label: `Expected${cur}`, value: gh(l.expectedCash ?? 0) },
        { label: "Status", value: l.status },
      ]}
      actions={(l) => (
        <>
          <Button asChild size="sm" variant="outline" className="flex-1 h-10">
            <Link href={`/poultry-driver-returns/${l.poultryVehicleLoadingId}`}>View details</Link>
          </Button>
          {showActions && l.status === "Loaded" && (
            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => onRecordReturn(l)}>
              Record return
            </Button>
          )}
          {showActions && onReload && (l.status === "Loaded" || l.status === "Draft") && (
            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => onReload(l)}>
              Reload
            </Button>
          )}
          {showActions && (l.status === "Loaded" || l.status === "Draft") && (
            <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => onVoid(l)}>
              <XCircle className="h-4 w-4 mr-1" /> Void
            </Button>
          )}
          {onEditReconciled && l.status === "Reconciled" && (
            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => onEditReconciled(l)}>
              <Pencil className="h-4 w-4 mr-1" /> Edit
            </Button>
          )}
          {onReverse && l.status === "Reconciled" && (
            <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => onReverse(l)}>
              <Undo2 className="h-4 w-4 mr-1" /> Reverse
            </Button>
          )}
        </>
      )}
      desktopTable={
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead>
                <TableHead>Driver</TableHead>
                <TableHead>Vehicle</TableHead>
                <TableHead>Route</TableHead>
                <TableHead className="text-right">Loaded (crates)</TableHead>
                <TableHead className="text-right">Expected{cur}</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((l) => (
                <TableRow key={l.poultryVehicleLoadingId}>
                  <TableCell>
                    <Link href={`/poultry-driver-returns/${l.poultryVehicleLoadingId}`} className="text-sky-700 hover:underline">
                      {l.loadDate.split("T")[0]}
                    </Link>
                  </TableCell>
                  <TableCell>{l.driverName ?? "—"}</TableCell>
                  <TableCell>{l.vehicleName ?? "—"}</TableCell>
                  <TableCell>{l.routeName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{l.cratesLoaded}</TableCell>
                  <TableCell className="text-right tabular-nums">{gh(l.expectedCash ?? 0)}</TableCell>
                  <TableCell><Badge className={LOAD_STATUS[l.status] ?? ""}>{l.status}</Badge></TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    <Button asChild size="sm" variant="ghost" title="View details">
                      <Link href={`/poultry-driver-returns/${l.poultryVehicleLoadingId}`}><Eye className="h-4 w-4" /></Link>
                    </Button>
                    {showActions && l.status === "Loaded" && <Button size="sm" onClick={() => onRecordReturn(l)}>Record return</Button>}
                    {showActions && onReload && (l.status === "Loaded" || l.status === "Draft") && (
                      <Button size="sm" variant="ghost" onClick={() => onReload(l)} title="Reload — clone into a fresh run">
                        <RefreshCw className="h-4 w-4 text-sky-600" />
                      </Button>
                    )}
                    {showActions && (l.status === "Loaded" || l.status === "Draft") && (
                      <Button size="sm" variant="ghost" onClick={() => onVoid(l)} title="Void this delivery (reverses stock)">
                        <XCircle className="h-4 w-4 text-rose-500" />
                      </Button>
                    )}
                    {onEditReconciled && l.status === "Reconciled" && (
                      <Button size="sm" variant="ghost" onClick={() => onEditReconciled(l)} title="Edit this reconciled return (reverses + re-opens for edit)">
                        <Pencil className="h-4 w-4 text-sky-700" />
                      </Button>
                    )}
                    {onReverse && l.status === "Reconciled" && (
                      <Button size="sm" variant="ghost" onClick={() => onReverse(l)} title="Reverse reconciliation">
                        <Undo2 className="h-4 w-4 text-amber-600" />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      }
    />
  )
}

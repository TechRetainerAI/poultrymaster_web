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
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Plus, Loader2, Truck, XCircle, Trash2, Info, ChevronDown, ChevronRight,
  Users2, MapPin, Undo2, RefreshCw, Eye, CheckCircle2, Pencil,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  listWaterVehicleLoadings, createWaterVehicleLoading, approveWaterVehicleLoading, voidWaterVehicleLoading,
  listWaterDriverReturns, createWaterDriverReturn, approveWaterDriverReturn, cancelWaterDriverReturn,
  reverseWaterDriverReturn, uncancelWaterDriverReturn, deleteWaterDriverReturn,
  listWaterVehicleLoadingItems, listWaterDriverReturnItems,
  // Restore the saved customer breakdown + delivery expenses when editing a return.
  listWaterDriverReturnCustomerSales, listWaterDriverReturnExpenses,
  listWaterVehicles, listWaterRoutes, listWaterProducts, listWaterDrivers, listWaterStaff, listWaterCustomers,
  // Migration 083 — Approve & Reconcile in one shot + posting-mode persistence.
  approveReconcileWaterDriverReturn, updateWaterDriverReturnPostingMode,
  type WaterVehicleLoading, type WaterDriverReturn, type WaterVehicle, type WaterRoute, type WaterProduct,
  type WaterDriver, type WaterStaff, type WaterCustomer,
  type WaterVehicleLoadingItem,
} from "@/lib/api/water"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { fmtMoney, useCurrency } from "@/lib/currency"

const gh = (n: number) => fmtMoney(n)

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
  waterProductId: number
  bagsLoaded: number
  unitPrice: number
  sachetsPerBag: number
  notes: string
}

type ReturnItem = {
  waterProductId: number
  productName: string
  bagsLoaded: number   // snapshot from loading items
  bagsSold: number
  bagsReturned: number
  bagsDamaged: number
  unitPrice: number
}

type BreakdownItem = {
  waterProductId: number
  quantity: number
  unitPrice: number
}

type BreakdownRow = {
  waterCustomerId: number | null
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

export default function WaterDriverReturnsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  // Gate admin-only actions (Delete on a Cancelled return — James 2026-05-30).
  // Staff users see no Delete button at all; the backend SP also rejects
  // delete on non-Cancelled rows, so this is defence-in-depth.
  const permissions = usePermissions()

  // Column-header / Stat-card unit suffix. Same store fmtMoney reads, so the
  // headers flip with the "Show currency symbol" setup toggle and reflect the
  // current symbol (GHC / $ / ₵ / …) instead of being hardcoded to GHC.
  const { symbol, showSymbol } = useCurrency()
  // James (2026-05-30): currency symbols belong on the *values* (driven by
  // fmtMoney + the showCurrencySymbol toggle), never duplicated into the
  // column header. Force empty so headers stay clean regardless of toggle.
  const cur = ""

  // Synchronous re-entry locks. State-based "disabled" relies on React
  // re-rendering before the next click registers, which isn't reliable on
  // rapid double-clicks — James reported one click producing two delivery
  // runs (~3s apart). Refs flip immediately so the second invocation aborts.
  const loadInflight = useRef(false)
  const returnInflight = useRef(false)

  // Confirmation dialog for the X (void) action on a Loaded delivery row.
  const [voidTarget, setVoidTarget] = useState<WaterVehicleLoading | null>(null)
  // Migration 068 — Reverse Reconciliation. Captures the WaterDriverReturn
  // about to be reversed so the PromptDialog can prompt for a reason.
  const [reverseTarget, setReverseTarget] = useState<WaterDriverReturn | null>(null)
  // James (2026-05-30): "Edit" on a Reconciled row reuses the same Reverse SP
  // (no Update endpoint exists) — after reverse we re-open the Record Return
  // dialog pre-filled with the existing return, the operator changes what they
  // need, Save re-creates + re-approves. This flag tells the PromptDialog's
  // onSubmit which behavior to run after the reverse succeeds.
  const [editAfterReverse, setEditAfterReverse] = useState(false)

  // Prompt 2 Part 1 §1 — explicit Approve + Cancel for Draft returns. The
  // happy path creates+approves in one shot (createWaterDriverReturn already
  // calls approve internally); these handlers cover Drafts that were left
  // behind by a partial save (e.g. approve failed after insert).
  // Open the styled confirmation; the dialog (below) runs the actual SP.
  function approveDraftReturn(r: WaterDriverReturn) {
    setApproveTarget(r)
  }

  async function cancelDraftReturn(r: WaterDriverReturn) {
    try { await cancelWaterDriverReturn(r.waterDriverReturnId); toast({ title: "Return cancelled" }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }
  // James (2026-05-30): Uncancel a Cancelled return so it can be re-approved.
  // Migration 071 SP only flips Cancelled → Draft (RAISERROR otherwise).
  async function uncancelDraftReturn(r: WaterDriverReturn) {
    try { await uncancelWaterDriverReturn(r.waterDriverReturnId); toast({ title: "Return uncancelled — back to Draft. Approve to reconcile." }); await load() }
    catch (e: any) { toast({ title: "Uncancel failed", description: e?.message, variant: "destructive" }) }
  }
  // James (2026-05-30): admin-only hard delete of a Cancelled return. Two
  // belts: UI button only renders when permissions.isAdmin, and the SP
  // RAISERRORs if Status != 'Cancelled'.
  const [deleteTarget, setDeleteTarget] = useState<WaterDriverReturn | null>(null)
  // Styled approve-&-reconcile confirmation (replaces the native window.confirm).
  const [approveTarget, setApproveTarget] = useState<WaterDriverReturn | null>(null)
  async function performDeleteCancelledReturn(r: WaterDriverReturn) {
    try { await deleteWaterDriverReturn(r.waterDriverReturnId); toast({ title: `Cancelled return #${r.waterDriverReturnId} deleted` }); await load() }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  // James (2026-05-30): "on the return page, we need one more action called:
  // Edit". When the operator closes the Edit-on-Reconciled dialog without
  // saving, the row is now sitting in the Returns tab as Draft and there was
  // no way to pick the edit back up. This handler closes that loop — it
  // re-opens the Record Return dialog pre-filled with the existing return,
  // and on save it cancels the old Draft so the user keeps exactly one
  // active Draft per loading.
  const editReturnTargetRef = useRef<WaterDriverReturn | null>(null)
  function openEditReturnDlg(r: WaterDriverReturn) {
    const l = loadings.find(x => x.waterVehicleLoadingId === r.waterVehicleLoadingId)
    if (!l) {
      toast({ title: "Loading not found", description: "Can't find the delivery run this return belongs to.", variant: "destructive" })
      return
    }
    editReturnTargetRef.current = r
    void prefillFromExistingReturn(l, r)
  }
  // Migration 068 / Prompt 2 §4 — Reload / Edit Load. Opens an inline dialog
  // for editing the header fields on a Draft/Loaded run. Item edits are
  // deferred to the existing items list (kept as a separate task to avoid
  // accidentally clobbering line totals).
  const [reloadTarget, setReloadTarget] = useState<WaterVehicleLoading | null>(null)
  const [reloadForm, setReloadForm] = useState<{
    waterDriverId: number | null
    waterVehicleId: number | null
    waterRouteId: number | null
    openingCashWithDriver: number
    notes: string
  }>({ waterDriverId: null, waterVehicleId: null, waterRouteId: null, openingCashWithDriver: 0, notes: "" })
  const [reloadBusy, setReloadBusy] = useState(false)

  function openReloadDlg(l: WaterVehicleLoading) {
    setReloadTarget(l)
    setReloadForm({
      waterDriverId:  l.waterDriverId ?? null,
      waterVehicleId: l.waterVehicleId ?? null,
      waterRouteId:   l.waterRouteId  ?? null,
      openingCashWithDriver: l.openingCashWithDriver ?? 0,
      notes: l.notes ?? "",
    })
  }

  async function saveReload() {
    if (!reloadTarget) return
    setReloadBusy(true)
    try {
      const { reloadWaterVehicleLoading } = await import("@/lib/api/water")
      await reloadWaterVehicleLoading(reloadTarget.waterVehicleLoadingId, {
        waterDriverId:  reloadForm.waterDriverId,
        waterVehicleId: reloadForm.waterVehicleId,
        waterRouteId:   reloadForm.waterRouteId,
        openingCashWithDriver: reloadForm.openingCashWithDriver,
        notes: reloadForm.notes,
        // items: null → SP leaves item rows + their stock txns alone. We can
        // wire the items editor later (the SP already accepts the JSON).
        items: null,
      })
      toast({ title: "Delivery updated" })
      setReloadTarget(null); await load()
    } catch (e: any) {
      toast({ title: "Reload failed", description: e?.message, variant: "destructive" })
    } finally { setReloadBusy(false) }
  }

  const [loadings, setLoadings] = useState<WaterVehicleLoading[]>([])
  const [returns, setReturns] = useState<WaterDriverReturn[]>([])
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [routes, setRoutes] = useState<WaterRoute[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [drivers, setDrivers] = useState<WaterDriver[]>([])
  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [customers, setCustomers] = useState<WaterCustomer[]>([])
  const [loading, setLoading] = useState(true)

  // ===== Search/date filters (Active loads + Returns tabs) =====
  const [loadingsSearch, setLoadingsSearch] = useState("")
  const [loadingsDateFrom, setLoadingsDateFrom] = useState("")
  const [loadingsDateTo, setLoadingsDateTo] = useState("")
  const [returnsSearch, setReturnsSearch] = useState("")
  const [returnsDateFrom, setReturnsDateFrom] = useState("")
  const [returnsDateTo, setReturnsDateTo] = useState("")
  // Migration 068 / Prompt 2 §5 — precise dropdown filters that work in
  // combination with the free-text search. "ALL" disables the filter.
  const [filterDriver,  setFilterDriver]  = useState<string>("ALL")
  const [filterVehicle, setFilterVehicle] = useState<string>("ALL")
  const [filterRoute,   setFilterRoute]   = useState<string>("ALL")
  const [filterStatus,  setFilterStatus]  = useState<string>("ALL")

  const matchesDropdowns = (row: { waterDriverId?: number | null, waterVehicleId?: number | null, waterRouteId?: number | null, status?: string | null }) => {
    if (filterDriver  !== "ALL" && String(row.waterDriverId  ?? "") !== filterDriver)  return false
    if (filterVehicle !== "ALL" && String(row.waterVehicleId ?? "") !== filterVehicle) return false
    if (filterRoute   !== "ALL" && String(row.waterRouteId   ?? "") !== filterRoute)   return false
    if (filterStatus  !== "ALL" && (row.status ?? "") !== filterStatus)                 return false
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
      // Returns rows don't carry driver/vehicle/route ids directly — resolve
      // via the parent loading.
      const parent = loadings.find(l => l.waterVehicleLoadingId === r.waterVehicleLoadingId)
      return matchesDropdowns({
        waterDriverId:  parent?.waterDriverId,
        waterVehicleId: parent?.waterVehicleId,
        waterRouteId:   parent?.waterRouteId,
        status:         r.status,
      })
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [returns, loadings, returnsSearch, returnsDateFrom, returnsDateTo, filterDriver, filterVehicle, filterRoute, filterStatus],
  )

  // ===== Load Vehicle dialog state =====
  const [loadDlg, setLoadDlg] = useState(false)
  const [loadForm, setLoadForm] = useState({
    waterVehicleId: 0,
    waterDriverId: 0 as number | 0,
    assistantStaffId: 0 as number | 0,
    waterRouteId: 0,
    openingCashWithDriver: 0,
    notes: "",
    // #29 — operator can pick the load date (defaults to today).
    loadDate: new Date().toISOString().split("T")[0],
  })
  const [loadItems, setLoadItems] = useState<LoadItem[]>([])
  const [savingLoad, setSavingLoad] = useState(false)
  // James (2026-05-30): "After loading a vehicle, when you click on edit, it
  // should open the same dialog we used when loading the vehicle." Reuse the
  // Load Vehicle dialog for editing too — when this is set, saveLoad calls
  // reloadWaterVehicleLoading instead of createWaterVehicleLoading.
  const [editLoadTarget, setEditLoadTarget] = useState<WaterVehicleLoading | null>(null)

  // ===== Driver Return dialog state =====
  const [returnDlg, setReturnDlg] = useState<{ open: boolean; loading?: WaterVehicleLoading }>({ open: false })
  const [returnItems, setReturnItems] = useState<ReturnItem[]>([])
  const [returnPayments, setReturnPayments] = useState({
    cashCollected: 0,
    moMoCollected: 0,
    bankCollected: 0,
    creditSalesAmount: 0,
    cashReturnedByDriver: 0,
  })
  const [returnNotes, setReturnNotes] = useState("")
  // Operator-pickable return date (defaults to today; editable, incl. on edit).
  const [returnDate, setReturnDate] = useState(new Date().toISOString().split("T")[0])
  const [breakdownOpen, setBreakdownOpen] = useState(false)
  const [breakdown, setBreakdown] = useState<BreakdownRow[]>([])
  const [expensesOpen, setExpensesOpen] = useState(false)
  const [expenses, setExpenses] = useState<ExpenseRow[]>([])
  const [savingReturn, setSavingReturn] = useState(false)
  const [overrideMismatch, setOverrideMismatch] = useState(false)
  // Migration 083 — sales posting mode + primary customer.
  //   Detailed     = use customer breakdown rows (legacy)
  //   OneCustomer  = post entire delivery sale to primaryCustomerId
  //   Summary      = post to GeneralDelivery default customer
  // #15: default to "Post all sales to one customer".
  const [postingMode, setPostingMode] = useState<"Detailed" | "OneCustomer" | "Summary">("OneCustomer")
  const [primaryCustomerId, setPrimaryCustomerId] = useState<number | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // #15: "Summary only" is not allowed once there are credit sales — flip the
  // operator to the detailed/one-customer flow so the credit lands on a real customer.
  useEffect(() => {
    if (postingMode === "Summary" && returnPayments.creditSalesAmount > 0) setPostingMode("OneCustomer")
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [returnPayments.creditSalesAmount, postingMode])

  async function load() {
    setLoading(true)
    // Each lookup is independent — a single 5xx on listWaterStaff shouldn't
    // hide the loadings the user just saved. We run them in parallel but
    // tolerate per-call failures, and only surface a banner when EVERY call
    // failed (i.e. the user is offline or the API is fully down). This was
    // James's "it worked but the red still comes" report: a successful save
    // followed by a partial reload failure was lighting up the banner.
    const results = await Promise.allSettled([
      listWaterVehicleLoadings(), listWaterDriverReturns(),
      listWaterVehicles(), listWaterRoutes(), listWaterProducts(),
      listWaterDrivers(), listWaterStaff(), listWaterCustomers(),
    ])
    const [ls, rs, vs, rts, ps, ds, st, cs] = results
    const failures: string[] = []
    if (ls.status === "fulfilled") setLoadings(ls.value)         ; else failures.push(`loadings: ${ls.reason?.message ?? ls.reason}`)
    if (rs.status === "fulfilled") setReturns(rs.value)          ; else failures.push(`returns: ${rs.reason?.message ?? rs.reason}`)
    if (vs.status === "fulfilled") setVehicles(vs.value)         ; else failures.push(`vehicles: ${vs.reason?.message ?? vs.reason}`)
    if (rts.status === "fulfilled") setRoutes(rts.value)         ; else failures.push(`routes: ${rts.reason?.message ?? rts.reason}`)
    if (ps.status === "fulfilled") {
      // Only finished goods can be loaded onto a delivery.
      setProducts(ps.value.filter(p => (p.productType ?? "FinishedGood") === "FinishedGood"))
    } else failures.push(`products: ${ps.reason?.message ?? ps.reason}`)
    if (ds.status === "fulfilled") setDrivers(ds.value)          ; else failures.push(`drivers: ${ds.reason?.message ?? ds.reason}`)
    if (st.status === "fulfilled") setStaff(st.value)            ; else failures.push(`staff: ${st.reason?.message ?? st.reason}`)
    if (cs.status === "fulfilled") setCustomers(cs.value)        ; else failures.push(`customers: ${cs.reason?.message ?? cs.reason}`)

    if (failures.length === results.length) {
      toast({ title: "Couldn't load this page", description: failures[0], variant: "destructive" })
    } else if (failures.length > 0) {
      // Partial failure — log to console but don't block the UI. The save
      // toast (if any) is the right place for action feedback.
      console.warn("water-driver-returns partial reload failure:", failures)
    }
    setLoading(false)
  }

  // ===== Load Vehicle handlers =====
  function openLoadDlg() {
    const v = vehicles.find(v => v.status === "Active")
    setLoadForm({
      waterVehicleId: v?.waterVehicleId ?? 0,
      waterDriverId: drivers.find(d => d.isActive)?.waterDriverId ?? 0,
      assistantStaffId: 0,
      waterRouteId: routes[0]?.waterRouteId ?? 0,
      openingCashWithDriver: 0,
      notes: "",
      loadDate: new Date().toISOString().split("T")[0],
    })
    // Seed with a single product line — single-product companies see one row,
    // multi-product companies just click "Add product".
    setLoadItems(products.length > 0
      ? [{ waterProductId: products[0].waterProductId, bagsLoaded: 0, unitPrice: products[0].unitPrice ?? 0, sachetsPerBag: 30, notes: "" }]
      : [],
    )
    setLoadDlg(true)
  }

  // James (2026-05-30): Edit-an-existing-load reuses the Load Vehicle dialog
  // (not the stripped-down Reload dialog) so the operator can change products
  // and quantities too, not just driver/vehicle/route.
  async function openEditLoadDlg(l: WaterVehicleLoading) {
    setEditLoadTarget(l)
    setLoadForm({
      waterVehicleId:        l.waterVehicleId,
      waterDriverId:         l.waterDriverId         ?? 0,
      assistantStaffId:      l.assistantStaffId      ?? 0,
      waterRouteId:          l.waterRouteId          ?? 0,
      openingCashWithDriver: l.openingCashWithDriver ?? 0,
      notes:                 l.notes                 ?? "",
      loadDate:              (l.loadDate ?? new Date().toISOString()).split("T")[0],
    })
    // Pre-fill the items the same way openReturnDlg does so the operator sees
    // their previously-loaded products/quantities/prices, ready to edit.
    try {
      const items = await listWaterVehicleLoadingItems(l.waterVehicleLoadingId)
      setLoadItems(items.length > 0
        ? items.map(it => ({
            waterProductId: it.waterProductId,
            bagsLoaded:     it.bagsLoaded,
            unitPrice:      it.unitPrice ?? 0,
            sachetsPerBag:  it.sachetsPerBag ?? 30,
            notes:          it.notes ?? "",
          }))
        : (l.waterProductId
            ? [{ waterProductId: l.waterProductId, bagsLoaded: l.bagsLoaded, unitPrice: l.expectedSellingPricePerBag ?? 0, sachetsPerBag: l.sachetsPerBag ?? 30, notes: "" }]
            : []))
    } catch (e) {
      console.warn("could not pre-fill load items for edit", e)
      setLoadItems([])
    }
    setLoadDlg(true)
  }

  function addLoadItem() {
    const taken = new Set(loadItems.map(i => i.waterProductId))
    const next = products.find(p => !taken.has(p.waterProductId)) ?? products[0]
    if (!next) return toast({ title: "No more products to add", variant: "destructive" })
    setLoadItems([
      ...loadItems,
      { waterProductId: next.waterProductId, bagsLoaded: 0, unitPrice: next.unitPrice ?? 0, sachetsPerBag: 30, notes: "" },
    ])
  }

  function removeLoadItem(idx: number) {
    setLoadItems(loadItems.filter((_, i) => i !== idx))
  }

  function updateLoadItem(idx: number, patch: Partial<LoadItem>) {
    setLoadItems(loadItems.map((it, i) => i === idx ? { ...it, ...patch } : it))
  }

  async function saveLoad() {
    // First gate: synchronous re-entry block. Without this, a 100ms double-tap
    // creates two delivery runs because React state-based `disabled` waits a
    // render tick. We saw this in prod (loadings #10/#11, 3s apart).
    if (loadInflight.current) return
    if (!loadForm.waterVehicleId) return toast({ title: "Pick a vehicle", variant: "destructive" })
    if (!loadForm.waterDriverId) return toast({ title: "Driver is required", description: "Drivers carry the stock and the money — the system needs to know who.", variant: "destructive" })
    if (loadItems.length === 0) return toast({ title: "Add at least one product line", variant: "destructive" })
    if (loadItems.some(i => !i.waterProductId || i.bagsLoaded <= 0)) {
      return toast({ title: "Each line needs a product and a quantity > 0", variant: "destructive" })
    }
    const dupes = new Set<number>()
    for (const it of loadItems) {
      if (dupes.has(it.waterProductId)) return toast({ title: "Duplicate product line", description: "Each product can only appear once per load.", variant: "destructive" })
      dupes.add(it.waterProductId)
    }

    loadInflight.current = true
    setSavingLoad(true)
    try {
      const itemsPayload = loadItems.map(it => ({
        waterProductId: it.waterProductId,
        bagsLoaded:     it.bagsLoaded,
        unitPrice:      it.unitPrice,
        sachetsPerBag:  it.sachetsPerBag,
        notes:          it.notes || null,
      }))

      if (editLoadTarget) {
        // Edit path: reuse the same dialog, but call the reload SP which
        // reverses old stock-out txns and applies new ones atomically.
        const { reloadWaterVehicleLoading } = await import("@/lib/api/water")
        await reloadWaterVehicleLoading(editLoadTarget.waterVehicleLoadingId, {
          waterDriverId:         loadForm.waterDriverId  || null,
          waterVehicleId:        loadForm.waterVehicleId || null,
          waterRouteId:          loadForm.waterRouteId   || null,
          openingCashWithDriver: loadForm.openingCashWithDriver,
          notes:                 loadForm.notes,
          loadDate:              new Date(loadForm.loadDate).toISOString(),
          items:                 itemsPayload,
        } as any)
        toast({ title: "Delivery run updated" })
      } else {
        const created = await createWaterVehicleLoading({
          waterVehicleId:        loadForm.waterVehicleId,
          waterDriverId:         loadForm.waterDriverId    || null as any,
          assistantStaffId:      loadForm.assistantStaffId || null as any,
          waterRouteId:          loadForm.waterRouteId     || null as any,
          openingCashWithDriver: loadForm.openingCashWithDriver,
          notes:                 loadForm.notes,
          loadDate:              new Date(loadForm.loadDate).toISOString(),
          // bagsLoaded is required by the existing API type; the SP recomputes
          // it from the items array when present. Send a dummy value to satisfy
          // TS — the SP ignores it.
          bagsLoaded:            0,
          items:                 itemsPayload,
        } as any)
        // Approve immediately so stock moves out — matches the "load and go"
        // operator flow. The create makes a Draft; approve promotes it to
        // Loaded. If approve fails we must NOT leave the orphan Draft behind —
        // it shows up as a confusing "duplicate" next to the real Loaded row.
        if (!created?.waterVehicleLoadingId) {
          throw new Error("The load was created but the server did not return its id — please retry.")
        }
        try {
          await approveWaterVehicleLoading(created.waterVehicleLoadingId)
        } catch (apErr: any) {
          // Roll back the stuck Draft so it can't masquerade as a duplicate.
          try { await voidWaterVehicleLoading(created.waterVehicleLoadingId, "Auto-voided: load could not be confirmed") } catch { /* best effort */ }
          throw new Error(apErr?.message ? `Load could not be confirmed: ${apErr.message}` : "Load could not be confirmed — please retry.")
        }
        toast({ title: "Delivery run loaded — stock moved out" })
      }
      setLoadDlg(false); setEditLoadTarget(null); await load()
    } catch (e: any) { toast({ title: editLoadTarget ? "Update failed" : "Load failed", description: e?.message, variant: "destructive" }) }
    finally { setSavingLoad(false); loadInflight.current = false }
  }

  // James (2026-05-30): "Edit" on a Reconciled row. There's no Update SP for
  // returns — the supported way to change one is reverse-then-re-record. This
  // handler kicks off that flow: find the linked Approved return, fire the
  // PromptDialog with editAfterReverse=true; the dialog's onSubmit handles
  // the reverse + pre-fill + reopen-Record-Return sequence.
  function openEditReconciledDlg(l: WaterVehicleLoading) {
    const r = returns.find(x => x.waterVehicleLoadingId === l.waterVehicleLoadingId && x.status === "Approved")
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
  // successful reverse so the Record Return dialog opens with what the
  // operator previously recorded (instead of the "all sold, no money" default).
  async function prefillFromExistingReturn(l: WaterVehicleLoading, r: WaterDriverReturn) {
    setReturnNotes(r.notes ?? "")
    setReturnDate((r.returnDate ?? new Date().toISOString()).split("T")[0])
    setBreakdownOpen(false)
    setExpensesOpen(false)
    setBreakdown([])
    setExpenses([])
    setOverrideMismatch(false)
    // Restore how the sale was posted + which customer it was posted to, so the
    // dialog reopens on the same option the operator originally chose (instead
    // of resetting to the OneCustomer default with no customer selected).
    const mode = (r.salesPostingMode === "Detailed" || r.salesPostingMode === "OneCustomer" || r.salesPostingMode === "Summary")
      ? r.salesPostingMode
      : "OneCustomer"
    setPostingMode(mode)
    setPrimaryCustomerId(r.primaryCustomerId ?? null)
    setReturnPayments({
      cashCollected:      r.cashCollected      ?? 0,
      moMoCollected:      r.moMoCollected      ?? 0,
      bankCollected:      r.bankCollected      ?? 0,
      creditSalesAmount:  r.creditSalesAmount  ?? 0,
      cashReturnedByDriver: r.cashReturnedByDriver ?? (l.openingCashWithDriver ?? 0),
    })
    setReturnDlg({ open: true, loading: l })
    try {
      // Items, saved per-customer breakdown, and delivery expenses in parallel.
      const [items, customerSales, savedExpenses] = await Promise.all([
        listWaterDriverReturnItems(r.waterDriverReturnId),
        listWaterDriverReturnCustomerSales(r.waterDriverReturnId).catch(() => []),
        listWaterDriverReturnExpenses(r.waterDriverReturnId).catch(() => []),
      ])

      if (items.length > 0) {
        setReturnItems(items.map(it => ({
          waterProductId: it.waterProductId,
          productName: it.productName ?? products.find(p => p.waterProductId === it.waterProductId)?.name ?? `Product #${it.waterProductId}`,
          bagsLoaded: it.bagsLoaded ?? 0,
          bagsSold: it.bagsSold,
          bagsReturned: it.bagsReturned,
          bagsDamaged: it.bagsDamaged,
          unitPrice: it.unitPrice ?? 0,
        })))
      } else {
        // Fallback: treat as fresh return-from-loading. Same behavior as
        // openReturnDlg in the no-items case.
        await openReturnDlg(l)
      }

      // Restore the detailed customer breakdown (Detailed mode).
      if (customerSales.length > 0) {
        setBreakdown(customerSales.map(cs => ({
          waterCustomerId: cs.waterCustomerId ?? null,
          customerLabel: cs.customerLabel ?? cs.customerName ?? "",
          cashPaid: cs.cashPaid ?? 0,
          moMoPaid: cs.moMoPaid ?? 0,
          bankPaid: cs.bankPaid ?? 0,
          creditAmount: cs.creditAmount ?? 0,
          notes: cs.notes ?? "",
          items: (cs.items ?? []).map(it => ({
            waterProductId: it.waterProductId,
            quantity: it.quantity,
            unitPrice: it.unitPrice ?? 0,
          })),
        })))
        if (mode === "Detailed") setBreakdownOpen(true)
      }

      // Restore the delivery expenses (fuel, toll, chop money, etc.).
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
  async function openReturnDlg(l: WaterVehicleLoading) {
    setReturnNotes("")
    setReturnDate((l.loadDate ?? new Date().toISOString()).split("T")[0])
    setBreakdownOpen(false)
    setExpensesOpen(false)
    setBreakdown([])
    setExpenses([])
    setOverrideMismatch(false)
    setReturnPayments({
      cashCollected: 0, moMoCollected: 0, bankCollected: 0,
      creditSalesAmount: 0, cashReturnedByDriver: l.openingCashWithDriver ?? 0,
    })
    setReturnDlg({ open: true, loading: l })
    // Pull the multi-product items if the loading was created with them.
    try {
      const items = await listWaterVehicleLoadingItems(l.waterVehicleLoadingId)
      if (items.length > 0) {
        setReturnItems(items.map(it => ({
          waterProductId: it.waterProductId,
          productName: it.productName ?? products.find(p => p.waterProductId === it.waterProductId)?.name ?? `Product #${it.waterProductId}`,
          bagsLoaded: it.bagsLoaded,
          // Default actuals to "all sold" — the operator can quickly accept
          // when nothing came back, or adjust when there were returns.
          bagsSold: it.bagsLoaded,
          bagsReturned: 0,
          bagsDamaged: 0,
          unitPrice: it.unitPrice ?? 0,
        })))
      } else {
        // Legacy single-product loading.
        setReturnItems([{
          waterProductId: l.waterProductId ?? 0,
          productName: l.productName ?? products.find(p => p.waterProductId === l.waterProductId)?.name ?? "Product",
          bagsLoaded: l.bagsLoaded,
          bagsSold: l.bagsLoaded, bagsReturned: 0, bagsDamaged: 0,
          unitPrice: l.expectedSellingPricePerBag ?? 0,
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
        waterCustomerId: null, customerLabel: "",
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
      ? { ...r, items: [...r.items, { waterProductId: first.waterProductId, quantity: 1, unitPrice: first.unitPrice ?? 0 }] }
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

  // "Use summary only" — clears breakdown and credit-customer enforcement.
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
  const totalSold     = returnItems.reduce((s, it) => s + it.bagsSold, 0)
  const totalReturned = returnItems.reduce((s, it) => s + it.bagsReturned, 0)
  const totalDamaged  = returnItems.reduce((s, it) => s + it.bagsDamaged, 0)
  const totalLoadedItems = returnItems.reduce((s, it) => s + it.bagsLoaded, 0)
  const totalLoaded = returnDlg.loading?.bagsLoaded ?? totalLoadedItems
  const perItemBalanced = returnItems.every(it => (it.bagsSold + it.bagsReturned + it.bagsDamaged) === it.bagsLoaded)
  const overallBalanced = (totalSold + totalReturned + totalDamaged) === totalLoaded

  const expectedFromItems = returnItems.reduce((s, it) => s + (it.bagsSold * it.unitPrice), 0)
  const expectedCash = expectedFromItems ||
    (returnDlg.loading ? totalSold * (returnDlg.loading.expectedSellingPricePerBag ?? 0) : 0)

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
        productQty.set(it.waterProductId, (productQty.get(it.waterProductId) ?? 0) + it.quantity)
      }
    }
    return { cash, momo, bank, credit, productQty }
  }, [breakdown])

  // True only when the breakdown is at least one row and the summary matches.
  const breakdownProvided = breakdown.length > 0
  const breakdownPaymentsBalance =
    breakdownTotals.cash   === returnPayments.cashCollected &&
    breakdownTotals.momo   === returnPayments.moMoCollected &&
    breakdownTotals.bank   === returnPayments.bankCollected &&
    breakdownTotals.credit === returnPayments.creditSalesAmount
  const breakdownQtyBalance = returnItems.every(ri =>
    (breakdownTotals.productQty.get(ri.waterProductId) ?? 0) === ri.bagsSold,
  )
  const breakdownBalanced = breakdownPaymentsBalance && breakdownQtyBalance

  // Validate credit-to-customer: in summary mode, warn if credit > 0; in
  // detailed mode, require every credit amount to land on a customer (label
  // not enough for a real customer ledger, but allowed as override).
  // Both checks are scoped to postingMode === "Detailed" — under
  // OneCustomer/Summary modes the Step 3 UI is hidden, so we mustn't let stale
  // breakdown state block save or surface a warning the user can't act on.
  const isDetailed = postingMode === "Detailed"
  const creditWithoutCustomer = isDetailed
    && returnPayments.creditSalesAmount > 0
    && !breakdownProvided
  const detailedCreditUnassigned = isDetailed
    && breakdownProvided
    && breakdown.some(r => r.creditAmount > 0 && !r.waterCustomerId)

  const expensesTotal = expenses.reduce((s, e) => s + (e.isApproved ? e.amount : 0), 0)

  // #32: the cash the driver returns must reconcile with the float they left with
  // (opening cash) less any approved expenses paid from that float. Flag a
  // mismatch and block Approve & Reconcile until it balances (Draft is allowed).
  const openingCashFloat = returnDlg.loading?.openingCashWithDriver ?? 0
  const expectedFloatBack = Math.max(openingCashFloat - expensesTotal, 0)
  const floatBalanced = Math.abs((returnPayments.cashReturnedByDriver ?? 0) - expectedFloatBack) < 0.01

  // Migration 083 — save Draft then immediately call Approve & Reconcile.
  // Convenience wrapper for the "Approve & Reconcile" button at the bottom of
  // the Record Return modal so the operator skips the Returns-tab round-trip.
  async function saveAndApproveReconcile() {
    await saveReturn({ approveAfter: true })
  }

  async function saveReturn(opts?: { approveAfter?: boolean }) {
    // Synchronous re-entry block (same reason as saveLoad — multiple Draft
    // returns appeared in the DB for the same loading).
    if (returnInflight.current) return
    if (!returnDlg.loading) return
    if (!perItemBalanced) {
      return toast({
        title: "Per-product bags don't reconcile",
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
        description: "Tie each credit amount to a customer, or tick the admin override.",
        variant: "destructive",
      })
    }

    returnInflight.current = true
    setSavingReturn(true)
    try {
      const created = await createWaterDriverReturn({
        waterVehicleLoadingId: returnDlg.loading.waterVehicleLoadingId,
        returnDate: new Date(returnDate).toISOString(),
        bagsSold: totalSold,
        bagsReturned: totalReturned,
        bagsDamaged: totalDamaged,
        missingBags: 0,
        cashCollected: returnPayments.cashCollected,
        moMoCollected: returnPayments.moMoCollected,
        bankCollected: returnPayments.bankCollected,
        creditSalesAmount: returnPayments.creditSalesAmount,
        cashReturnedByDriver: returnPayments.cashReturnedByDriver,
        approvedDeliveryExpenses: expensesTotal,
        notes: returnNotes || null,
        items: returnItems.map(it => ({
          waterProductId: it.waterProductId,
          bagsSold: it.bagsSold,
          bagsReturned: it.bagsReturned,
          bagsDamaged: it.bagsDamaged,
          unitPrice: it.unitPrice,
        })),
        customerSales: (isDetailed && breakdownProvided) ? breakdown.map(r => ({
          waterCustomerId: r.waterCustomerId ?? null,
          customerLabel: r.customerLabel || null,
          cashPaid: r.cashPaid, moMoPaid: r.moMoPaid, bankPaid: r.bankPaid,
          creditAmount: r.creditAmount,
          notes: r.notes || null,
          items: r.items,
        })) : undefined,
        expenses: expenses.length > 0 ? expenses.map(e => ({
          expenseCategory: e.expenseCategory,
          amount: e.amount,
          description: e.description || null,
          isApproved: e.isApproved,
        })) : undefined,
      } as any)

      // Migration 083 — persist the chosen sales posting mode on the new Draft
      // so spWaterDriverReturn_ApproveReconcile knows how to materialise the
      // sale (Detailed = breakdown rows, OneCustomer = single primary customer,
      // Summary = GeneralDelivery default customer).
      const newReturnId = (created as any)?.waterDriverReturnId
      if (newReturnId) {
        try {
          await updateWaterDriverReturnPostingMode(newReturnId, {
            salesPostingMode: postingMode,
            primaryCustomerId: postingMode === "OneCustomer" ? primaryCustomerId : null,
          })
        } catch (e: any) {
          // Don't blow up the whole save — the row defaults to 'Detailed'
          // server-side which preserves legacy behaviour.
          // eslint-disable-next-line no-console
          console.warn("posting-mode persist failed", e)
        }
      }

      // If the operator pressed "Approve & Reconcile" rather than "Record Draft",
      // run validation + materialisation immediately so the row jumps straight
      // to Reconciled and the user doesn't have to revisit the Returns tab.
      if (opts?.approveAfter && newReturnId) {
        try {
          await approveReconcileWaterDriverReturn(newReturnId)
        } catch (e: any) {
          toast({ title: "Saved as Draft — approve failed", description: e?.message, variant: "destructive" })
        }
      }
      // James (2026-05-30): Record and Approve are now distinct steps. Save
      // creates a Draft; the operator clicks Approve in the Returns tab when
      // they're comfortable that the bag/money math is right. The Draft
      // row's existing Approve button already runs spWaterDriverReturn_Approve,
      // so no other change is needed.

      // N12: editing a Draft return must leave EXACTLY ONE record. Previously we
      // cancelled the old Draft (leaving a stray Cancelled row that confused the
      // closing). Now we DELETE it outright after the new Insert succeeds, so
      // there is only the replacement return.
      const editedFrom = editReturnTargetRef.current
      if (editedFrom) {
        try { await deleteWaterDriverReturn(editedFrom.waterDriverReturnId) }
        catch (e: any) {
          toast({
            title: "New return saved, but couldn't remove the old one",
            description: `Old return #${editedFrom.waterDriverReturnId}: ${e?.message ?? String(e)}`,
            variant: "destructive",
          })
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

          {/* Prompt 2 Part 2 §3 — page-level KPIs sit BELOW the filtered tab
              content so every tab fits the "filters → cards → table" rule.
              Score cards moved further down. */}

          {/* Tabs split the page so each operation has its own list — James
              didn't want one giant scrollable mess. Active / Returns /
              Reconciled show data; Drivers / Vehicles / Routes link out to
              the existing top-level sidebar pages. */}
          <Tabs defaultValue="active">
            {/* shadcn TabsList defaults to h-9 (36px). With flex-wrap, the second
                row of tabs got hidden behind the height boundary on mobile —
                "Setup" disappeared. h-auto + items-stretch lets wrapped rows
                render. flex-1 + min-w-fit lets each trigger size to its content. */}
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
                      onReload={openEditLoadDlg}
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
                      items={visibleReturns}
                      getKey={(r) => r.waterDriverReturnId}
                      primary={(r) => `Delivery #${r.waterVehicleLoadingId} · ${r.vehicleName ?? "Vehicle —"} · ${r.bagsSold} bags sold`}
                      secondary={(r) => (
                        <>
                          <span>{r.returnDate.split("T")[0]}</span>
                          {r.driverName && <span>· {r.driverName}</span>}
                          {r.routeName && <span>· {r.routeName}</span>}
                          {(r.shortageAmount ?? 0) > 0 && <span className="text-rose-600">· Short {gh(r.shortageAmount ?? 0)}</span>}
                        </>
                      )}
                      details={(r) => [
                        { label: "Delivery #", value: r.waterVehicleLoadingId },
                        { label: "Date", value: r.returnDate.split("T")[0] },
                        { label: "Vehicle", value: r.vehicleName ?? "—" },
                        { label: "Driver", value: r.driverName ?? "—" },
                        { label: "Route", value: r.routeName ?? "—" },
                        { label: "Status", value: r.status },
                        { label: "Sold (bags)", value: r.bagsSold },
                        { label: "Returned (bags)", value: r.bagsReturned },
                        { label: "Damaged (bags)", value: r.bagsDamaged },
                        { label: `Cash${cur}`, value: gh(r.cashCollected) },
                        { label: `MoMo${cur}`, value: gh(r.moMoCollected) },
                        { label: `Credit${cur}`, value: gh(r.creditSalesAmount) },
                        { label: `Shortage${cur}`, value: <span className={(r.shortageAmount ?? 0) > 0 ? "text-rose-600" : ""}>{gh(r.shortageAmount ?? 0)}</span> },
                      ]}
                      actions={(r) => (
                        <>
                          <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                            <Link href={`/water-driver-returns/${r.waterVehicleLoadingId}`}>View details</Link>
                          </Button>
                          {/* Draft → Edit + Approve + Cancel inline. Edit was added 2026-05-30
                              after operators reported needing to fix a Draft mid-flow. */}
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
                          {/* Prompt 2 §3 — Reverse Reconciliation. Only valid
                              on Approved returns. */}
                          {r.status === "Approved" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => setReverseTarget(r)}>
                              <Undo2 className="h-4 w-4 mr-1" /> Reverse
                            </Button>
                          )}
                          {/* James (2026-05-30): Uncancel — only on Cancelled rows.
                              Flips Cancelled → Draft so the operator can re-approve. */}
                          {r.status === "Cancelled" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => uncancelDraftReturn(r)}>
                              <Undo2 className="h-4 w-4 mr-1" /> Uncancel
                            </Button>
                          )}
                          {/* Admin-only hard delete on Cancelled rows. */}
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
                                <TableHead className="text-right">Sold (bags)</TableHead>
                                <TableHead className="text-right">Returned (bags)</TableHead>
                                <TableHead className="text-right">Damaged (bags)</TableHead>
                                <TableHead className="text-right">Cash{cur}</TableHead>
                                <TableHead className="text-right">MoMo{cur}</TableHead>
                                <TableHead className="text-right">Credit{cur}</TableHead>
                                <TableHead className="text-right">Shortage{cur}</TableHead>
                                <TableHead className="text-right">Actions</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {visibleReturns.map((r) => (
                            <TableRow key={r.waterDriverReturnId}>
                              <TableCell className="font-medium tabular-nums">#{r.waterVehicleLoadingId}</TableCell>
                              <TableCell>{r.returnDate.split("T")[0]}</TableCell>
                              <TableCell className="font-medium">{r.vehicleName ?? "—"}</TableCell>
                              <TableCell>{r.driverName ?? "—"}</TableCell>
                              <TableCell><Badge className={r.status === "Approved" ? "bg-green-100 text-green-700" : r.status === "Cancelled" ? "bg-slate-100 text-slate-600" : "bg-amber-100 text-amber-700"}>{r.status}</Badge></TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsSold}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsReturned}</TableCell>
                              <TableCell className="text-right tabular-nums">{r.bagsDamaged}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.cashCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.moMoCollected)}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(r.creditSalesAmount)}</TableCell>
                                <TableCell className={`text-right tabular-nums ${(r.shortageAmount ?? 0) > 0 ? "text-rose-600" : ""}`}>{gh(r.shortageAmount ?? 0)}</TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                <Button asChild size="sm" variant="ghost" title="View details">
                                  <Link href={`/water-driver-returns/${r.waterVehicleLoadingId}`}><Eye className="h-4 w-4" /></Link>
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
              {/* Mirror the filter UI so users can narrow reconciled history
                  by driver/vehicle/route/date. */}
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
                        // Resolve the matching Approved driver-return so we
                        // can hand the right entity to the existing prompt.
                        const r = returns.find(x => x.waterVehicleLoadingId === l.waterVehicleLoadingId && x.status === "Approved")
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

            {/* Setup tab: deep-links to the existing sidebar pages so this
                hub doesn't duplicate their CRUD. James asked for the
                operations to be grouped — keeping setup separate keeps the
                main page focused on the daily flow. */}
            <TabsContent value="setup">
              <Card>
                <CardContent className="p-4 grid grid-cols-1 md:grid-cols-3 gap-3">
                  <Link href="/water-drivers" className="border rounded-md p-4 hover:bg-slate-50 transition">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <Users2 className="h-4 w-4 text-sky-600" /> Drivers
                    </div>
                    <div className="text-xs text-slate-500 mt-1">{drivers.filter(d => d.isActive).length} active · manage drivers, base pay, commissions</div>
                  </Link>
                  <Link href="/water-vehicles" className="border rounded-md p-4 hover:bg-slate-50 transition">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <Truck className="h-4 w-4 text-sky-600" /> Vehicles
                    </div>
                    <div className="text-xs text-slate-500 mt-1">{vehicles.filter(v => v.status === "Active").length} active · manage vehicles and capacity</div>
                  </Link>
                  <Link href="/water-routes" className="border rounded-md p-4 hover:bg-slate-50 transition">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <MapPin className="h-4 w-4 text-sky-600" /> Routes
                    </div>
                    <div className="text-xs text-slate-500 mt-1">{routes.length} configured · manage delivery routes</div>
                  </Link>
                  <Link href="/water-driver-report" className="border rounded-md p-4 hover:bg-slate-50 transition md:col-span-3">
                    <div className="flex items-center gap-2 font-medium text-slate-900">
                      <Truck className="h-4 w-4 text-sky-600" /> Driver collection report
                    </div>
                    <div className="text-xs text-slate-500 mt-1">Per-driver per-product loaded / sold / returned / damaged with cash + shortage roll-up</div>
                  </Link>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>

          {/* Page-level KPIs — relocated below the tabs per Prompt 2 Part 2 §3
              so the standard "filters → cards → table" sequence holds within
              each tab. These cards summarise across all tabs (not filtered
              by the per-tab ListFilters). */}
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
      <Dialog open={loadDlg} onOpenChange={(o) => { setLoadDlg(o); if (!o) setEditLoadTarget(null) }}>
        {/* Load Vehicle dialog — widened to match Record Return. max-w-3xl
            (768px) was clipping the products table on wide screens.
            Title/description swap when editing an existing load (James, 2026-05-30). */}
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editLoadTarget ? <Pencil className="w-5 h-5 text-blue-600" /> : <Truck className="w-5 h-5 text-blue-600" />}
              {editLoadTarget
                ? `Edit delivery run #${editLoadTarget.waterVehicleLoadingId}`
                : "Create delivery run — load driver"}
            </DialogTitle>
            <DialogDescription>
              {editLoadTarget
                ? "Change driver, vehicle, route, products or quantities. Saving reverses the old stock-out and applies the new amounts atomically."
                : "Assign a driver, pick the vehicle + route, and list the products being loaded. Stock moves out of the warehouse on save."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="Driver & route" color="indigo" columns={3}>
              <FormField label="Driver *">
                {/* Prompt 2 Part 1 §6 — picking a driver auto-fills vehicle
                    from driver.defaultVehicleId (when set). Manual override
                    stays available via the Vehicle picker below. */}
                <Select value={String(loadForm.waterDriverId)} onValueChange={(v) => {
                  const driverId = Number(v)
                  const d = drivers.find(x => x.waterDriverId === driverId)
                  setLoadForm({
                    ...loadForm,
                    waterDriverId: driverId,
                    waterVehicleId: d?.defaultVehicleId ?? loadForm.waterVehicleId,
                  })
                }}>
                  <SelectTrigger><SelectValue placeholder="Pick driver" /></SelectTrigger>
                  <SelectContent>{drivers.filter(d => d.isActive).map(d => (
                    <SelectItem key={d.waterDriverId} value={String(d.waterDriverId)}>{d.driverName}</SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Vehicle *">
                <Select value={String(loadForm.waterVehicleId)} onValueChange={(v) => setLoadForm({ ...loadForm, waterVehicleId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Pick vehicle" /></SelectTrigger>
                  <SelectContent>{vehicles.filter(v => v.status === "Active").map(v => (
                    <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName} ({v.vehicleType})</SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Route">
                {/* Prompt 2 Part 1 §7 — picking a route falls back to the
                    route's default vehicle ONLY when no vehicle is set yet,
                    so we don't clobber an explicit driver-default selection. */}
                <Select value={String(loadForm.waterRouteId)} onValueChange={(v) => {
                  const routeId = Number(v)
                  const r = routes.find(x => x.waterRouteId === routeId)
                  setLoadForm({
                    ...loadForm,
                    waterRouteId: routeId,
                    waterVehicleId: loadForm.waterVehicleId || (r?.defaultVehicleId ?? loadForm.waterVehicleId),
                  })
                }}>
                  <SelectTrigger><SelectValue placeholder="Pick route" /></SelectTrigger>
                  <SelectContent>{routes.map(r => (
                    <SelectItem key={r.waterRouteId} value={String(r.waterRouteId)}>{r.routeName}</SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Assistant (optional)">
                {/* The assistant can be another DRIVER (a 2nd person on the
                    truck) OR an office staff member — list both, excluding
                    whoever is the selected driver. AssistantStaffId is a loose
                    int (no FK), so storing either id is fine. */}
                {(() => {
                  const driverName = drivers
                    .find(d => d.waterDriverId === loadForm.waterDriverId)
                    ?.driverName?.trim().toLowerCase()
                  const driverOpts = drivers.filter(d => d.isActive && d.waterDriverId !== loadForm.waterDriverId)
                  const staffOpts = staff.filter(s =>
                    s.isActive && !s.isDeleted &&
                    `${s.firstName} ${s.lastName}`.trim().toLowerCase() !== driverName,
                  )
                  const hasAny = driverOpts.length + staffOpts.length > 0
                  return (
                    <Select value={String(loadForm.assistantStaffId)} onValueChange={(v) => setLoadForm({ ...loadForm, assistantStaffId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder="Pick assistant" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="0">— none —</SelectItem>
                        {!hasAny && <div className="px-2 py-1.5 text-sm text-slate-500">No other drivers or staff available.</div>}
                        {driverOpts.map(d => (
                          <SelectItem key={`d${d.waterDriverId}`} value={String(d.waterDriverId)}>
                            {d.driverName} · Driver
                          </SelectItem>
                        ))}
                        {staffOpts.map(s => (
                          <SelectItem key={`s${s.waterStaffId}`} value={String(s.waterStaffId)}>
                            {s.firstName} {s.lastName}{s.role ? ` · ${s.role}` : ""}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )
                })()}
              </FormField>
              <FormField label={`Opening cash with driver${cur}`} hint="Cash float given to driver before departure (change, fuel, small expenses). Separate from sales cash.">
                <NumberInput min={0} step="0.01" value={loadForm.openingCashWithDriver}
                  onChange={(e) => setLoadForm({ ...loadForm, openingCashWithDriver: Number(e.target.value) || 0 })} />
              </FormField>
              {/* #29 — pick the load date (defaults to today). */}
              <FormField label="Load date">
                <Input type="date" value={loadForm.loadDate} onChange={(e) => setLoadForm({ ...loadForm, loadDate: e.target.value })} />
              </FormField>
            </FormSection>

            {/* Products section gets the colored band treatment too so it
                blends with FormSection siblings. */}
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
                {/* Desktop table — same as before. */}
                <div className="hidden lg:block overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="min-w-[180px]">Product</TableHead>
                        <TableHead className="text-right">Quantity (bags)</TableHead>
                        <TableHead className="text-right">Unit price{cur}</TableHead>
                        <TableHead className="text-right">Expected{cur}</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {loadItems.map((it, idx) => {
                        const exp = it.bagsLoaded * it.unitPrice
                        return (
                          <TableRow key={idx}>
                            <TableCell>
                              <Select value={String(it.waterProductId)} onValueChange={(v) => {
                                const id = Number(v)
                                const p = products.find(x => x.waterProductId === id)
                                updateLoadItem(idx, { waterProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                              }}>
                                <SelectTrigger><SelectValue /></SelectTrigger>
                                <SelectContent>{products.map(p => (
                                  <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>
                                ))}</SelectContent>
                              </Select>
                            </TableCell>
                            <TableCell className="text-right">
                              <NumberInput min={0} value={it.bagsLoaded}
                                onChange={(e) => updateLoadItem(idx, { bagsLoaded: Number(e.target.value) || 0 })}
                                className="w-24 ml-auto text-right" />
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

                {/* Mobile card stack — each row becomes a self-contained card so
                    the product Select and the qty/price inputs stop colliding
                    inside a side-scrolling table cell. */}
                <div className="lg:hidden space-y-2">
                  {loadItems.map((it, idx) => {
                    const exp = it.bagsLoaded * it.unitPrice
                    return (
                      <div key={idx} className="rounded-lg border border-slate-200 bg-white p-3 space-y-2">
                        <div className="flex items-center gap-2">
                          <div className="flex-1 min-w-0">
                            <Select value={String(it.waterProductId)} onValueChange={(v) => {
                              const id = Number(v)
                              const p = products.find(x => x.waterProductId === id)
                              updateLoadItem(idx, { waterProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                            }}>
                              <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                              <SelectContent>{products.map(p => (
                                <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>
                              ))}</SelectContent>
                            </Select>
                          </div>
                          <Button size="sm" variant="ghost" onClick={() => removeLoadItem(idx)} className="shrink-0">
                            <Trash2 className="h-4 w-4 text-red-500" />
                          </Button>
                        </div>
                        <div className="grid grid-cols-3 gap-2 items-end">
                          <div>
                            <label className="text-xs text-slate-500">Qty (bags)</label>
                            <NumberInput min={0} value={it.bagsLoaded}
                              onChange={(e) => updateLoadItem(idx, { bagsLoaded: Number(e.target.value) || 0 })}
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
                {gh(loadItems.reduce((s, it) => s + (it.bagsLoaded * it.unitPrice), 0))}
              </span>
            </div>

            <div className="flex flex-col-reverse sm:flex-row gap-2 sm:gap-3 sm:justify-end pt-2">
              <Button type="button" onClick={() => setLoadDlg(false)} className="bg-red-600 hover:bg-red-700 text-white w-full sm:w-auto h-11 sm:h-10">Cancel</Button>
              <Button onClick={saveLoad} disabled={savingLoad} className="w-full sm:w-auto h-11 sm:h-10">
                {savingLoad ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : editLoadTarget ? "Save changes" : "Load & approve"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* ===================================================================
          Record Driver Return dialog — multi-product + breakdown + expenses
          =================================================================== */}
      <Dialog open={returnDlg.open} onOpenChange={(v) => { if (!v) { setReturnDlg({ open: false }); editReturnTargetRef.current = null } }}>
        {/* Record Return dialog — wider on big screens (1800px cap, 98vw on
            mid laptops) so the per-product reconciliation table breathes when
            it appears on xl+. overflow-x-hidden because the base DialogContent
            uses `display: grid` whose children default to min-width: auto —
            any wider child would push a page-level horizontal scrollbar. The
            inner tables already wrap their own overflow-x-auto. p-3 on mobile
            to claw back edge padding. */}
        <DialogContent className="w-[98vw] max-w-[1800px] max-h-[92vh] overflow-y-auto overflow-x-hidden p-3 sm:p-6">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Truck className="w-5 h-5 text-blue-600" />
              Record driver return — {returnDlg.loading?.driverName ?? "—"} / {returnDlg.loading?.vehicleName} / {returnDlg.loading?.routeName ?? "—"}
            </DialogTitle>
            <DialogDescription>
              Reconcile bags sold / returned / damaged per product, then enter the payment summary. Optionally add the per-customer breakdown and delivery expenses.
            </DialogDescription>
          </DialogHeader>

          {returnDlg.loading && (
            // min-w-0 forces this child to shrink within the DialogContent
            // grid track (grid children default to min-width: auto, which is
            // the real reason inner tables/inputs were spilling out of the
            // dialog and triggering a page-level horizontal scrollbar).
            <div className="space-y-4 min-w-0 w-full">
              {/* Return date — defaults to the load date; editable (incl. on edit). */}
              <div className="flex items-center gap-2">
                <label className="text-sm text-slate-600 shrink-0">Return date</label>
                <Input type="date" value={returnDate} onChange={(e) => setReturnDate(e.target.value)} className="max-w-[200px]" />
              </div>
              {/* At-a-glance summary so the operator always sees the bag
                  balance and money totals without scrolling. */}
              <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs">
                  <div>
                    <div className="text-slate-500">Loaded</div>
                    <div className="text-base font-semibold tabular-nums text-slate-900">{totalLoaded} bags</div>
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

              {/* Per-product reconciliation — colored band matching the
                  surrounding FormSection look. Above xl (1280px) renders the
                  full 7-column table; below that, each product is a stacked
                  card so the inputs stay tap-friendly and the operator never
                  has to side-scroll while entering data. */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                {/* Header wraps to a second line on narrow widths so the hint
                    text doesn't get truncated as "Sold + Returned + Damaged mu…". */}
                <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white flex flex-col sm:flex-row sm:items-center sm:justify-between gap-1 sm:gap-2">
                  <span>Step 1 · Reconcile bags per product</span>
                  <span className="text-xs font-normal text-amber-50">Sold + Returned + Damaged must equal Loaded</span>
                </div>

                {/* James (2026-06-05): drop the desktop horizontal-scroll
                    8-column table and use a single card-per-product layout at
                    every breakpoint. Inside each card, fields render as
                    label-on-left / value-on-right rows in a 2-column grid on
                    sm+ (1 column on mobile) so the operator sees Loaded /
                    Sold / Returned / Damaged / Unit price / Expected without
                    horizontal scrolling, matching Step 2's pattern. */}
                <div className="bg-white p-4 space-y-4">
                  {returnItems.map((it, idx) => {
                    const total = it.bagsSold + it.bagsReturned + it.bagsDamaged
                    const balanced = total === it.bagsLoaded
                    const expected = it.bagsSold * it.unitPrice
                    // One reconciliation row: label on left (truncate), input/value on right
                    // (fixed-width so columns align across rows). Defined inline (not as a
                    // local component) so React doesn't unmount/remount the inputs on each
                    // render — which would drop keystroke focus while typing.
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
                        {/* Card header: product name + balance status */}
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
                              : total - it.bagsLoaded > 0
                                ? `+${total - it.bagsLoaded}`
                                : `${total - it.bagsLoaded}`}
                          </div>
                        </div>

                        {/* #13: 2 cols, row-major order →
                            Loaded | Expected
                            Sold   | Unit price
                            Returned | Damaged */}
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2">
                          <div className={rowClass}>
                            <div className={labelClass}>Loaded (bags)</div>
                            <div className={valueWrapClass}>
                              <div className="text-right tabular-nums font-medium pr-3">{it.bagsLoaded}</div>
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Expected{cur}</div>
                            <div className={valueWrapClass}>
                              <div className="text-right tabular-nums font-semibold pr-3">{gh(expected)}</div>
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Sold (bags)</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                value={it.bagsSold}
                                onChange={(e) => updateReturnItem(idx, { bagsSold: Number(e.target.value) || 0 })}
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
                            <div className={labelClass}>Returned (bags)</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                value={it.bagsReturned}
                                onChange={(e) => updateReturnItem(idx, { bagsReturned: Number(e.target.value) || 0 })}
                              />
                            </div>
                          </div>
                          <div className={rowClass}>
                            <div className={labelClass}>Damaged (bags)</div>
                            <div className={valueWrapClass}>
                              <NumberInput
                                className="text-right tabular-nums"
                                min={0}
                                value={it.bagsDamaged}
                                onChange={(e) => updateReturnItem(idx, { bagsDamaged: Number(e.target.value) || 0 })}
                              />
                            </div>
                          </div>
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>

              {/* Payment summary — all amounts in GHC. James (2026-06-05) asked
                  for a label-on-left / input-on-right layout so the section
                  reads like a table of "this is the field, this is the value"
                  rather than the FormField grid that put labels above inputs.
                  All four collection-method rows are always visible (no
                  dropdown / no "+ Add method" picker — operator fills the ones
                  they used and leaves the rest at 0). Cash returned sits below
                  a divider since it's a float reconciliation, not a sale. */}
              <FormSection title={`Step 2 · Money collected${cur}`} color="green" columns={1}>
                {/* #14: two items per row; only "Cash returned by driver" (below)
                    keeps its own full-width row. */}
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
                {/* #30: Unaccounted cash = expected sales not covered by cash/MoMo/
                    bank/credit. Read-only so the operator sees money gaps at a glance. */}
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

              {/* Migration 083 — Sales Posting Mode (moved above Step 3 per James
                  2026-06-02 so the operator decides posting strategy first; Step
                  3 (per-customer breakdown) only appears when "Detailed" is
                  picked, since OneCustomer + Summary don't need it). The chosen
                  mode is persisted on the Draft via /posting-mode so
                  spWaterDriverReturn_ApproveReconcile knows how to materialise
                  the sale. */}
              <FormSection title="How should this delivery sale be posted?" color="purple" columns={1}>
                <div className="space-y-2 text-sm">
                  {/* #15: order = One customer (default) → Summary → Detailed. */}
                  <label className="flex items-start gap-2 cursor-pointer">
                    <input type="radio" className="mt-1" checked={postingMode === "OneCustomer"} onChange={() => setPostingMode("OneCustomer")} />
                    <span><strong>Post all sales to one customer</strong><br/>
                      <span className="text-slate-500">Posts the entire delivery sale to the customer below.</span></span>
                  </label>
                  {/* OneCustomer dropdown sits directly under its radio. */}
                  {postingMode === "OneCustomer" && (
                    <div className="pl-6">
                      <Select value={primaryCustomerId ? String(primaryCustomerId) : ""} onValueChange={(v) => setPrimaryCustomerId(v ? Number(v) : null)}>
                        <SelectTrigger className="h-10"><SelectValue placeholder="Pick a customer" /></SelectTrigger>
                        <SelectContent>
                          {customers.map((c) => (
                            <SelectItem key={c.waterCustomerId} value={String(c.waterCustomerId)}>{c.name}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}

                  {/* #15: Summary only is disabled when there are credit sales —
                      credit must be tracked against a real customer (option 1 or 3). */}
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
                        <span className="block text-amber-700">Unavailable while there are credit sales — pick option 1 or 3.</span>
                      )}</span>
                  </label>

                  <label className="flex items-start gap-2 cursor-pointer">
                    <input type="radio" className="mt-1" checked={postingMode === "Detailed"}    onChange={() => setPostingMode("Detailed")} />
                    <span><strong>Detailed customer breakdown</strong><br/>
                      <span className="text-slate-500">Record real customer/shop sales one-by-one. The breakdown appears right below when selected.</span></span>
                  </label>
                </div>
              </FormSection>

              {/* Step 3 only renders when "Detailed customer breakdown" is the
                  posting mode — the other two modes don't use the per-customer
                  rows so showing the section would be misleading. */}
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
                          <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
                            <div className="md:col-span-2"><Label>Customer</Label>
                              <Select value={String(row.waterCustomerId ?? 0)} onValueChange={(v) => updateBreakdownRow(rowIdx, { waterCustomerId: Number(v) || null })}>
                                <SelectTrigger><SelectValue placeholder="Pick customer" /></SelectTrigger>
                                <SelectContent>
                                  <SelectItem value="0">— walk-in / unnamed —</SelectItem>
                                  {customers.map(c => (
                                    <SelectItem key={c.waterCustomerId} value={String(c.waterCustomerId)}>{c.name}</SelectItem>
                                  ))}
                                </SelectContent>
                              </Select></div>
                            <div><Label>Or label</Label>
                              <Input value={row.customerLabel} onChange={(e) => updateBreakdownRow(rowIdx, { customerLabel: e.target.value })} placeholder="Walk-in name" /></div>
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
                                {/* Desktop table — xl: cutover so the customer-
                                    breakdown line items don't squash the
                                    dialog at 1024-1280px laptop widths. */}
                                <div className="hidden xl:block overflow-x-auto">
                                  <Table>
                                    <TableHeader>
                                      <TableRow>
                                        <TableHead>Product</TableHead>
                                        <TableHead className="text-right">Qty (bags)</TableHead>
                                        <TableHead className="text-right">Price{cur}</TableHead>
                                        <TableHead className="text-right">Total{cur}</TableHead>
                                        <TableHead></TableHead>
                                      </TableRow>
                                    </TableHeader>
                                    <TableBody>
                                      {row.items.map((it, itIdx) => (
                                        <TableRow key={itIdx}>
                                          <TableCell>
                                            <Select value={String(it.waterProductId)} onValueChange={(v) => {
                                              const id = Number(v)
                                              const p = products.find(x => x.waterProductId === id)
                                              updateBreakdownItem(rowIdx, itIdx, { waterProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                                            }}>
                                              <SelectTrigger><SelectValue /></SelectTrigger>
                                              <SelectContent>{products.map(p => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}</SelectContent>
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

                                {/* Card stack — carries all widths below xl: */}
                                <div className="xl:hidden p-2 space-y-2">
                                  {row.items.map((it, itIdx) => (
                                    <div key={itIdx} className="rounded-md border p-2 space-y-2 bg-white">
                                      <div className="flex items-center gap-2">
                                        <div className="flex-1 min-w-0">
                                          <Select value={String(it.waterProductId)} onValueChange={(v) => {
                                            const id = Number(v)
                                            const p = products.find(x => x.waterProductId === id)
                                            updateBreakdownItem(rowIdx, itIdx, { waterProductId: id, unitPrice: p?.unitPrice ?? it.unitPrice })
                                          }}>
                                            <SelectTrigger><SelectValue /></SelectTrigger>
                                            <SelectContent>{products.map(p => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}</SelectContent>
                                          </Select>
                                        </div>
                                        <Button size="sm" variant="ghost" onClick={() => removeBreakdownItem(rowIdx, itIdx)}>
                                          <Trash2 className="h-4 w-4 text-red-500" />
                                        </Button>
                                      </div>
                                      <div className="grid grid-cols-3 gap-2 items-end">
                                        <div>
                                          <label className="text-xs text-slate-500">Qty (bags)</label>
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

                          {/* Payment split — all amounts in GHC. */}
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

                    {/* Breakdown vs summary check */}
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
                        {/* Desktop table — same xl: rule as the other tables
                            in this dialog so the expense list doesn't clip on
                            small/mid laptops. */}
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

                        {/* Card stack — used everywhere below xl:. */}
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
                <span className="font-semibold whitespace-nowrap">{overallBalanced && perItemBalanced ? "✓ Bags balanced" : "✗ Bags don't balance"}</span>
              </div>

              {/* Warnings for credit-without-customer */}
              {creditWithoutCustomer && (
                <div className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-3 py-2">
                  Credit sales are not assigned to customers. Customer balances will not be accurate unless credit is linked to customers via the breakdown.
                </div>
              )}
              {detailedCreditUnassigned && (
                <div className="text-xs text-rose-800 bg-rose-50 border border-rose-200 rounded-md px-3 py-2">
                  One or more customer rows have credit but no customer selected. Pick a customer or tick the admin override below.
                </div>
              )}
              {((isDetailed && breakdownProvided && !breakdownBalanced) || detailedCreditUnassigned) && (
                <label className="text-xs flex items-center gap-2 text-slate-700">
                  <input type="checkbox" checked={overrideMismatch} onChange={(e) => setOverrideMismatch(e.target.checked)} />
                  Admin override — approve anyway
                </label>
              )}

              {/* Money balance strip */}
              <div className={`rounded-xl border px-4 py-3 grid grid-cols-2 md:grid-cols-5 gap-2 text-sm ${shortage > 0 ? "border-rose-200 bg-rose-50" : overage > 0 ? "border-amber-200 bg-amber-50" : "border-slate-200 bg-slate-50"}`}>
                <div><div className="text-xs text-slate-500">Expected cash</div><div className="font-semibold tabular-nums">{gh(expectedCash)}</div></div>
                <div><div className="text-xs text-slate-500">Collected</div><div className="font-semibold tabular-nums">{gh(collected)}</div></div>
                <div><div className="text-xs text-slate-500">Shortage</div><div className={`font-semibold tabular-nums ${shortage > 0 ? "text-rose-600" : "text-slate-400"}`}>{gh(shortage)}</div></div>
                <div><div className="text-xs text-slate-500">Overage</div><div className={`font-semibold tabular-nums ${overage > 0 ? "text-green-700" : "text-slate-400"}`}>{gh(overage)}</div></div>
                <div><div className="text-xs text-slate-500">Approved expenses</div><div className="font-semibold tabular-nums">{gh(expensesTotal)}</div></div>
              </div>

              {/* Explain why Approve & Reconcile may be disabled so it's not a mystery. */}
              {(!overallBalanced || !perItemBalanced || (postingMode === "OneCustomer" && !primaryCustomerId)) && (
                <div className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
                  Approve &amp; Reconcile is disabled because{" "}
                  {(!overallBalanced || !perItemBalanced)
                    ? "the bag counts don't reconcile yet (each product's Sold + Returned + Damaged must equal Loaded)."
                    : "you chose “Post all sales to one customer” but haven't selected the customer yet — pick one above, or switch the posting option."}
                </div>
              )}
              <div className="flex flex-col-reverse sm:flex-row gap-2 sm:gap-3 sm:justify-end pt-2">
                <Button type="button" onClick={() => setReturnDlg({ open: false })} className="bg-red-600 hover:bg-red-700 text-white w-full sm:w-auto h-11 sm:h-10">Cancel</Button>
                <Button onClick={() => saveReturn()}
                  disabled={savingReturn || !overallBalanced || !perItemBalanced}
                  title={!overallBalanced || !perItemBalanced ? "Reconcile per-product bags before saving" : "Saves as Draft; approve from the Returns tab"}
                  variant="outline"
                  className="w-full sm:w-auto h-11 sm:h-10"
                >
                  {savingReturn ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Record return (Draft)"}
                </Button>
                {/* Migration 083 §2 — single-shot Approve & Reconcile. Same validation
                    as Draft + immediate spWaterDriverReturn_ApproveReconcile call. */}
                <Button onClick={saveAndApproveReconcile}
                  disabled={savingReturn || !overallBalanced || !perItemBalanced || (postingMode === "OneCustomer" && !primaryCustomerId)}
                  title={
                    (!overallBalanced || !perItemBalanced) ? "Reconcile the bag counts first (Sold + Returned + Damaged = Loaded)."
                    : (postingMode === "OneCustomer" && !primaryCustomerId) ? "Select the customer under “Post all sales to one customer” first."
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

      {/* DeliveriesTable lives below the JSX; jsx hoisting doesn't apply but
          the function declaration is hoisted at the module level. */}

      {/* Admin-only hard delete of a Cancelled return. */}
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title={`Delete cancelled return #${deleteTarget?.waterDriverReturnId ?? ""}?`}
        description="This permanently removes the return header, per-product items, customer-sale rows, and delivery expense rows. Only available for Cancelled returns. The action cannot be undone."
        confirmLabel="Delete return"
        successTitle="Cancelled return deleted"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteTarget) await performDeleteCancelledReturn(deleteTarget)
        }}
      />

      {/* Styled Approve & Reconcile confirmation (replaces the native confirm). */}
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
            await approveReconcileWaterDriverReturn(approveTarget.waterDriverReturnId)
            await load()
          }
        }}
      />

      {/* Void / "delete" confirmation. Reverses LoadOut stock when status is Loaded. */}
      <ConfirmDeleteDialog
        open={!!voidTarget}
        onOpenChange={(o) => { if (!o) setVoidTarget(null) }}
        title="Void this delivery?"
        description={voidTarget
          ? `Void delivery ${voidTarget.driverName ?? voidTarget.vehicleName} (${voidTarget.bagsLoaded} bags${voidTarget.expectedCash ? `, expected ${gh(voidTarget.expectedCash)}` : ""})? ${voidTarget.status === "Loaded"
              ? "This will return the bags to warehouse stock via an Adjust transaction. Blocked if a driver return is already recorded."
              : "Draft loadings have no stock to reverse."}`
          : undefined}
        confirmLabel="Void delivery"
        successTitle="Delivery voided — stock returned to warehouse"
        errorTitle="Void failed"
        onConfirm={async () => {
          if (voidTarget) {
            await voidWaterVehicleLoading(voidTarget.waterVehicleLoadingId)
            await load()
          }
        }}
      />

      {/* Prompt 2 §4 — Reload / Edit Load. Header-only edits for now
          (driver/vehicle/route/opening cash/notes). Items are kept as-is so
          the existing LoadOut stock txns stay valid. */}
      <Dialog open={!!reloadTarget} onOpenChange={(o) => { if (!o) setReloadTarget(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Reload / Edit Load</DialogTitle>
            <DialogDescription>
              Correct the driver/vehicle/route/notes for this delivery. Item lines stay as recorded.
            </DialogDescription>
          </DialogHeader>
          {reloadTarget && (
            <div className="space-y-4">
              <FormSection title="Delivery" color="indigo">
                <FormField label="Driver">
                  <Select
                    value={String(reloadForm.waterDriverId ?? "")}
                    onValueChange={(v) => setReloadForm({ ...reloadForm, waterDriverId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Pick driver" /></SelectTrigger>
                    <SelectContent>
                      {drivers.filter(d => d.isActive).map((d) => (
                        <SelectItem key={d.waterDriverId} value={String(d.waterDriverId)}>{d.driverName}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Vehicle">
                  <Select
                    value={String(reloadForm.waterVehicleId ?? "")}
                    onValueChange={(v) => setReloadForm({ ...reloadForm, waterVehicleId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Pick vehicle" /></SelectTrigger>
                    <SelectContent>
                      {vehicles.filter(v => v.status === "Active").map((v) => (
                        <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Route">
                  <Select
                    value={String(reloadForm.waterRouteId ?? "")}
                    onValueChange={(v) => setReloadForm({ ...reloadForm, waterRouteId: v ? Number(v) : null })}>
                    <SelectTrigger><SelectValue placeholder="Pick route" /></SelectTrigger>
                    <SelectContent>
                      {routes.map((r) => (
                        <SelectItem key={r.waterRouteId} value={String(r.waterRouteId)}>{r.routeName}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Opening cash with driver">
                  <NumberInput min={0} step="0.01"
                    value={reloadForm.openingCashWithDriver}
                    onChange={(e) => setReloadForm({ ...reloadForm, openingCashWithDriver: Number(e.target.value) || 0 })} />
                </FormField>
              </FormSection>
              <FormSection title="Notes" color="slate" columns={1}>
                <FormField label="Notes">
                  <Input value={reloadForm.notes} onChange={(e) => setReloadForm({ ...reloadForm, notes: e.target.value })} />
                </FormField>
              </FormSection>
              <div className="flex justify-end gap-2 pt-2">
                <Button type="button" variant="outline" onClick={() => setReloadTarget(null)}>Cancel</Button>
                <Button onClick={saveReload} disabled={reloadBusy}>
                  {reloadBusy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : "Save changes"}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Migration 068 / Prompt 2 §3 — Reverse Reconciliation dialog. The
          confirmation copy mirrors the prompt verbatim so users know exactly
          what will be undone. */}
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
        onSubmit={async (reason) => {
          if (!reverseTarget) return
          const target = reverseTarget
          const wantsEdit = editAfterReverse
          try {
            await reverseWaterDriverReturn(target.waterDriverReturnId, reason)
            if (wantsEdit) {
              toast({ title: "Reverted — re-opening the return for edit" })
              setReverseTarget(null); setEditAfterReverse(false)
              await load()
              // After reload, find the updated loading row so the dialog has
              // the freshest state (status may have flipped back from
              // Reconciled to Loaded).
              const reloaded = await listWaterVehicleLoadings()
              const l = reloaded.find(x => x.waterVehicleLoadingId === target.waterVehicleLoadingId)
                ?? loadings.find(x => x.waterVehicleLoadingId === target.waterVehicleLoadingId)
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

// Migration 068 / Prompt 2 §5 — dropdown filters for Driver / Vehicle / Route
// / Status. Rendered inside ListFilters' `extras` slot so the search/date
// row keeps its existing layout.
function DeliveryDropdowns({
  drivers, vehicles, routes,
  driver, setDriver, vehicle, setVehicle, route, setRoute, status, setStatus,
  statusOptions,
}: {
  drivers: WaterDriver[]
  vehicles: WaterVehicle[]
  routes: WaterRoute[]
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
            <SelectItem key={d.waterDriverId} value={String(d.waterDriverId)}>{d.driverName}</SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select value={vehicle} onValueChange={setVehicle}>
        <SelectTrigger className="w-36 h-9 text-xs"><SelectValue placeholder="All vehicles" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="ALL">All vehicles</SelectItem>
          {vehicles.filter(v => v.status === "Active").map((v) => (
            <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName}</SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select value={route} onValueChange={setRoute}>
        <SelectTrigger className="w-36 h-9 text-xs"><SelectValue placeholder="All routes" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="ALL">All routes</SelectItem>
          {routes.map((r) => (
            <SelectItem key={r.waterRouteId} value={String(r.waterRouteId)}>{r.routeName}</SelectItem>
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

// Compact loadings table reused in both Active and Reconciled tabs. Keeping
// it local to this file because it depends on local types (WaterVehicleLoading,
// LOAD_STATUS) and isn't useful elsewhere.
function DeliveriesTable({
  rows, onRecordReturn, onVoid, onReload, onReverse, onEditReconciled, showActions,
}: {
  rows: WaterVehicleLoading[]
  onRecordReturn: (l: WaterVehicleLoading) => void
  onVoid: (l: WaterVehicleLoading) => void
  onReload?: (l: WaterVehicleLoading) => void
  // Prompt 2 §3 / Part 1 §1 — Reverse Reconciliation from the Reconciled tab.
  // The loading row → resolve the linked driver-return upstream and call the
  // existing reverse handler. Only invoked on rows with status Reconciled.
  onReverse?: (l: WaterVehicleLoading) => void
  // James (2026-05-30) — Edit on a Reconciled row. Same SP as Reverse, but
  // the upstream handler reopens the Record Return dialog pre-filled after
  // the reverse succeeds. Only invoked on Reconciled rows.
  onEditReconciled?: (l: WaterVehicleLoading) => void
  showActions: boolean
}) {
  // Local copy of the column-header currency suffix — DeliveriesTable is
  // declared outside the main component so it can't close over the parent's
  // `cur`. Reading from the same store keeps both in sync with the setup
  // toggle and active symbol.
  const { symbol, showSymbol } = useCurrency()
  // James (2026-05-30): currency symbols belong on the *values* (driven by
  // fmtMoney + the showCurrencySymbol toggle), never duplicated into the
  // column header. Force empty so headers stay clean regardless of toggle.
  const cur = ""
  return (
    <MobileCardList
      items={rows}
      getKey={(l) => l.waterVehicleLoadingId}
      primary={(l) => (
        <Link href={`/water-driver-returns/${l.waterVehicleLoadingId}`} className="text-sky-700 hover:underline">
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
        { label: "Loaded (bags)", value: l.bagsLoaded },
        { label: `Expected${cur}`, value: gh(l.expectedCash ?? 0) },
        { label: "Status", value: l.status },
      ]}
      actions={(l) => (
        <>
          {/* View Details — present on every tab so users don't have to guess
              that the date is a link (Prompt 2 Part 1 §1). */}
          <Button asChild size="sm" variant="outline" className="flex-1 h-10">
            <Link href={`/water-driver-returns/${l.waterVehicleLoadingId}`}>View details</Link>
          </Button>
          {showActions && l.status === "Loaded" && (
            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => onRecordReturn(l)}>
              Record return
            </Button>
          )}
          {/* Prompt 2 §4 — Reload/Edit Load (only on Draft+Loaded). */}
          {showActions && onReload && (l.status === "Loaded" || l.status === "Draft") && (
            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => onReload(l)}>
              Reload / edit
            </Button>
          )}
          {showActions && (l.status === "Loaded" || l.status === "Draft") && (
            <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => onVoid(l)}>
              <XCircle className="h-4 w-4 mr-1" /> Void
            </Button>
          )}
          {/* Reconciled tab — Edit (reverse + re-record + re-approve). */}
          {onEditReconciled && l.status === "Reconciled" && (
            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => onEditReconciled(l)}>
              <Pencil className="h-4 w-4 mr-1" /> Edit
            </Button>
          )}
          {/* Reconciled tab — Reverse Reconciliation (Prompt 2 Part 1 §3). */}
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
                <TableHead className="text-right">Loaded (bags)</TableHead>
                <TableHead className="text-right">Expected{cur}</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((l) => (
                <TableRow key={l.waterVehicleLoadingId}>
                  <TableCell>
                    <Link href={`/water-driver-returns/${l.waterVehicleLoadingId}`} className="text-sky-700 hover:underline">
                      {l.loadDate.split("T")[0]}
                    </Link>
                  </TableCell>
                  <TableCell>{l.driverName ?? "—"}</TableCell>
                  <TableCell>{l.vehicleName ?? "—"}</TableCell>
                  <TableCell>{l.routeName ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{l.bagsLoaded}</TableCell>
                  <TableCell className="text-right tabular-nums">{gh(l.expectedCash ?? 0)}</TableCell>
                  <TableCell><Badge className={LOAD_STATUS[l.status] ?? ""}>{l.status}</Badge></TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    <Button asChild size="sm" variant="ghost" title="View details">
                      <Link href={`/water-driver-returns/${l.waterVehicleLoadingId}`}><Eye className="h-4 w-4" /></Link>
                    </Button>
                    {showActions && l.status === "Loaded" && <Button size="sm" onClick={() => onRecordReturn(l)}>Record return</Button>}
                    {showActions && onReload && (l.status === "Loaded" || l.status === "Draft") && (
                      <Button size="sm" variant="ghost" onClick={() => onReload(l)} title="Reload / edit load">
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

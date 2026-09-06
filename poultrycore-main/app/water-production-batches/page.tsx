"use client"

import React, { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
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
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Plus, Loader2, Factory, CheckCircle2, XCircle, Pencil, Undo2, Trash2, Eye, CalendarDays } from "lucide-react"
import Link from "next/link"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterProductionBatches, createWaterProductionBatch, updateWaterProductionBatch,
  approveWaterProductionBatch, cancelWaterProductionBatch, reopenWaterProductionBatch,
  listWaterRawMaterialOpenLots,
  listWaterMachines, listWaterProducts, listWaterRawMaterialItems,
  getWaterProductionRecipe, listWaterProductionBatchMaterials, isDailyProductionChild,
  type WaterProductionBatch, type WaterMachine, type WaterProduct,
  type WaterRawMaterialItem, type WaterProductionMaterialUsageInput, type WaterRawMaterialLot,
} from "@/lib/api/water"
import { planDraw, lotsForItem, type DrawPlan } from "@/lib/water-lot-draw"
import { useFmt } from "@/lib/currency"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-green-100 text-green-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

const SHIFTS = ["Morning", "Afternoon", "Night", "FullDay"]

const round3 = (n: number) => Math.round(n * 1000) / 1000

// In-memory row shape for the "Raw Materials Used" section. We track expected
// vs actual separately so the user can adjust without losing the recipe-derived
// suggestion (and so the backend can write Variance).
type MaterialRow = {
  waterRawMaterialItemId: number
  expectedQuantity: number
  actualQuantity: number
  unitCost: number    // GHC per unit; pre-filled from latest purchase
  unitOfMeasure: string
  availableStock: number
  itemName: string
}

export default function WaterProductionBatchesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const fmtGhc = useFmt()

  const [batches, setBatches] = useState<WaterProductionBatch[]>([])
  const [machines, setMachines] = useState<WaterMachine[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [rawMaterials, setRawMaterials] = useState<WaterRawMaterialItem[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  // Raw Materials Used section state.
  const [materialRows, setMaterialRows] = useState<MaterialRow[]>([])
  const [recipeLoading, setRecipeLoading] = useState(false)
  // True when this batch's selected product has a saved recipe — drives the
  // "Use expected quantities" button + warns when missing materials.
  const [hasRecipe, setHasRecipe] = useState(false)
  // Open purchase lots for every raw material, in the order each item's policy
  // consumes them. Drives the per-row draw preview below: what a typed quantity
  // will actually be taken from, and what that costs.
  const [openLots, setOpenLots] = useState<WaterRawMaterialLot[]>([])
  // Rows whose lot breakdown is expanded.
  const [expandedDraw, setExpandedDraw] = useState<Record<number, boolean>>({})

  // User chose to override the "materials missing" guard at Approve time.
  const [overrideMissing, setOverrideMissing] = useState(false)

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // null = create mode, number = edit mode (the WaterProductionBatchId being edited).
  // Only Draft batches can be edited; Approved/Cancelled rows show no pencil.
  const [editingId, setEditingId] = useState<number | null>(null)
  const [reopenTarget, setReopenTarget] = useState<WaterProductionBatch | null>(null)
  // Backend requires BatchNumber (max 60 chars). Frontend auto-generates a
  // timestamp-based default the user can override before submitting; without
  // this the POST was returning 400 "BatchNumber field is required."
  const makeBatchNumber = () => {
    const d = new Date()
    const pad = (n: number) => String(n).padStart(2, "0")
    return `B-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  }

  const [form, setForm] = useState({
    batchNumber: makeBatchNumber(),
    productionDate: new Date().toISOString().split("T")[0],
    shift: "Morning",
    // 0 = no specific machine. When machineScope = "AllMachines" we ignore
    // this and store NULL on the backend so reports can tell the two apart.
    waterMachineId: 0,
    machineScope: "SingleMachine" as "SingleMachine" | "AllMachines",
    waterProductId: 0,
    bagsProduced: 0,
    sachetsPerBag: 30,
    rejectedSachets: 0,
    damagedBags: 0,
    electricityCost: 0,
    fuelCost: 0,
    laborCost: 0,
    otherProductionCost: 0,
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [bs, ms, ps, mats, lots] = await Promise.all([
        listWaterProductionBatches(),
        listWaterMachines(),
        listWaterProducts(),
        listWaterRawMaterialItems(),
        // Tolerated failure: without lots the form falls back to headline stock
        // and the latest-purchase price, which is what it showed before.
        listWaterRawMaterialOpenLots().catch(() => [] as WaterRawMaterialLot[]),
      ])
      setBatches(bs); setMachines(ms); setProducts(ps); setRawMaterials(mats); setOpenLots(lots)
    } catch (e: any) { toast({ title: "Could not load production records", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Fetch the selected product's recipe and reseed material rows. Called on
  // every product change inside the open dialog. We deliberately don't preserve
  // user edits when the product changes — switching products means a different
  // recipe entirely.
  async function loadRecipeForProduct(productId: number, bagsProduced: number) {
    setRecipeLoading(true); setHasRecipe(false)
    try {
      const recipe = await getWaterProductionRecipe(productId)
      if (!recipe || !recipe.items.length) {
        setMaterialRows([])
        return
      }
      setHasRecipe(true)
      const rows: MaterialRow[] = recipe.items.map(it => {
        const mat = rawMaterials.find(m => m.waterRawMaterialItemId === it.waterRawMaterialItemId)
        // Expected = bags × qty-per-bag × (1 + waste%)
        const expectedRaw = bagsProduced * Number(it.quantityPerOutputUnit ?? 0)
        const expected = expectedRaw * (1 + Number(it.wasteAllowancePercent ?? 0) / 100)
        const unitCost = Number(it.latestUnitCost ?? 0)
        return {
          waterRawMaterialItemId: it.waterRawMaterialItemId,
          expectedQuantity: round3(expected),
          actualQuantity: round3(expected),
          unitCost,
          unitOfMeasure: it.rawMaterialUnit ?? mat?.unitOfMeasure ?? "",
          availableStock: Number(it.rawMaterialStock ?? mat?.currentQuantity ?? 0),
          itemName: it.rawMaterialName ?? mat?.itemName ?? `Material #${it.waterRawMaterialItemId}`,
        }
      })
      setMaterialRows(rows)
    } catch (e: any) {
      // Don't blow up the whole modal — just leave the section empty so the
      // user can still record the batch without a recipe.
      console.warn("recipe load failed", e)
      setMaterialRows([])
    } finally {
      setRecipeLoading(false)
    }
  }

  // Show finished goods first in the picker — raw/packaging materials are
  // legal too (Other), but the typical case is sachet/bottle water.
  const productPicker = useMemo(
    () => [...products].sort((a, b) => {
      const aFG = (a.productType ?? "FinishedGood") === "FinishedGood" ? 0 : 1
      const bFG = (b.productType ?? "FinishedGood") === "FinishedGood" ? 0 : 1
      return aFG - bFG || a.name.localeCompare(b.name)
    }),
    [products],
  )

  async function openNew() {
    setEditingId(null)
    setOverrideMissing(false)
    const defaultProductId = productPicker.find(p => p.isActive)?.waterProductId ?? 0
    setForm({
      batchNumber: makeBatchNumber(),
      productionDate: new Date().toISOString().split("T")[0],
      shift: "Morning",
      waterMachineId: machines.find(m => m.status === "Active")?.waterMachineId ?? 0,
      machineScope: "SingleMachine",
      waterProductId: defaultProductId,
      bagsProduced: 0,
      sachetsPerBag: 30,
      rejectedSachets: 0,
      damagedBags: 0,
      electricityCost: 0,
      fuelCost: 0,
      laborCost: 0,
      otherProductionCost: 0,
      notes: "",
    })
    setMaterialRows([])
    setOpen(true)
    if (defaultProductId) await loadRecipeForProduct(defaultProductId, 0)
  }

  async function openEdit(b: WaterProductionBatch) {
    setEditingId(b.waterProductionBatchId)
    setOverrideMissing(false)
    setForm({
      batchNumber: b.batchNumber ?? makeBatchNumber(),
      productionDate: b.productionDate ? b.productionDate.split("T")[0] : new Date().toISOString().split("T")[0],
      shift: b.shift ?? "Morning",
      waterMachineId: b.waterMachineId ?? 0,
      machineScope: (b.machineScope === "AllMachines" ? "AllMachines" : "SingleMachine"),
      waterProductId: b.waterProductId ?? 0,
      bagsProduced: b.bagsProduced ?? 0,
      sachetsPerBag: b.sachetsPerBag ?? 30,
      rejectedSachets: b.rejectedSachets ?? 0,
      damagedBags: b.damagedBags ?? 0,
      electricityCost: b.electricityCost ?? 0,
      fuelCost: b.fuelCost ?? 0,
      laborCost: b.laborCost ?? 0,
      otherProductionCost: b.otherProductionCost ?? 0,
      notes: b.notes ?? "",
    })
    setMaterialRows([])
    setOpen(true)
    // Prefer the user's previously-recorded usage rows over fresh expected
    // values — they're the source of truth for this Draft batch.
    try {
      const used = await listWaterProductionBatchMaterials(b.waterProductionBatchId)
      if (used.length > 0) {
        setHasRecipe(true)
        setMaterialRows(used.map(u => {
          const mat = rawMaterials.find(m => m.waterRawMaterialItemId === u.waterRawMaterialItemId)
          return {
            waterRawMaterialItemId: u.waterRawMaterialItemId,
            expectedQuantity: Number(u.expectedQuantityUsed ?? u.quantityUsed ?? 0),
            actualQuantity: Number(u.quantityUsed ?? 0),
            unitCost: Number(u.unitCost ?? 0),
            unitOfMeasure: u.unitOfMeasure ?? mat?.unitOfMeasure ?? "",
            availableStock: Number(u.currentStock ?? mat?.currentQuantity ?? 0),
            itemName: u.itemName ?? mat?.itemName ?? `Material #${u.waterRawMaterialItemId}`,
          }
        }))
      } else if (b.waterProductId) {
        await loadRecipeForProduct(b.waterProductId, b.bagsProduced ?? 0)
      }
    } catch (e) {
      console.warn("materials load failed", e)
    }
  }

  async function save(andApprove = false) {
    if (!form.batchNumber.trim()) return toast({ title: "Batch number is required", variant: "destructive" })
    if (!form.waterProductId)     return toast({ title: "Pick a product first", variant: "destructive" })
    if (form.bagsProduced <= 0)   return toast({ title: "Bags produced must be greater than zero", variant: "destructive" })
    if (form.sachetsPerBag <= 0)  return toast({ title: "Sachets per bag must be greater than zero", variant: "destructive" })

    // Inline validation on Raw Materials Used.
    for (const row of materialRows) {
      if (row.actualQuantity < 0) return toast({ title: `Negative quantity not allowed`, description: `${row.itemName}: actual cannot be negative.`, variant: "destructive" })
    }

    // Guard: missing required materials. Draft can be saved without them, but
    // we still warn unless the user already accepted the override (rendered
    // inline below the materials table).
    if (hasRecipe && materialRows.some(r => r.actualQuantity <= 0) && !overrideMissing) {
      return toast({
        title: "Some materials are missing",
        description: "Tick \"Save anyway (override)\" below the Raw Materials section if you want to record this production without them.",
        variant: "destructive",
      })
    }

    setSaving(true)
    try {
      const materialsUsed: WaterProductionMaterialUsageInput[] | undefined = materialRows.length > 0
        ? materialRows.map(r => ({
            waterRawMaterialItemId: r.waterRawMaterialItemId,
            quantityUsed: r.actualQuantity,
            expectedQuantityUsed: r.expectedQuantity,
            unitCost: r.unitCost,
          }))
        : []  // explicit empty array → SP replaces with no rows

      const payload = {
        ...form,
        productionDate: form.productionDate,
        // "All Machines / Combined" → NULL machine id (the SP also enforces this).
        waterMachineId: form.machineScope === "AllMachines" ? null : (form.waterMachineId || null as any),
        waterProductId: form.waterProductId || null as any,
        machineScope: form.machineScope,
        materialsUsed,
      }
      let approveId: number | null = editingId
      if (editingId != null) {
        await updateWaterProductionBatch(editingId, payload as any)
        if (!andApprove) toast({ title: "Production record updated" })
      } else {
        const created = await createWaterProductionBatch(payload as any)
        approveId = (created as any)?.waterProductionBatchId ?? null
        if (!andApprove) toast({ title: "Production record saved as Draft", description: "Approve to add to inventory." })
      }
      // #26: approve right from the popup so the operator skips the list round-trip.
      if (andApprove && approveId != null) {
        await approveWaterProductionBatch(approveId)
        toast({ title: "Production saved & approved — bags added to inventory" })
      }
      setOpen(false); setEditingId(null); await load()
    } catch (e: any) { toast({ title: andApprove ? "Save & approve failed" : (editingId != null ? "Update failed" : "Save failed"), description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  // Recompute expected when bags-produced changes (preserves user overrides
  // on actualQuantity — the user might've already adjusted them).
  function applyExpectedQuantities() {
    if (!form.waterProductId) return
    setMaterialRows(rows => rows.map(r => {
      // Use the original recipe ratio: expected ÷ previous bags. If previous
      // expected was 0 we have nothing to extrapolate from — fall back to 0.
      return r // recompute happens via separate reload below
    }))
    // Easier: just refetch.
    void loadRecipeForProduct(form.waterProductId, form.bagsProduced)
  }

  function addMaterialRow() {
    const unused = rawMaterials.filter(m => m.isActive && !materialRows.some(r => r.waterRawMaterialItemId === m.waterRawMaterialItemId))
    if (unused.length === 0) {
      toast({ title: "No more materials to add", variant: "destructive" })
      return
    }
    const m = unused[0]
    setMaterialRows([
      ...materialRows,
      {
        waterRawMaterialItemId: m.waterRawMaterialItemId,
        expectedQuantity: 0,
        actualQuantity: 0,
        unitCost: 0,
        unitOfMeasure: m.unitOfMeasure ?? "",
        availableStock: Number(m.currentQuantity ?? 0),
        itemName: m.itemName,
      },
    ])
  }

  function removeMaterialRow(idx: number) {
    setMaterialRows(rows => rows.filter((_, i) => i !== idx))
  }

  function updateMaterialRow(idx: number, patch: Partial<MaterialRow>) {
    setMaterialRows(rows => rows.map((r, i) => i === idx ? { ...r, ...patch } : r))
  }

  async function approve(b: WaterProductionBatch) {
    try { await approveWaterProductionBatch(b.waterProductionBatchId); toast({ title: "Batch approved — bags added to inventory" }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function cancel(b: WaterProductionBatch) {
    try { await cancelWaterProductionBatch(b.waterProductionBatchId); toast({ title: "Batch cancelled" }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  async function performReopen(b: WaterProductionBatch) {
    await reopenWaterProductionBatch(b.waterProductionBatchId)
    await load()
  }

  // Derived totals: today's good bags + month's good bags from Approved batches.
  // The cards label this explicitly as "(good)" so users don't confuse it with
  // total produced bags — see migration 067 / prompt #7.
  const totals = useMemo(() => {
    const today = new Date().toISOString().slice(0, 10)
    const month = today.slice(0, 7)
    const approved = batches.filter(b => b.status === "Approved")
    const good = (b: WaterProductionBatch) =>
      (b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0)))
    const todayBags = approved.filter(b => b.productionDate.startsWith(today)).reduce((s, b) => s + good(b), 0)
    const monthBags = approved.filter(b => b.productionDate.startsWith(month)).reduce((s, b) => s + good(b), 0)
    return { todayBags, monthBags, draftCount: batches.filter(b => b.status === "Draft").length }
  }, [batches])

  const visibleBatches = useMemo(
    () => filterByDateAndSearch(batches, {
      search, dateFrom, dateTo,
      searchKeys: ["batchNumber", "status", "notes"],
      dateKey: "productionDate",
    }),
    [batches, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleBatches)

  // Live preview values in the dialog.
  const totalSachets = form.bagsProduced * form.sachetsPerBag
  const otherProductionCost = form.electricityCost + form.fuelCost + form.laborCost + form.otherProductionCost
  // Migration 063: raw material cost is part of the live total.
  // What each material line will actually draw, walked down that item's lots in
  // its own FIFO/LIFO/HIFO order. This is the preview of what approval will do,
  // so the price shown is the one the batch gets costed at — not the latest
  // purchase price, which only matches when there is a single lot.
  const drawPlans = useMemo(() => {
    const out: Record<number, DrawPlan> = {}
    materialRows.forEach((r, idx) => {
      out[idx] = planDraw(lotsForItem(openLots, r.waterRawMaterialItemId), r.actualQuantity)
    })
    return out
  }, [materialRows, openLots])

  // Cost from the draw where we have lots to walk; fall back to the row's own
  // unit cost when an item has none (nothing purchased, or lots not yet loaded).
  const rawMaterialCost = materialRows.reduce((s, r, idx) => {
    const plan = drawPlans[idx]
    return s + (plan && plan.takes.length ? plan.totalCost : r.actualQuantity * r.unitCost)
  }, 0)
  const totalProductionCost = otherProductionCost + rawMaterialCost
  // Migration 067: Cost per Bag must use GOOD bags (Produced - Damaged), not
  // total Produced. Otherwise damaging stock makes per-bag cost look cheap.
  const goodBags = Math.max(0, form.bagsProduced - form.damagedBags)
  const costPerBag = goodBags > 0 ? totalProductionCost / goodBags : 0
  const efficiency = totalSachets > 0 ? ((totalSachets - form.rejectedSachets) / totalSachets) * 100 : 0

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          {/* Header — stacks on mobile, side-by-side from sm: */}
          <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-sky-100 rounded-lg flex items-center justify-center">
                <Factory className="h-5 w-5 text-sky-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-semibold text-slate-900 truncate">Production</h1>
                <p className="text-xs sm:text-sm text-slate-500">{batches.length} production record{batches.length === 1 ? "" : "s"} on file.</p>
              </div>
            </div>
            <Button onClick={openNew} className="gap-2 w-full sm:w-auto h-11 sm:h-10 shrink-0">
              <Plus className="h-4 w-4" /> Record production
            </Button>
          </div>

          {/* Prompt 2 §10 — filters above score cards, consistent app-wide. */}
          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search batch number, status or notes"
          />

          {/* Score cards now sit AFTER the filters, per Prompt 2 §10. */}
          {/* #19: smaller scorecards (4 across even on mobile, tighter padding)
              to free vertical space for the batch list below. */}
          <div className="mt-3 mb-3 grid grid-cols-2 sm:grid-cols-4 gap-2">
            <Card><CardContent className="p-2.5"><div className="text-[11px] leading-tight text-slate-500">Today's bags (good)</div><div className="text-base font-semibold tabular-nums">{totals.todayBags.toLocaleString()}</div></CardContent></Card>
            <Card><CardContent className="p-2.5"><div className="text-[11px] leading-tight text-slate-500">Month's bags (good)</div><div className="text-base font-semibold tabular-nums">{totals.monthBags.toLocaleString()}</div></CardContent></Card>
            <Card><CardContent className="p-2.5"><div className="text-[11px] leading-tight text-slate-500">Pending approval</div><div className="text-base font-semibold">{totals.draftCount}</div></CardContent></Card>
            <Card><CardContent className="p-2.5"><div className="text-[11px] leading-tight text-slate-500">Active machines</div><div className="text-base font-semibold">{machines.filter(m => m.status === "Active").length}</div></CardContent></Card>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : batches.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No production records yet.</div>
              ) : (
                <MobileCardList
                  striped
                  defaultOpen
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(b) => b.waterProductionBatchId}
                  primary={(b) => `${b.batchNumber ?? `#${b.waterProductionBatchId}`} · ${(b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))).toLocaleString()} good bags`}
                  secondary={(b) => (
                    <>
                      <span>{b.productionDate ? b.productionDate.split("T")[0] : "—"}</span>
                      {/* #19: surface the machine name on the production entry. */}
                      <Badge variant="outline">{b.machineScope === "AllMachines" ? "All Machines" : (b.machineName ?? "—")}</Badge>
                      <Badge className={STATUS_COLORS[b.status] ?? ""}>{b.status}</Badge>
                    </>
                  )}
                  highlights={(b) => [
                    { label: "Produced bags", value: b.bagsProduced.toLocaleString(), accent: "blue" },
                    { label: "Good bags", value: (b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))).toLocaleString(), accent: "emerald" },
                    { label: "Total cost", value: fmtGhc(b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0))), accent: "violet", wide: true },
                  ]}
                  details={(b) => {
                    const cpb = b.costPerBag ?? 0
                    return [
                      { label: "Date", value: b.productionDate ? b.productionDate.split("T")[0] : "—" },
                      { label: "Shift", value: b.shift ?? "—" },
                      { label: "Machine", value: b.machineScope === "AllMachines" ? "All Machines / Combined" : (b.machineName ?? "—") },
                      { label: "Damaged", value: b.damagedBags ?? 0 },
                      { label: "Cost/bag", value: fmtGhc(cpb) },
                    ]
                  }}
                  actions={(b) => (
                    <>
                      {/* View — every batch including Approved (prompt #3). */}
                      <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                        <Link href={`/water-production-batches/${b.waterProductionBatchId}`}>
                          <Eye className="h-4 w-4 mr-1" /> View
                        </Link>
                      </Button>
                      {/* A record generated by a Batch Production day is managed
                          from its parent: reopening it here would leave the day
                          claiming Posted with a posting log that lies. */}
                      {isDailyProductionChild(b) ? (
                        <Button asChild size="sm" variant="outline" className="flex-1 h-10 text-sky-700 border-sky-200">
                          <Link href={`/water-daily-production/${b.waterDailyProductionId}`}>
                            <CalendarDays className="h-4 w-4 mr-1" /> Open batch production
                          </Link>
                        </Button>
                      ) : (
                        <>
                          {b.status === "Draft" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(b)}>
                              <Pencil className="h-4 w-4 mr-1" /> Edit
                            </Button>
                          )}
                          {b.status === "Draft" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => approve(b)}>
                              <CheckCircle2 className="h-4 w-4 mr-1" /> Approve
                            </Button>
                          )}
                          {b.status !== "Cancelled" && b.status !== "Approved" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => cancel(b)}>
                              <XCircle className="h-4 w-4 mr-1" /> Cancel
                            </Button>
                          )}
                          {b.status === "Approved" && (
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200" onClick={() => setReopenTarget(b)}>
                              <Undo2 className="h-4 w-4 mr-1" /> Reopen
                            </Button>
                          )}
                        </>
                      )}
                    </>
                  )}
                  desktopTable={
                    // Horizontal scroll on narrow screens so columns don't overflow the card.
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Shift</TableHead>
                            <TableHead>Machine</TableHead>
                            <TableHead className="text-right">Produced</TableHead>
                            <TableHead className="text-right">Good</TableHead>
                            <TableHead className="text-right">Damaged</TableHead>
                            <TableHead className="text-right">Total cost</TableHead>
                            <TableHead className="text-right">Cost/bag</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((b) => {
                            const totalCost = b.allInCost ?? ((b.totalProductionCost ?? 0) + (b.rawMaterialCost ?? 0))
                            const cpb       = b.costPerBag ?? 0
                            const good      = b.goodBags ?? (b.bagsProduced - (b.damagedBags ?? 0))
                            return (
                              <TableRow key={b.waterProductionBatchId}>
                                <TableCell className="whitespace-nowrap">{b.productionDate ? b.productionDate.split("T")[0] : "—"}</TableCell>
                                <TableCell>{b.shift ?? "—"}</TableCell>
                                <TableCell className="max-w-[160px] truncate">
                                  {b.machineScope === "AllMachines"
                                    ? <span className="italic text-slate-600">All / Combined</span>
                                    : (b.machineName ?? "—")}
                                </TableCell>
                                <TableCell className="text-right tabular-nums">{b.bagsProduced.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums font-medium">{good.toLocaleString()}</TableCell>
                                <TableCell className="text-right tabular-nums">{b.damagedBags ?? 0}</TableCell>
                                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtGhc(totalCost)}</TableCell>
                                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtGhc(cpb)}</TableCell>
                                <TableCell><Badge className={STATUS_COLORS[b.status] ?? ""}>{b.status}</Badge></TableCell>
                                <TableCell className="text-right whitespace-nowrap">
                                  {/* View first — works for Draft + Approved + Cancelled. */}
                                  <Button asChild size="sm" variant="ghost" title="View details">
                                    <Link href={`/water-production-batches/${b.waterProductionBatchId}`}><Eye className="h-4 w-4" /></Link>
                                  </Button>
                                  {isDailyProductionChild(b) ? (
                                    // Managed from the parent day — see the mobile branch above.
                                    <Button asChild size="sm" variant="ghost" title="Open the batch production that created this record">
                                      <Link href={`/water-daily-production/${b.waterDailyProductionId}`}>
                                        <CalendarDays className="h-4 w-4 text-sky-600" />
                                      </Link>
                                    </Button>
                                  ) : (
                                    <>
                                      {/* Edit only allowed in Draft — once approved the batch has moved stock + cash and edits would corrupt the books. */}
                                      {b.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => openEdit(b)} title="Edit"><Pencil className="h-4 w-4" /></Button>}
                                      {b.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => approve(b)} title="Approve"><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
                                      {b.status !== "Cancelled" && b.status !== "Approved" && <Button size="sm" variant="ghost" onClick={() => cancel(b)} title="Cancel"><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                                      {/* Reopen reverses the stock txn and flips back to Draft so the user can edit/delete. Blocked by backend if bags have already sold. */}
                                      {b.status === "Approved" && <Button size="sm" variant="ghost" onClick={() => setReopenTarget(b)} title="Reopen for edit"><Undo2 className="h-4 w-4 text-amber-600" /></Button>}
                                    </>
                                  )}
                                </TableCell>
                              </TableRow>
                            )
                          })}
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

      {/* The production record form is a large modal. James (2026-05-30): "some of the
          popup page is hidden" — the raw-materials table has 8 columns and
          even at max-w-7xl + min-w-[160px] on the Material select, total
          width exceeds the dialog on mid-size screens, so the right-side
          columns (Stock, Cost, Remove) were getting clipped. Drop the
          overflow-x-hidden so the inner `overflow-x-auto` wrapper can
          actually scroll. p-3 sm:p-6 keeps mobile padding tight. */}
      <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditingId(null) }}>
        {/* Wider on big screens (1800px cap, 98vw on mid laptops) so the
            8-column raw-materials table breathes. overflow-x-hidden because the
            base DialogContent uses `display: grid` whose children default to
            min-width: auto — any wider child would push a page-level
            scrollbar. The inner tables already wrap their own overflow-x. */}
        <DialogContent className="w-[98vw] max-w-[1800px] max-h-[90vh] overflow-y-auto overflow-x-hidden p-3 sm:p-6">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Factory className="w-5 h-5 text-blue-600" />
              {editingId != null ? "Edit production record" : "Record production"}
            </DialogTitle>
            <DialogDescription>
              Record what was produced, the raw materials consumed, and the costs incurred. Saved as Draft until approved.
            </DialogDescription>
          </DialogHeader>

          {/* min-w-0 forces this child to shrink within the DialogContent grid
              track (grid children default to min-width: auto, which is the
              real reason inner tables/inputs were spilling out of the dialog). */}
          <div className="space-y-4 min-w-0 w-full">
            <FormSection title="Batch information" color="indigo">
              <FormField label="Batch number *" full>
                <Input maxLength={60} value={form.batchNumber} onChange={(e) => setForm({ ...form, batchNumber: e.target.value })} placeholder="e.g. B-20260524-093015" />
              </FormField>
              <FormField label="Production date">
                <Input type="date" value={form.productionDate} onChange={(e) => setForm({ ...form, productionDate: e.target.value })} />
              </FormField>
              <FormField label="Shift">
                <Select value={form.shift} onValueChange={(v) => setForm({ ...form, shift: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{SHIFTS.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Machine">
                {/* The special value "0" represents "All Machines / Combined" —
                    used when the business records a single combined batch
                    across several machines instead of per-machine batches.
                    See prompt #8. */}
                <Select
                  value={form.machineScope === "AllMachines" ? "all" : String(form.waterMachineId)}
                  onValueChange={(v) => {
                    if (v === "all") setForm({ ...form, machineScope: "AllMachines", waterMachineId: 0 })
                    else setForm({ ...form, machineScope: "SingleMachine", waterMachineId: Number(v) })
                  }}>
                  <SelectTrigger><SelectValue placeholder="Pick machine" /></SelectTrigger>
                  <SelectContent>
                    {machines.filter(m => m.status === "Active").map(m =>
                      <SelectItem key={m.waterMachineId} value={String(m.waterMachineId)}>{m.machineName}</SelectItem>
                    )}
                    <SelectItem value="all">All Machines / Combined</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Product">
                <Select value={String(form.waterProductId)} onValueChange={(v) => {
                  const id = Number(v)
                  setForm({ ...form, waterProductId: id })
                  if (id) void loadRecipeForProduct(id, form.bagsProduced)
                }}>
                  <SelectTrigger><SelectValue placeholder="Pick product" /></SelectTrigger>
                  <SelectContent>{productPicker.map(p => (
                    <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>
                      {p.name}{(p.productType ?? "FinishedGood") !== "FinishedGood" ? ` (${p.productType})` : ""}
                    </SelectItem>
                  ))}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Production output" color="blue">
              {/* "Produced bags" = total bags before subtracting damaged.
                  Good bags = Produced - Damaged, computed below and rolled into
                  the live summary strip + the list page. */}
              <FormField label="Produced bags *" hint="Total bags before subtracting damaged">
                <NumberInput min={0} value={form.bagsProduced} onChange={(e) => {
                  const v = Number(e.target.value) || 0
                  setForm({ ...form, bagsProduced: v })
                }} />
              </FormField>
              <FormField label="Sachets per bag">
                <NumberInput min={1} value={form.sachetsPerBag} onChange={(e) => setForm({ ...form, sachetsPerBag: Number(e.target.value) || 30 })} />
              </FormField>
              <FormField label="Damaged bags" hint="Counted as loss — not added to stock">
                <NumberInput min={0} value={form.damagedBags} onChange={(e) => setForm({ ...form, damagedBags: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Rejected sachets" hint="Counted as loss">
                <NumberInput min={0} value={form.rejectedSachets} onChange={(e) => setForm({ ...form, rejectedSachets: Number(e.target.value) || 0 })} />
              </FormField>
            </FormSection>

            {/* ====================================================== */}
            {/* Raw Materials Used (migration 063) - own coloured       */}
            {/* section to match the farm-style FormSection look.       */}
            {/* ====================================================== */}
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              {/* Header wraps to a second line on narrow widths so the action
                  buttons ("Use expected" + "Add material") don't get clipped
                  off the right edge of the dialog on small/mid laptops. */}
              <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                <span>Raw materials &amp; supplies used</span>
                <div className="flex flex-wrap gap-2">
                  <Button type="button" variant="secondary" size="sm" onClick={applyExpectedQuantities} disabled={!hasRecipe || !form.waterProductId}>
                    Use expected
                  </Button>
                  <Button type="button" variant="secondary" size="sm" onClick={addMaterialRow}>
                    <Plus className="h-4 w-4 mr-1" /> Add material
                  </Button>
                </div>
              </div>
              <div className="p-4 bg-white">
                {/* #25.1: expected quantities are applied by default on load —
                    make that explicit so the operator knows (and can adjust). */}
                <div className="text-xs text-slate-500 mb-2">
                  {hasRecipe ? (
                    <span className="inline-flex items-center gap-1.5">
                      <span className="inline-flex items-center rounded-full bg-emerald-100 text-emerald-700 px-2 py-0.5 text-[11px] font-medium">✓ Using expected quantities</span>
                      <span>Auto-applied from this product's recipe — adjust actual usage below if it differs.</span>
                    </span>
                  ) : "This product has no recipe — add materials manually or set one up in Product details."}
                </div>

              {recipeLoading ? (
                <div className="text-sm text-slate-500 flex items-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading recipe…
                </div>
              ) : materialRows.length === 0 ? (
                <div className="text-xs text-slate-500 px-2 py-3">
                  No materials yet.{" "}
                  {form.waterProductId
                    ? "Click \"Add material\" to record usage, or open the product to add a recipe."
                    : "Pick a product first."}
                </div>
              ) : (
                <div>
                  {/* Desktop table — was breaking out of the dialog on common
                      laptop widths (1024-1280px) with all 8 columns. Push the
                      table to `xl:` (1280px+) where it actually fits cleanly,
                      and let the friendlier card stack carry everything below
                      that. Both layouts now use the same data; only the
                      arrangement changes. */}
                  <div className="hidden xl:block overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Material</TableHead>
                          <TableHead className="text-right">Expected</TableHead>
                          <TableHead className="text-right">Actual</TableHead>
                          <TableHead>Unit</TableHead>
                          <TableHead className="text-right">Unit cost</TableHead>
                          <TableHead className="text-right">Stock</TableHead>
                          <TableHead className="text-right">Cost</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {materialRows.map((row, idx) => {
                          const plan = drawPlans[idx]
                      // Warn on what can actually be drawn, which is what approval
                      // checks. Stock added by adjustment counts as on hand but has
                      // no lot behind it, so the two figures differ.
                      const drawable = plan ? plan.available : row.availableStock
                      const overStock = plan ? plan.shortfall > 0 : row.actualQuantity > row.availableStock
                          const cost = row.actualQuantity * row.unitCost
                          return (
                          <React.Fragment key={idx}>
                            <TableRow>
                              <TableCell>
                                <Select value={String(row.waterRawMaterialItemId)} onValueChange={(v) => {
                                  const id = Number(v)
                                  const mat = rawMaterials.find(m => m.waterRawMaterialItemId === id)
                                  updateMaterialRow(idx, {
                                    waterRawMaterialItemId: id,
                                    itemName: mat?.itemName ?? row.itemName,
                                    unitOfMeasure: mat?.unitOfMeasure ?? "",
                                    availableStock: Number(mat?.currentQuantity ?? 0),
                                  })
                                }}>
                                  <SelectTrigger className="min-w-[160px]"><SelectValue /></SelectTrigger>
                                  <SelectContent>
                                    {rawMaterials.map(m => (
                                      <SelectItem key={m.waterRawMaterialItemId} value={String(m.waterRawMaterialItemId)}>
                                        {m.itemName}
                                      </SelectItem>
                                    ))}
                                  </SelectContent>
                                </Select>
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-slate-500">
                                {row.expectedQuantity.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                              </TableCell>
                              <TableCell className="text-right">
                                <NumberInput
                                   min={0} step="0.001"
                                  value={row.actualQuantity}
                                  onChange={(e) => updateMaterialRow(idx, { actualQuantity: Number(e.target.value) || 0 })}
                                  className={`w-24 ml-auto text-right ${overStock ? "border-amber-400" : ""}`}
                                />
                                {overStock && (
                                  <div className="text-[10px] text-amber-700 mt-0.5">
                                    Only {drawable.toLocaleString(undefined, { maximumFractionDigits: 3 })} in purchase batches
                                  </div>
                                )}
                              </TableCell>
                              <TableCell className="text-slate-500">{row.unitOfMeasure || "—"}</TableCell>
                              {/* The price this line will actually be charged:
                                  the blend of the lots its quantity reaches, in
                                  the item's own FIFO/LIFO/HIFO order. Click to
                                  see which lots. Re-run for real at approval. */}
                              <TableCell className="text-right">
                                {plan && plan.takes.length ? (
                                  <button
                                    type="button"
                                    className="text-right hover:underline"
                                    onClick={() => setExpandedDraw(m => ({ ...m, [idx]: !m[idx] }))}
                                    title={plan.takes.length > 1 ? "Blended across purchase batches — click for the split" : "From one purchase batch — click for detail"}
                                  >
                                    <div className="tabular-nums text-slate-700">{fmtGhc(plan.unitCost)}</div>
                                    <div className="text-[10px] text-sky-600">
                                      {plan.takes.length === 1
                                        ? `1 batch${expandedDraw[idx] ? " ▴" : " ▾"}`
                                        : `${plan.takes.length} batches${expandedDraw[idx] ? " ▴" : " ▾"}`}
                                    </div>
                                  </button>
                                ) : (
                                  <>
                                    <div className="tabular-nums text-slate-600">{fmtGhc(row.unitCost)}</div>
                                    <div className="text-[10px] text-slate-400">latest purchase</div>
                                  </>
                                )}
                              </TableCell>
                              <TableCell className="text-right tabular-nums text-slate-500">
                                {drawable.toLocaleString(undefined, { maximumFractionDigits: 3 })}
                                {/* Headline stock above the drawable pool means some
                                    arrived by adjustment, with no lot to draw it from. */}
                                {plan && row.availableStock - plan.available > 0.001 && (
                                  <div className="text-[10px] text-amber-600">
                                    {row.availableStock.toLocaleString(undefined, { maximumFractionDigits: 3 })} on hand
                                  </div>
                                )}
                              </TableCell>
                              <TableCell className="text-right tabular-nums">
                                {(plan && plan.takes.length ? plan.totalCost : cost).toFixed(2)}
                              </TableCell>
                              <TableCell>
                                <Button type="button" size="sm" variant="ghost" onClick={() => removeMaterialRow(idx)}>
                                  <Trash2 className="h-4 w-4 text-red-500" />
                                </Button>
                              </TableCell>
                            </TableRow>
                            {/* The draw itself, lot by lot, in consumption order. */}
                            {expandedDraw[idx] && plan && plan.takes.length > 0 && (
                              <TableRow key={`${idx}-draw`} className="bg-sky-50/60 hover:bg-sky-50/60">
                                <TableCell colSpan={8} className="py-2">
                                  <div className="text-[11px] text-sky-900">
                                    <div className="font-medium mb-1">
                                      Drawn from {plan.takes.length} purchase batch{plan.takes.length === 1 ? "" : "es"}
                                      {row.itemName ? ` of ${row.itemName}` : ""}
                                      {" · "}
                                      <span className="uppercase">{lotsForItem(openLots, row.waterRawMaterialItemId)[0]?.usageMethod ?? "FIFO"}</span>
                                    </div>
                                    <table className="w-full max-w-2xl tabular-nums">
                                      <tbody>
                                        {plan.takes.map((t) => (
                                          <tr key={t.lot.waterRawMaterialPurchaseId} className="text-sky-800">
                                            <td className="py-0.5 pr-3">{(t.lot.purchaseDate || "").split("T")[0]}</td>
                                            <td className="py-0.5 pr-3 text-slate-500">{t.lot.supplierName || "—"}</td>
                                            <td className="py-0.5 pr-3 text-right">
                                              {t.productionQuantity.toLocaleString(undefined, { maximumFractionDigits: 3 })} {row.unitOfMeasure}
                                            </td>
                                            <td className="py-0.5 pr-3 text-right">@ {fmtGhc(t.lot.productionUnitCost)}</td>
                                            <td className="py-0.5 text-right font-medium">{fmtGhc(t.cost)}</td>
                                          </tr>
                                        ))}
                                        <tr className="border-t border-sky-200 font-semibold text-sky-900">
                                          <td className="py-1 pr-3" colSpan={2}>Total</td>
                                          <td className="py-1 pr-3 text-right">
                                            {plan.drawn.toLocaleString(undefined, { maximumFractionDigits: 3 })} {row.unitOfMeasure}
                                          </td>
                                          <td className="py-1 pr-3 text-right">{fmtGhc(plan.unitCost)}</td>
                                          <td className="py-1 text-right">{fmtGhc(plan.totalCost)}</td>
                                        </tr>
                                      </tbody>
                                    </table>
                                    {plan.shortfall > 0 && (
                                      <div className="mt-1 text-amber-700">
                                        Short {plan.shortfall.toLocaleString(undefined, { maximumFractionDigits: 3 })} {row.unitOfMeasure} —
                                        approving will be refused until a purchase covers it.
                                      </div>
                                    )}
                                    <div className="mt-1 text-sky-700/70">
                                      Re-checked when the batch is approved, so this can change if another batch draws the same stock first.
                                    </div>
                                  </div>
                                </TableCell>
                              </TableRow>
                            )}
                          </React.Fragment>
                          )
                        })}
                      </TableBody>
                    </Table>
                  </div>

                  {/* Card stack — used everywhere up to xl: (1280px). The
                      previous lg: cutover meant 1024-1280px screens saw the
                      cramped 8-column table; the stack reads cleaner and
                      doesn't get clipped at any width. md+ takes advantage of
                      the wider dialog with a 4-up info row + side-by-side
                      Material/inputs. */}
                  <div className="xl:hidden space-y-3">
                    {materialRows.map((row, idx) => {
                      const plan = drawPlans[idx]
                      // Warn on what can actually be drawn, which is what approval
                      // checks. Stock added by adjustment counts as on hand but has
                      // no lot behind it, so the two figures differ.
                      const drawable = plan ? plan.available : row.availableStock
                      const overStock = plan ? plan.shortfall > 0 : row.actualQuantity > row.availableStock
                      const cost = row.actualQuantity * row.unitCost
                      // #25.2: thicker outer border so each material block is
                      // clearly separated from the next.
                      return (
                        <div key={idx} className={`rounded-lg border-2 p-3 space-y-3 bg-white ${overStock ? "border-amber-400" : "border-slate-300"}`}>
                          {/* Row 1: Material picker spans full width on phones,
                              shares space with the inputs on md+ screens. */}
                          <div className="grid grid-cols-1 md:grid-cols-12 gap-2 items-end">
                            <div className="md:col-span-5 min-w-0">
                              <label className="text-xs text-slate-500">Material</label>
                              <Select value={String(row.waterRawMaterialItemId)} onValueChange={(v) => {
                                const id = Number(v)
                                const mat = rawMaterials.find(m => m.waterRawMaterialItemId === id)
                                updateMaterialRow(idx, {
                                  waterRawMaterialItemId: id,
                                  itemName: mat?.itemName ?? row.itemName,
                                  unitOfMeasure: mat?.unitOfMeasure ?? "",
                                  availableStock: Number(mat?.currentQuantity ?? 0),
                                })
                              }}>
                                <SelectTrigger><SelectValue /></SelectTrigger>
                                <SelectContent>
                                  {rawMaterials.map(m => (
                                    <SelectItem key={m.waterRawMaterialItemId} value={String(m.waterRawMaterialItemId)}>{m.itemName}</SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </div>
                            <div className="grid grid-cols-2 gap-2 md:col-span-6">
                              <div>
                                <label className="text-xs text-slate-500">Actual ({row.unitOfMeasure || "—"})</label>
                                <NumberInput
                                   min={0} step="0.001"
                                  value={row.actualQuantity}
                                  onChange={(e) => updateMaterialRow(idx, { actualQuantity: Number(e.target.value) || 0 })}
                                  className={`text-right ${overStock ? "border-amber-400" : ""}`}
                                />
                              </div>
                              <div>
                                <label className="text-xs text-slate-500">Unit cost</label>
                                {plan && plan.takes.length ? (
                                  <>
                                    <div className="h-9 flex items-center justify-end tabular-nums text-slate-700">{fmtGhc(plan.unitCost)}</div>
                                    <div className="text-[10px] text-sky-700 text-right">
                                      {plan.takes.length === 1 ? "from 1 purchase batch" : `blended over ${plan.takes.length} purchase batches`}
                                    </div>
                                  </>
                                ) : (
                                  <>
                                    <div className="h-9 flex items-center justify-end tabular-nums text-slate-600">{fmtGhc(row.unitCost)}</div>
                                    <div className="text-[10px] text-slate-400 text-right">latest purchase — repriced on approval</div>
                                  </>
                                )}
                              </div>
                            </div>
                            <div className="md:col-span-1 flex md:justify-end">
                              <Button type="button" size="sm" variant="ghost" onClick={() => removeMaterialRow(idx)}>
                                <Trash2 className="h-4 w-4 text-red-500" />
                              </Button>
                            </div>
                          </div>
                          {/* Row 2: info strip — Expected / Stock / Cost. md+ also
                              shows Unit alongside so all 4 metadata fields are
                              visible at a glance. */}
                          <div className="grid grid-cols-3 md:grid-cols-4 gap-2 text-xs border-t pt-2">
                            <div>
                              <div className="text-slate-500">Expected</div>
                              <div className="tabular-nums">{row.expectedQuantity.toLocaleString(undefined, { maximumFractionDigits: 3 })}</div>
                            </div>
                            <div className="hidden md:block">
                              <div className="text-slate-500">Unit</div>
                              <div className="tabular-nums">{row.unitOfMeasure || "—"}</div>
                            </div>
                            <div>
                              <div className="text-slate-500">Stock</div>
                              <div className={`tabular-nums ${overStock ? "text-amber-700 font-semibold" : ""}`}>{drawable.toLocaleString(undefined, { maximumFractionDigits: 3 })}</div>
                            </div>
                            <div className="text-right">
                              <div className="text-slate-500">Cost</div>
                              <div className="tabular-nums font-semibold">{fmtGhc(cost)}</div>
                            </div>
                          </div>
                          {overStock && (
                            <div className="text-[11px] text-amber-700">Only {drawable.toLocaleString(undefined, { maximumFractionDigits: 3 })} in purchase batches ({row.availableStock.toLocaleString()} on hand)</div>
                          )}
                        </div>
                      )
                    })}
                  </div>

                  {hasRecipe && materialRows.some(r => r.actualQuantity <= 0) && (
                    <label className="text-xs text-amber-700 flex items-center gap-2 mt-2">
                      <input type="checkbox" checked={overrideMissing} onChange={(e) => setOverrideMissing(e.target.checked)} />
                      Save anyway (override) — some required materials have zero usage
                    </label>
                  )}
                </div>
              )}
              </div>
            </div>

            <FormSection title="Production costs" color="green">
              <FormField label="Electricity">
                <NumberInput min={0} step="0.01" value={form.electricityCost} onChange={(e) => setForm({ ...form, electricityCost: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Fuel">
                <NumberInput min={0} step="0.01" value={form.fuelCost} onChange={(e) => setForm({ ...form, fuelCost: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Labor">
                <NumberInput min={0} step="0.01" value={form.laborCost} onChange={(e) => setForm({ ...form, laborCost: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Other">
                <NumberInput min={0} step="0.01" value={form.otherProductionCost} onChange={(e) => setForm({ ...form, otherProductionCost: Number(e.target.value) || 0 })} />
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            {/* Live summary strip — calmer slate background so it doesn't fight
                the colored section bands above. */}
            <div className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-2 text-sm">
              <div><span className="text-slate-500">Good bags:</span> <span className="font-semibold tabular-nums">{goodBags.toLocaleString()}</span></div>
              <div><span className="text-slate-500">Sachets:</span> <span className="font-semibold tabular-nums">{totalSachets.toLocaleString()}</span></div>
              <div><span className="text-slate-500">Raw materials &amp; supplies:</span> <span className="font-semibold tabular-nums">{fmtGhc(rawMaterialCost)}</span></div>
              <div><span className="text-slate-500">Other costs:</span> <span className="font-semibold tabular-nums">{fmtGhc(otherProductionCost)}</span></div>
              <div><span className="text-slate-500">Total cost:</span> <span className="font-semibold tabular-nums">{fmtGhc(totalProductionCost)}</span></div>
              <div><span className="text-slate-500">Cost/bag:</span> <span className="font-semibold tabular-nums">{fmtGhc(costPerBag)}</span></div>
              <div><span className="text-slate-500">Efficiency:</span> <span className="font-semibold tabular-nums">{efficiency.toFixed(1)}%</span></div>
            </div>

            <div className="flex flex-wrap gap-3 justify-end pt-2 sticky bottom-0 bg-white pb-1">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
              <Button variant="outline" onClick={() => save(false)} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : editingId != null ? "Save changes" : "Save as Draft"}
              </Button>
              {/* #26: approve right inside the popup (record + edit). */}
              <Button className="bg-green-600 hover:bg-green-700 text-white" onClick={() => save(true)} disabled={saving}>
                <CheckCircle2 className="h-4 w-4 mr-1" /> Save &amp; Approve
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!reopenTarget}
        onOpenChange={(o) => { if (!o) setReopenTarget(null) }}
        title="Reopen this approved production record?"
        description={reopenTarget
          ? `Reversing "${reopenTarget.batchNumber}" will subtract its ${(reopenTarget.bagsProduced ?? 0) - (reopenTarget.damagedBags ?? 0)} good bags from stock and flip it back to Draft. If those bags have already been sold this will fail — cancel the sales first.`
          : undefined}
        confirmLabel="Reopen"
        successTitle="Production record reopened — back to Draft"
        errorTitle="Reopen failed"
        onConfirm={async () => { if (reopenTarget) await performReopen(reopenTarget) }}
      />
    </div>
  )
}

"use client"

// Unified Water company setup hub. One page, tabbed by entity, so an operator
// (or admin) sets up everything the rest of the app depends on in one place
// instead of hunting across 9 different routes.
//
// Each tab embeds a SetupTable that:
//   * lists the items via the existing list*() API helper,
//   * shows an "Add" button that links to the dedicated route (the per-entity
//     pages already have polished add/edit forms — don't duplicate them here),
//   * supports delete on rows that the API supports deleting.
//
// Tabs included match the user's spec: Drivers, Machines, Routes, Products,
// Boreholes, Suppliers (raw material items), Staff — plus Customers and
// Vehicles which the daily flow also depends on.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Settings, Plus, Pencil, Trash2, Loader2, Save, DollarSign,
  ShoppingBag, Users, Truck, Route as RouteIcon, Cog, Droplets, Box, Users2,
} from "lucide-react"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { FormSection, FormField } from "@/components/ui/form-section"
import { fetchFarmSettings, updateFarmCurrency, useFarmSettingsStore, fmtMoney } from "@/lib/currency"
import {
  ProductModal, CustomerModal, DriverModal, VehicleModal, RouteModal,
  MachineModal, BoreholeModal, RawMaterialModal, StaffModal,
} from "@/components/water-setup/inline-modals"
import {
  getWaterCompanyProfile, setupWaterCompany, updateWaterCompanyProfile,
  type WaterCompanyProfile,
} from "@/lib/api/water"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import {
  listWaterProducts, deleteWaterProduct,
  listWaterCustomers, deleteWaterCustomer,
  listWaterDrivers, deleteWaterDriver,
  listWaterVehicles, deleteWaterVehicle,
  listWaterRoutes, deleteWaterRoute,
  listWaterMachines, deleteWaterMachine,
  listWaterBoreholes, deleteWaterBorehole,
  listWaterRawMaterialItems, deleteWaterRawMaterialItem,
  listWaterStaff, deleteWaterStaff,
  listWaterSuppliers, deleteWaterSupplier,
} from "@/lib/api/water"

type Column<T> = { header: string; accessor: (item: T) => React.ReactNode }
type SetupTab<T> = {
  key: string
  label: string
  icon: React.ComponentType<{ className?: string }>
  fetch: () => Promise<T[]>
  idOf: (item: T) => number
  labelOf: (item: T) => string
  delete?: (id: number) => Promise<void>
  // Link to the dedicated full page (kept as a "Open full page" escape hatch
  // so power users with bulk-edit needs don't lose the existing UI).
  addHref: string
  columns: Column<T>[]
  // Prompt 2 §13 — optional inline modal. When provided, Add/Edit happen
  // inside this page; tabs without a modal fall back to navigating to addHref.
  Modal?: React.ComponentType<{
    open: boolean
    item: T | null
    onOpenChange: (open: boolean) => void
    onSaved: () => void
  }>
}

function SetupSection<T>({ tab }: { tab: SetupTab<T> }) {
  const { toast } = useToast()
  const [items, setItems] = useState<T[]>([])
  const [loading, setLoading] = useState(true)
  const [deleteTarget, setDeleteTarget] = useState<T | null>(null)
  // Inline modal state — null = closed, "add" = new item, item = edit.
  const [modalState, setModalState] = useState<"add" | T | null>(null)

  async function load() {
    setLoading(true)
    try { setItems(await tab.fetch()) }
    catch (e: any) { toast({ title: `Could not load ${tab.label.toLowerCase()}`, description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [])

  async function handleDelete(item: T) {
    if (!tab.delete) return
    try {
      await tab.delete(tab.idOf(item))
      toast({ title: `${tab.label} deleted`, description: tab.labelOf(item) })
      setDeleteTarget(null)
      await load()
    } catch (e: any) {
      toast({ title: "Delete failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  return (
    <Card>
      <CardContent className="p-0">
        <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b">
          <div className="flex items-center gap-2 text-slate-700">
            <tab.icon className="h-5 w-5 text-sky-600" />
            <span className="font-semibold">{tab.label}</span>
            {!loading && <Badge variant="secondary" className="ml-1">{items.length}</Badge>}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button asChild size="sm" variant="outline">
              <Link href={tab.addHref}><Pencil className="h-4 w-4 mr-1" /> Open full page</Link>
            </Button>
            {tab.Modal ? (
              <Button size="sm" onClick={() => setModalState("add")}>
                <Plus className="h-4 w-4 mr-1" /> Add {tab.label.toLowerCase()}
              </Button>
            ) : (
              <Button asChild size="sm">
                <Link href={tab.addHref}><Plus className="h-4 w-4 mr-1" /> Add {tab.label.toLowerCase()}</Link>
              </Button>
            )}
          </div>
        </div>
        {loading ? (
          <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : items.length === 0 ? (
          <div className="p-8 text-center text-slate-500">
            No {tab.label.toLowerCase()} yet. Click <span className="font-medium">Add {tab.label.toLowerCase()}</span> above to create your first one.
          </div>
        ) : (
          /* #20: cards on mobile, table on desktop (was table-only). The generic
             column config drives both, so every setup tab gets cards at once. */
          <MobileCardList
            items={items}
            getKey={(item) => tab.idOf(item)}
            primary={(item) => tab.labelOf(item)}
            secondary={(item) => tab.columns.length > 1 ? <span>{tab.columns[1].accessor(item)}</span> : null}
            details={(item) => tab.columns.map((c) => ({ label: c.header, value: c.accessor(item) }))}
            actions={(tab.delete || tab.Modal) ? (item) => (
              <>
                {tab.Modal && (
                  <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setModalState(item)}>
                    <Pencil className="h-4 w-4 mr-1" /> Edit
                  </Button>
                )}
                {tab.delete && (
                  <Button size="sm" variant="outline" className="flex-1 h-10 text-rose-600 border-rose-200" onClick={() => setDeleteTarget(item)}>
                    <Trash2 className="h-4 w-4 mr-1" /> Delete
                  </Button>
                )}
              </>
            ) : undefined}
            desktopTable={
              <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    {tab.columns.map((c) => <TableHead key={c.header}>{c.header}</TableHead>)}
                    {(tab.delete || tab.Modal) && <TableHead className="text-right">Actions</TableHead>}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {items.map((item) => (
                    <TableRow key={tab.idOf(item)}>
                      {tab.columns.map((c) => <TableCell key={c.header}>{c.accessor(item)}</TableCell>)}
                      {(tab.delete || tab.Modal) && (
                        <TableCell className="text-right whitespace-nowrap">
                          {tab.Modal && (
                            <Button size="sm" variant="ghost" onClick={() => setModalState(item)} title={`Edit ${tab.label.toLowerCase()}`}>
                              <Pencil className="h-4 w-4" />
                            </Button>
                          )}
                          {tab.delete && (
                            <Button size="sm" variant="ghost" className="text-rose-600 hover:bg-rose-50" onClick={() => setDeleteTarget(item)} title={`Delete ${tab.label.toLowerCase()}`}>
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          )}
                        </TableCell>
                      )}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              </div>
            }
          />
        )}
      </CardContent>
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
        title={`Delete ${tab.label.toLowerCase()}?`}
        description={deleteTarget ? `${tab.labelOf(deleteTarget)} will be permanently removed. Records that reference it may stop resolving.` : ""}
        onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
      />

      {/* Inline add/edit modal — only rendered when the tab declares one. */}
      {tab.Modal && (
        <tab.Modal
          open={modalState !== null}
          item={modalState === "add" ? null : modalState as T | null}
          onOpenChange={(o) => { if (!o) setModalState(null) }}
          onSaved={() => { setModalState(null); void load() }}
        />
      )}
    </Card>
  )
}

// Module-scope formatter — module scope means we can't subscribe via useFmt().
// fmtMoney reads the latest setting from the Zustand store on each call, so
// once CompanySettingsCard re-renders SetupSection on save, this picks up the
// new shape on the next render.
const fmtGhc = (n?: number | null) => fmtMoney(n ?? 0)

const tabs: SetupTab<any>[] = [
  {
    key: "products",
    label: "Products",
    icon: ShoppingBag,
    addHref: "/water-products",
    fetch: listWaterProducts,
    delete: deleteWaterProduct,
    idOf: (p: any) => p.waterProductId,
    labelOf: (p: any) => p.name,
    columns: [
      { header: "Name", accessor: (p: any) => <span className="font-medium">{p.name}</span> },
      { header: "Size", accessor: (p: any) => p.sizeMl ? `${p.sizeMl}ml` : "—" },
      { header: "Unit", accessor: (p: any) => p.unit ?? "—" },
      { header: "Unit price", accessor: (p: any) => fmtGhc(p.unitPrice) },
      { header: "Stock", accessor: (p: any) => p.stockOnHand ?? 0 },
      { header: "Active", accessor: (p: any) => p.isActive ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
    Modal: ProductModal,
  },
  {
    key: "customers",
    label: "Customers",
    icon: Users,
    addHref: "/water-customers",
    fetch: listWaterCustomers,
    delete: deleteWaterCustomer,
    idOf: (c: any) => c.waterCustomerId,
    labelOf: (c: any) => c.name,
    columns: [
      { header: "Name", accessor: (c: any) => <span className="font-medium">{c.name}</span> },
      { header: "Phone", accessor: (c: any) => c.contactPhone ?? "—" },
      { header: "City", accessor: (c: any) => c.city ?? "—" },
      { header: "Outstanding", accessor: (c: any) => fmtGhc(c.outstandingBalance) },
    ],
    Modal: CustomerModal,
  },
  {
    key: "drivers",
    label: "Drivers",
    icon: Users2,
    addHref: "/water-drivers",
    fetch: listWaterDrivers,
    delete: deleteWaterDriver,
    idOf: (d: any) => d.waterDriverId,
    labelOf: (d: any) => d.driverName,
    columns: [
      { header: "Name", accessor: (d: any) => <span className="font-medium">{d.driverName}</span> },
      { header: "Phone", accessor: (d: any) => d.phoneNumber ?? "—" },
      { header: "License", accessor: (d: any) => d.licenseNumber ?? "—" },
      { header: "Active", accessor: (d: any) => d.isActive ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
    Modal: DriverModal,
  },
  {
    key: "vehicles",
    label: "Vehicles",
    icon: Truck,
    addHref: "/water-vehicles",
    fetch: listWaterVehicles,
    delete: deleteWaterVehicle,
    idOf: (v: any) => v.waterVehicleId,
    labelOf: (v: any) => v.vehicleName ?? v.registrationNumber ?? "Vehicle",
    columns: [
      { header: "Name", accessor: (v: any) => <span className="font-medium">{v.vehicleName ?? "—"}</span> },
      { header: "Reg #", accessor: (v: any) => v.registrationNumber ?? "—" },
      { header: "Type", accessor: (v: any) => v.vehicleType ?? "—" },
      { header: "Capacity", accessor: (v: any) => v.capacityBags ? `${v.capacityBags} bags` : "—" },
      { header: "Status", accessor: (v: any) => <Badge variant={v.status === "Active" ? "default" : "secondary"}>{v.status ?? "—"}</Badge> },
    ],
    Modal: VehicleModal,
  },
  {
    key: "routes",
    label: "Routes",
    icon: RouteIcon,
    addHref: "/water-routes",
    fetch: listWaterRoutes,
    delete: deleteWaterRoute,
    idOf: (r: any) => r.waterRouteId,
    labelOf: (r: any) => r.routeName,
    columns: [
      { header: "Name", accessor: (r: any) => <span className="font-medium">{r.routeName}</span> },
      { header: "Area covered", accessor: (r: any) => r.areaCovered ?? "—" },
      { header: "Expected customers", accessor: (r: any) => r.expectedCustomers ?? "—" },
      { header: "Expected bags", accessor: (r: any) => r.expectedBagsSold ?? "—" },
    ],
    Modal: RouteModal,
  },
  {
    key: "machines",
    label: "Machines",
    icon: Cog,
    addHref: "/water-machines",
    fetch: listWaterMachines,
    delete: deleteWaterMachine,
    idOf: (m: any) => m.waterMachineId,
    labelOf: (m: any) => m.machineName,
    columns: [
      { header: "Name", accessor: (m: any) => <span className="font-medium">{m.machineName}</span> },
      { header: "Type", accessor: (m: any) => m.machineType ?? "—" },
      { header: "Capacity / hr", accessor: (m: any) => m.capacityPerHour ?? "—" },
      { header: "Status", accessor: (m: any) => <Badge variant={m.status === "Active" ? "default" : "secondary"}>{m.status ?? "—"}</Badge> },
    ],
    Modal: MachineModal,
  },
  {
    key: "boreholes",
    label: "Boreholes",
    icon: Droplets,
    addHref: "/water-boreholes",
    fetch: listWaterBoreholes,
    delete: deleteWaterBorehole,
    idOf: (b: any) => b.waterBoreholeId,
    labelOf: (b: any) => b.boreholeName,
    columns: [
      { header: "Name", accessor: (b: any) => <span className="font-medium">{b.boreholeName}</span> },
      { header: "Location", accessor: (b: any) => b.location ?? "—" },
      { header: "Pump", accessor: (b: any) => b.pumpType ?? "—" },
      { header: "Status", accessor: (b: any) => <Badge variant={b.status === "Active" ? "default" : "secondary"}>{b.status ?? "—"}</Badge> },
    ],
    Modal: BoreholeModal,
  },
  {
    key: "raw-materials",
    label: "Raw materials & supplies",
    icon: Box,
    addHref: "/water-raw-materials",
    fetch: listWaterRawMaterialItems,
    delete: deleteWaterRawMaterialItem,
    idOf: (i: any) => i.waterRawMaterialItemId,
    labelOf: (i: any) => i.itemName,
    columns: [
      { header: "Item", accessor: (i: any) => <span className="font-medium">{i.itemName}</span> },
      { header: "Category", accessor: (i: any) => i.category ?? "—" },
      { header: "Unit", accessor: (i: any) => i.unitOfMeasure ?? "—" },
      { header: "Stock", accessor: (i: any) => i.currentQuantity ?? 0 },
      { header: "Min alert", accessor: (i: any) => i.minimumStockAlert ?? "—" },
      { header: "Active", accessor: (i: any) => i.isActive ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
    Modal: RawMaterialModal,
  },
  {
    key: "suppliers",
    label: "Suppliers",
    icon: Truck,
    addHref: "/water-suppliers",
    fetch: () => listWaterSuppliers({ includeInactive: true }),
    delete: deleteWaterSupplier,
    idOf: (s: any) => s.waterSupplierId,
    labelOf: (s: any) => s.supplierName,
    columns: [
      { header: "Name",   accessor: (s: any) => <span className="font-medium">{s.supplierName}</span> },
      { header: "Type",   accessor: (s: any) => s.supplierType ?? "—" },
      { header: "Phone",  accessor: (s: any) => s.phone ?? "—" },
      { header: "Email",  accessor: (s: any) => s.email ?? "—" },
      { header: "Active", accessor: (s: any) => s.isActive ? "Yes" : "No" },
    ],
    // No inline modal yet — the standalone /water-suppliers page already has
    // the full form. Add/Edit deep-link to that page; delete works inline.
  },
  {
    key: "staff",
    label: "Staff",
    icon: Users2,
    addHref: "/water-staff",
    fetch: () => listWaterStaff(),
    delete: deleteWaterStaff,
    idOf: (s: any) => s.waterStaffId,
    labelOf: (s: any) => `${s.firstName ?? ""} ${s.lastName ?? ""}`.trim(),
    columns: [
      { header: "Name", accessor: (s: any) => <span className="font-medium">{`${s.firstName ?? ""} ${s.lastName ?? ""}`.trim() || "—"}</span> },
      { header: "Role", accessor: (s: any) => s.role ?? "—" },
      { header: "Phone", accessor: (s: any) => s.phoneNumber ?? "—" },
      { header: "Salary type", accessor: (s: any) => s.salaryType ?? "—" },
      { header: "Base pay", accessor: (s: any) => fmtGhc(s.basePay) },
    ],
    Modal: StaffModal,
  },
]

export default function WaterSetupPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard") }
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center gap-3">
            <div className="rounded-lg bg-sky-100 p-2"><Settings className="h-6 w-6 text-sky-700" /></div>
            <div>
              <h1 className="text-2xl font-semibold text-slate-900">Water company setup</h1>
              <p className="text-sm text-slate-600">
                Everything the daily flow depends on — products, drivers, machines, routes, suppliers, staff.
                Add a row here to make it available in production batches, sales, payroll, etc.
              </p>
            </div>
          </div>

          <Tabs defaultValue="company" className="w-full">
            <div className="mb-2.5 text-sm font-semibold text-slate-800">
              Choose setup area
            </div>
            {/* Card-tile tabs: each setup area is a distinct white tile with a
                clear active state, so the list reads as an organized grid of
                choices rather than a flat run of same-weight pills (visual
                hierarchy feedback #1). Wraps to multiple rows on mobile. */}
            <TabsList className="grid h-auto w-full grid-cols-2 gap-2 bg-transparent p-0 sm:flex sm:flex-wrap">
              {/* Prompt 2 §14/§15 — company-level settings live in their own
                  tab so the rest of the per-entity tabs stay focused. */}
              <TabsTrigger
                value="company"
                className="shrink-0 cursor-pointer justify-start rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-slate-700 shadow-sm transition hover:border-sky-300 hover:text-sky-700 data-[state=active]:border-sky-500 data-[state=active]:bg-sky-50 data-[state=active]:text-sky-700 data-[state=active]:shadow"
              >
                <DollarSign className="h-4 w-4 mr-1.5 shrink-0" /> Company
              </TabsTrigger>
              {tabs.map((t) => (
                <TabsTrigger
                  key={t.key}
                  value={t.key}
                  className="shrink-0 cursor-pointer items-start justify-start whitespace-normal text-left leading-tight rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-slate-700 shadow-sm transition hover:border-sky-300 hover:text-sky-700 data-[state=active]:border-sky-500 data-[state=active]:bg-sky-50 data-[state=active]:text-sky-700 data-[state=active]:shadow"
                >
                  <t.icon className="h-4 w-4 mr-1.5 mt-0.5 shrink-0" />
                  <span className="min-w-0 break-words">{t.label}</span>
                </TabsTrigger>
              ))}
            </TabsList>

            <TabsContent value="company" className="mt-4">
              <CompanySettingsCard />
            </TabsContent>

            {tabs.map((t) => (
              <TabsContent key={t.key} value={t.key} className="mt-4">
                <SetupSection tab={t} />
              </TabsContent>
            ))}
          </Tabs>
        </main>
      </div>
    </div>
  )
}

// ----------------------------------------------------------------------------
// Company settings — Prompt 2 Part 2 §7 + §8.
//
// Single tab that lets the owner edit BOTH the business profile (brand,
// location, owner, sachets per bag, …) AND the currency settings. If the
// company profile doesn't exist yet, this acts as a first-time setup form;
// otherwise it acts as an edit form.
// ----------------------------------------------------------------------------
function CompanySettingsCard() {
  const { toast } = useToast()
  const apply = useFarmSettingsStore((s) => s.apply)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  // Currency settings (Farms row).
  const [code, setCode] = useState("GHS")
  const [symbol, setSymbol] = useState("GHC")
  const [showSymbol, setShowSymbol] = useState(true)

  // Company profile (WaterCompanyProfiles row). hasProfile tracks first-run
  // vs edit — used to switch between setupWaterCompany and updateWaterCompanyProfile.
  const [hasProfile, setHasProfile] = useState(false)
  const [profile, setProfile] = useState({
    brandName: "",
    // Default must be one of the SP's allowed values (Sachet|Bottled|Both).
    // Previously defaulted to "WaterProduction" — completely outside the SP's
    // IN list, so every Save was rejected with "BusinessType must be Sachet,
    // Bottled, or Both." James reported this on 2026-05-30.
    businessType: "Sachet",
    waterSourceType: "Borehole",
    productionSiteAddress: "",
    mainLocation: "",
    ownerName: "",
    phoneNumber: "",
    defaultBagSachetCount: 30,
    notes: "",
  })

  useEffect(() => {
    void (async () => {
      setLoading(true)
      try {
        const [farmSettings, prof] = await Promise.all([
          fetchFarmSettings().catch(() => null),
          getWaterCompanyProfile().catch(() => null),
        ])
        if (farmSettings) {
          setCode(farmSettings.currencyCode)
          setSymbol(farmSettings.currencySymbol)
          setShowSymbol(farmSettings.showCurrencySymbol)
          apply(farmSettings)
        }
        if (prof) {
          setHasProfile(true)
          setProfile({
            brandName: prof.brandName ?? "",
            businessType: prof.businessType ?? "WaterProduction",
            waterSourceType: prof.waterSourceType ?? "Borehole",
            productionSiteAddress: prof.productionSiteAddress ?? "",
            mainLocation: prof.mainLocation ?? "",
            ownerName: prof.ownerName ?? "",
            phoneNumber: prof.phoneNumber ?? "",
            defaultBagSachetCount: prof.defaultBagSachetCount ?? 30,
            notes: prof.notes ?? "",
          })
        }
      } catch (e: any) {
        toast({ title: "Could not load company settings", description: e?.message ?? String(e), variant: "destructive" })
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function save() {
    setSaving(true)
    try {
      // 1. Persist business profile.
      // Defence-in-depth: even if `profile.businessType` is loaded as a stale
      // pre-fix value (e.g. "WaterProduction" left over from the old dropdown),
      // normalize against the SP whitelist before sending so we never trip
      // RAISERROR. Same for waterSourceType.
      const allowedBiz    = ["Sachet", "Bottled", "Both"]
      const allowedSource = ["Borehole", "GhanaWater", "Tanker", "Mixed"]
      const profilePayload = {
        brandName: profile.brandName || null,
        businessType:
          allowedBiz.find(o => o.toLowerCase() === (profile.businessType ?? "").toLowerCase())
          ?? "Sachet",
        waterSourceType:
          allowedSource.find(o => o.toLowerCase() === (profile.waterSourceType ?? "").toLowerCase())
          ?? "Borehole",
        productionSiteAddress: profile.productionSiteAddress || null,
        mainLocation: profile.mainLocation || null,
        ownerName: profile.ownerName || null,
        phoneNumber: profile.phoneNumber || null,
        defaultCurrency: code.trim() || "GHS",
        defaultBagSachetCount: profile.defaultBagSachetCount || 30,
        notes: profile.notes || null,
      }
      if (hasProfile) await updateWaterCompanyProfile(profilePayload)
      else            { await setupWaterCompany(profilePayload); setHasProfile(true) }

      // 2. Persist currency / display settings.
      const next = await updateFarmCurrency({
        currencyCode: code.trim() || "GHS",
        currencySymbol: symbol.trim() || "GHC",
        showCurrencySymbol: showSymbol,
      })
      if (next) apply(next)

      toast({ title: hasProfile ? "Company settings saved." : "Water company set up." })
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  if (loading) {
    return (
      <Card><CardContent className="p-6 text-slate-500 flex items-center gap-2">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading company settings…
      </CardContent></Card>
    )
  }

  return (
    <Card>
      <CardContent className="p-4 space-y-4">
        <FormSection title="Business profile" color="indigo">
          <FormField label="Brand name" full>
            <Input value={profile.brandName} onChange={(e) => setProfile({ ...profile, brandName: e.target.value })} />
          </FormField>
          {/* James (2026-05-30): both selects had options that don't match the
              backend SP whitelist. Picking any of them caused
              "BusinessType must be Sachet, Bottled, or Both." or the
              waterSourceType equivalent. Aligned with spWaterCompany_Setup
              and added case-insensitive normalize so old DB values still
              load to a valid trigger state. */}
          <FormField label="Business type *">
            {(() => {
              const allowed = ["Sachet", "Bottled", "Both"]
              const match = allowed.find(o => o.toLowerCase() === (profile.businessType ?? "").toLowerCase())
              const value = match ?? "Sachet"
              return (
                <Select value={value} onValueChange={(v) => setProfile({ ...profile, businessType: v })}>
                  <SelectTrigger><SelectValue placeholder="Pick business type" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Sachet">Sachet</SelectItem>
                    <SelectItem value="Bottled">Bottled</SelectItem>
                    <SelectItem value="Both">Both</SelectItem>
                  </SelectContent>
                </Select>
              )
            })()}
          </FormField>
          <FormField label="Water source *">
            {(() => {
              const allowed = ["Borehole", "GhanaWater", "Tanker", "Mixed"]
              const match = allowed.find(o => o.toLowerCase() === (profile.waterSourceType ?? "").toLowerCase())
              const value = match ?? "Borehole"
              return (
                <Select value={value} onValueChange={(v) => setProfile({ ...profile, waterSourceType: v })}>
                  <SelectTrigger><SelectValue placeholder="Pick water source" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Borehole">Borehole</SelectItem>
                    <SelectItem value="GhanaWater">Ghana Water</SelectItem>
                    <SelectItem value="Tanker">Tanker</SelectItem>
                    <SelectItem value="Mixed">Mixed</SelectItem>
                  </SelectContent>
                </Select>
              )
            })()}
          </FormField>
          <FormField label="Production site address" full>
            <Input value={profile.productionSiteAddress} onChange={(e) => setProfile({ ...profile, productionSiteAddress: e.target.value })} />
          </FormField>
          <FormField label="Main location / town" full>
            <Input value={profile.mainLocation} onChange={(e) => setProfile({ ...profile, mainLocation: e.target.value })} />
          </FormField>
        </FormSection>

        <FormSection title="Owner" color="blue">
          <FormField label="Owner name">
            <Input value={profile.ownerName} onChange={(e) => setProfile({ ...profile, ownerName: e.target.value })} />
          </FormField>
          <FormField label="Phone">
            <Input value={profile.phoneNumber} onChange={(e) => setProfile({ ...profile, phoneNumber: e.target.value })} />
          </FormField>
        </FormSection>

        <FormSection title="Production defaults" color="green">
          <FormField label="Sachets per bag" hint="Used as default when recording production batches.">
            <NumberInput min={1} value={profile.defaultBagSachetCount}
              onChange={(e) => setProfile({ ...profile, defaultBagSachetCount: Number(e.target.value) || 30 })} />
          </FormField>
        </FormSection>

        <FormSection title="Currency settings" color="amber">
          <FormField label="Currency code" hint="ISO-style identifier — e.g. GHS, USD, EUR.">
            <Input value={code} onChange={(e) => setCode(e.target.value)} maxLength={10} />
          </FormField>
          <FormField label="Currency symbol" hint="Prefix rendered before amounts. e.g. GHC, ₵, $, ₦.">
            <Input value={symbol} onChange={(e) => setSymbol(e.target.value)} maxLength={10} />
          </FormField>
          <FormField label="Show currency symbol on pages" full>
            <div className="flex items-center justify-between rounded border p-2">
              <span className="text-sm text-slate-700">
                When off, amounts render as bare numbers (e.g. <span className="font-mono">1,234.50</span>).
              </span>
              <Switch checked={showSymbol} onCheckedChange={setShowSymbol} />
            </div>
          </FormField>
          <div className="text-xs text-slate-500 col-span-2">
            Preview: <span className="font-mono">{showSymbol ? `${symbol} ` : ""}1,234.50</span>
          </div>
        </FormSection>

        <FormSection title="Notes" color="slate" columns={1}>
          <FormField label="Notes">
            <Textarea value={profile.notes} onChange={(e) => setProfile({ ...profile, notes: e.target.value })} />
          </FormField>
        </FormSection>

        <div className="flex justify-end">
          <Button onClick={save} disabled={saving}>
            {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {hasProfile ? "Save settings" : "Set up Water Company"}</>}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

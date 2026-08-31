"use client"

// Unified Poultry company setup hub — the counterpart of /water-setup.
//
// One page, tabbed by entity, so an operator sets up everything the daily flow
// depends on in one place instead of hunting across ten routes.
//
// Each tab embeds a SetupSection that:
//   * lists the items via the existing list*() API helper,
//   * deletes rows inline where the API supports it,
//   * sends Add / Edit to the dedicated route. Those pages already carry
//     polished forms; duplicating them here would give the farm two forms per
//     entity that drift apart. /water-setup takes the same approach on the tabs
//     where it has no inline modal.
//
// Tabs map onto the water hub: Machines -> Houses and Boreholes -> Flock
// Groups are the poultry physical-plant equivalents; the rest carry over by
// name. The Company tab edits the profile added by migration 212 plus the
// farm's currency settings.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Settings, Plus, Pencil, Trash2, Loader2, Save, DollarSign,
  Users, Truck, Route as RouteIcon, Building2, Bird, Box, Users2, Package, UserCog,
} from "lucide-react"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Label } from "@/components/ui/label"
import { fetchFarmSettings, updateFarmCurrency, useFarmSettingsStore } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { getUserContext } from "@/lib/api/config"
import { CurrencySelect } from "@/components/ui/currency-select"
import { currencySymbolFor } from "@/lib/constants/currencies"
import {
  getPoultryCompanyProfile, setupPoultryCompany, updatePoultryCompanyProfile,
  POULTRY_BUSINESS_TYPES, POULTRY_HOUSING_SYSTEMS, POULTRY_HOUSING_LABELS,
} from "@/lib/api/poultry-company"
import {
  listPoultryDrivers, deletePoultryDriver,
  listPoultryVehicles, deletePoultryVehicle,
  listPoultryRoutes, deletePoultryRoute,
} from "@/lib/api/poultry-distribution"
import {
  listPoultryProducts, deletePoultryProduct,
  listPoultryRawMaterialItems, deletePoultryRawMaterialItem,
} from "@/lib/api/poultry-inventory"
import { getCustomers, deleteCustomer } from "@/lib/api/customer"
import { getSuppliers, deleteSupplier } from "@/lib/api/supplier"
import { getHouses, deleteHouse } from "@/lib/api/house"
import { getFlocks, deleteFlock } from "@/lib/api/flock"
import { getEmployees, deleteEmployee } from "@/lib/api/admin"

type Column<T> = { header: string; accessor: (item: T) => React.ReactNode }
type SetupTab<T> = {
  key: string
  label: string
  icon: React.ComponentType<{ className?: string }>
  fetch: () => Promise<T[]>
  idOf: (item: T) => number | string
  labelOf: (item: T) => string
  delete?: (id: any) => Promise<void>
  /** The dedicated page. Add and Edit both go here. */
  addHref: string
  columns: Column<T>[]
}

const dash = (v: unknown) => (v === null || v === undefined || v === "" ? "—" : String(v))

/**
 * The older poultry API helpers return ApiResponse<T[]> and take userId/farmId,
 * unlike the newer poultry-distribution / poultry-inventory helpers which
 * return the array directly and read the company from context. This unwraps the
 * former so every tab's fetch() has the same shape.
 */
async function unwrap<T>(p: Promise<{ success: boolean; data?: T[]; message?: string }>): Promise<T[]> {
  const r = await p
  if (!r.success) throw new Error(r.message || "Request failed")
  return r.data ?? []
}
const ctx = () => getUserContext()

const tabs: SetupTab<any>[] = [
  {
    key: "products",
    label: "Products",
    icon: Package,
    addHref: "/poultry-products",
    fetch: listPoultryProducts,
    delete: deletePoultryProduct,
    idOf: (p: any) => p.poultryProductId,
    labelOf: (p: any) => p.name,
    columns: [
      { header: "Name", accessor: (p: any) => <span className="font-medium">{p.name}</span> },
      { header: "Unit", accessor: (p: any) => dash(p.unit) },
      { header: "Type", accessor: (p: any) => dash(p.productType) },
      { header: "In stock", accessor: (p: any) => p.stockOnHand ?? 0 },
      { header: "Active", accessor: (p: any) => p.isActive ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
  },
  {
    key: "customers",
    label: "Customers",
    icon: Users,
    addHref: "/customers",
    fetch: () => unwrap(getCustomers(ctx().userId, ctx().farmId)),
    delete: async (id: number) => { await deleteCustomer(id, ctx().userId, ctx().farmId) },
    idOf: (c: any) => c.customerId,
    labelOf: (c: any) => c.name,
    columns: [
      { header: "Name", accessor: (c: any) => <span className="font-medium">{c.name}</span> },
      { header: "Phone", accessor: (c: any) => dash(c.contactPhone) },
      { header: "Email", accessor: (c: any) => dash(c.contactEmail) },
      { header: "City", accessor: (c: any) => dash(c.city) },
    ],
  },
  {
    key: "drivers",
    label: "Drivers",
    icon: Users2,
    addHref: "/poultry-drivers",
    fetch: listPoultryDrivers,
    delete: deletePoultryDriver,
    idOf: (d: any) => d.poultryDriverId,
    labelOf: (d: any) => d.driverName,
    columns: [
      { header: "Name", accessor: (d: any) => <span className="font-medium">{d.driverName}</span> },
      { header: "Phone", accessor: (d: any) => dash(d.phoneNumber) },
      { header: "Licence", accessor: (d: any) => dash(d.licenseNumber) },
      { header: "Commission / crate", accessor: (d: any) => dash(d.commissionPerCrate) },
      { header: "Active", accessor: (d: any) => d.isActive ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
  },
  {
    key: "vehicles",
    label: "Vehicles",
    icon: Truck,
    addHref: "/poultry-vehicles",
    fetch: listPoultryVehicles,
    delete: deletePoultryVehicle,
    idOf: (v: any) => v.poultryVehicleId,
    labelOf: (v: any) => v.vehicleName,
    columns: [
      { header: "Name", accessor: (v: any) => <span className="font-medium">{v.vehicleName}</span> },
      { header: "Reg #", accessor: (v: any) => dash(v.registrationNumber) },
      { header: "Type", accessor: (v: any) => dash(v.vehicleType) },
      { header: "Capacity", accessor: (v: any) => v.capacityCrates ? `${v.capacityCrates} crates` : "—" },
      { header: "Status", accessor: (v: any) => <Badge variant={v.status === "Active" ? "default" : "secondary"}>{dash(v.status)}</Badge> },
    ],
  },
  {
    key: "routes",
    label: "Routes",
    icon: RouteIcon,
    addHref: "/poultry-routes",
    fetch: listPoultryRoutes,
    delete: deletePoultryRoute,
    idOf: (r: any) => r.poultryRouteId,
    labelOf: (r: any) => r.routeName,
    columns: [
      { header: "Name", accessor: (r: any) => <span className="font-medium">{r.routeName}</span> },
      { header: "Area covered", accessor: (r: any) => dash(r.areaCovered) },
      { header: "Expected customers", accessor: (r: any) => dash(r.expectedCustomers) },
      { header: "Expected crates", accessor: (r: any) => dash(r.expectedCratesSold) },
    ],
  },
  {
    // Water's Machines tab. Houses are the poultry equivalent — the physical
    // structures production happens in.
    key: "houses",
    label: "Houses",
    icon: Building2,
    addHref: "/houses",
    fetch: () => unwrap(getHouses(ctx().userId, ctx().farmId)),
    delete: async (id: number) => { await deleteHouse(id, ctx().userId, ctx().farmId) },
    idOf: (h: any) => h.houseId,
    labelOf: (h: any) => h.name,
    columns: [
      { header: "Name", accessor: (h: any) => <span className="font-medium">{h.name}</span> },
      { header: "Capacity", accessor: (h: any) => dash(h.capacity) },
      { header: "Location", accessor: (h: any) => dash(h.location) },
    ],
  },
  {
    // Water's Boreholes tab. Flock groups are what the poultry farm actually
    // runs its production against.
    key: "flocks",
    label: "Flock groups",
    icon: Bird,
    addHref: "/flocks",
    fetch: () => unwrap(getFlocks(ctx().userId, ctx().farmId)),
    delete: async (id: number) => { await deleteFlock(id, ctx().userId, ctx().farmId) },
    idOf: (f: any) => f.flockId,
    labelOf: (f: any) => f.name,
    columns: [
      { header: "Name", accessor: (f: any) => <span className="font-medium">{f.name}</span> },
      { header: "Breed", accessor: (f: any) => dash(f.breed) },
      { header: "Birds", accessor: (f: any) => dash(f.quantity) },
      { header: "Batch", accessor: (f: any) => dash(f.batchName) },
      { header: "Active", accessor: (f: any) => f.active ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
  },
  {
    key: "raw-materials",
    label: "Raw materials & supplies",
    icon: Box,
    addHref: "/poultry-raw-materials",
    fetch: listPoultryRawMaterialItems,
    delete: deletePoultryRawMaterialItem,
    idOf: (i: any) => i.poultryRawMaterialItemId,
    labelOf: (i: any) => i.itemName,
    columns: [
      { header: "Item", accessor: (i: any) => <span className="font-medium">{i.itemName}</span> },
      { header: "Category", accessor: (i: any) => dash(i.category) },
      { header: "Unit", accessor: (i: any) => dash(i.unitOfMeasure) },
      { header: "Stock", accessor: (i: any) => i.currentQuantity ?? 0 },
      { header: "Min alert", accessor: (i: any) => dash(i.minimumStockAlert) },
      { header: "Active", accessor: (i: any) => i.isActive ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge variant="secondary">No</Badge> },
    ],
  },
  {
    key: "suppliers",
    label: "Suppliers",
    icon: Truck,
    addHref: "/suppliers",
    fetch: () => unwrap(getSuppliers(ctx().userId, ctx().farmId)),
    delete: async (id: number) => { await deleteSupplier(id, ctx().userId, ctx().farmId) },
    idOf: (s: any) => s.supplierId,
    labelOf: (s: any) => s.name,
    columns: [
      { header: "Name", accessor: (s: any) => <span className="font-medium">{s.name}</span> },
      { header: "Phone", accessor: (s: any) => dash(s.contactPhone) },
      { header: "Email", accessor: (s: any) => dash(s.contactEmail) },
      { header: "City", accessor: (s: any) => dash(s.city) },
    ],
  },
  {
    key: "employees",
    label: "Employees",
    icon: UserCog,
    addHref: "/employees",
    fetch: () => unwrap(getEmployees()),
    delete: async (id: string) => { await deleteEmployee(id) },
    idOf: (e: any) => e.id,
    labelOf: (e: any) => `${e.firstName ?? ""} ${e.lastName ?? ""}`.trim() || e.userName || e.email,
    columns: [
      { header: "Name", accessor: (e: any) => <span className="font-medium">{`${e.firstName ?? ""} ${e.lastName ?? ""}`.trim() || "—"}</span> },
      { header: "Email", accessor: (e: any) => dash(e.email) },
      { header: "Phone", accessor: (e: any) => dash(e.phoneNumber) },
      { header: "Role", accessor: (e: any) => e.isAdmin ? <Badge>Admin</Badge> : e.isStaff ? <Badge variant="secondary">Staff</Badge> : "—" },
    ],
  },
]

function SetupSection<T>({ tab }: { tab: SetupTab<T> }) {
  const { toast } = useToast()
  const [items, setItems] = useState<T[]>([])
  const [loading, setLoading] = useState(true)
  const [deleteTarget, setDeleteTarget] = useState<T | null>(null)

  async function load() {
    setLoading(true)
    try { setItems(await tab.fetch()) }
    catch (e: any) { toast({ title: `Could not load ${tab.label.toLowerCase()}`, description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [])

  // Client-side paging: every tab renders through this one panel, so a single
  // hook here gives all of them the same pager.
  const pg = usePagination(items as any[])

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

  const singular = tab.label.toLowerCase().replace(/s$/, "")

  return (
    <Card>
      <CardContent className="p-0">
        <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b">
          <div className="flex items-center gap-2 text-slate-700">
            <tab.icon className="h-5 w-5 text-amber-600" />
            <span className="font-semibold">{tab.label}</span>
            {!loading && <Badge variant="secondary" className="ml-1">{items.length}</Badge>}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button asChild size="sm" variant="outline">
              <Link href={tab.addHref}><Pencil className="h-4 w-4 mr-1" /> Open full page</Link>
            </Button>
            <Button asChild size="sm">
              <Link href={tab.addHref}><Plus className="h-4 w-4 mr-1" /> Add {singular}</Link>
            </Button>
          </div>
        </div>
        {loading ? (
          <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : items.length === 0 ? (
          <div className="p-8 text-center text-slate-500">
            No {tab.label.toLowerCase()} yet. Click <span className="font-medium">Add {singular}</span> above to create your first one.
          </div>
        ) : (
          <MobileCardList
            items={pg.pageItems}
            pagination={pg.paginationProps}
            getKey={(item: any) => tab.idOf(item)}
            primary={(item: any) => tab.labelOf(item)}
            secondary={(item: any) => tab.columns.length > 1 ? <span>{tab.columns[1].accessor(item)}</span> : null}
            details={(item: any) => tab.columns.map((c) => ({ label: c.header, value: c.accessor(item) }))}
            actions={tab.delete ? (item: any) => (
              <>
                <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                  <Link href={tab.addHref}><Pencil className="h-4 w-4 mr-1" /> Edit</Link>
                </Button>
                <Button size="sm" variant="outline" className="flex-1 h-10 text-rose-600 border-rose-200" onClick={() => setDeleteTarget(item)}>
                  <Trash2 className="h-4 w-4 mr-1" /> Delete
                </Button>
              </>
            ) : undefined}
            desktopTable={
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      {tab.columns.map((c) => <TableHead key={c.header}>{c.header}</TableHead>)}
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pg.pageItems.map((item: any) => (
                      <TableRow key={tab.idOf(item)}>
                        {tab.columns.map((c) => <TableCell key={c.header}>{c.accessor(item)}</TableCell>)}
                        <TableCell className="text-right whitespace-nowrap">
                          <Button asChild size="sm" variant="ghost" title={`Edit on the ${tab.label.toLowerCase()} page`}>
                            <Link href={tab.addHref}><Pencil className="h-4 w-4" /></Link>
                          </Button>
                          {tab.delete && (
                            <Button size="sm" variant="ghost" className="text-rose-600 hover:bg-rose-50" onClick={() => setDeleteTarget(item)} title={`Delete ${singular}`}>
                              <Trash2 className="h-4 w-4" />
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

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
        title={`Delete ${singular}?`}
        description={deleteTarget ? `${tab.labelOf(deleteTarget)} will be permanently removed. Records that reference it may stop resolving.` : ""}
        onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
      />
    </Card>
  )
}

// ----------------------------------------------------------------------------
// Company tab — the profile (migration 212) plus the farm's currency settings,
// mirroring water-setup's CompanySettingsCard. Acts as first-time setup when no
// profile exists yet and as an edit form afterwards.
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

  // Company profile (PoultryCompanyProfiles row).
  const [hasProfile, setHasProfile] = useState(false)
  const [profile, setProfile] = useState({
    brandName: "",
    businessType: "Layers" as string,
    housingSystem: "DeepLitter" as string,
    farmSiteAddress: "",
    mainLocation: "",
    ownerName: "",
    phoneNumber: "",
    email: "",
    defaultCurrency: "GHC",
    defaultCrateEggCount: 30,
    totalCapacity: null as number | null,
    operatingHours: "",
    notes: "",
  })

  useEffect(() => {
    void (async () => {
      setLoading(true)
      try {
        const [farmSettings, prof] = await Promise.all([
          fetchFarmSettings().catch(() => null),
          getPoultryCompanyProfile().catch(() => null),
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
            businessType: prof.businessType ?? "Layers",
            housingSystem: prof.housingSystem ?? "DeepLitter",
            farmSiteAddress: prof.farmSiteAddress ?? "",
            mainLocation: prof.mainLocation ?? "",
            ownerName: prof.ownerName ?? "",
            phoneNumber: prof.phoneNumber ?? "",
            email: prof.email ?? "",
            defaultCurrency: prof.defaultCurrency ?? "GHC",
            defaultCrateEggCount: prof.defaultCrateEggCount ?? 30,
            totalCapacity: prof.totalCapacity ?? null,
            operatingHours: prof.operatingHours ?? "",
            notes: prof.notes ?? "",
          })
          // A company set up before the Farms row carried a currency would show
          // the GHS default here while its profile said otherwise. Seed the
          // picker from the profile when the Farms row has nothing yet.
          if (!farmSettings && prof.defaultCurrency) {
            setCode(prof.defaultCurrency.toUpperCase())
            setSymbol(currencySymbolFor(prof.defaultCurrency))
          }
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
      // Normalize what we SEND: a value loaded from an older row could be
      // lowercase or blank, which the dropdown tolerates for display but the
      // database rejects on save.
      const payload = {
        ...profile,
        // The Currency section below is the single control; mirror it into the
        // profile so the two rows always agree.
        defaultCurrency: code,
        businessType: POULTRY_BUSINESS_TYPES.find(o => o.toLowerCase() === (profile.businessType ?? "").toLowerCase()) ?? "Layers",
        housingSystem: POULTRY_HOUSING_SYSTEMS.find(o => o.toLowerCase() === (profile.housingSystem ?? "").toLowerCase()) ?? "DeepLitter",
        defaultCrateEggCount: Math.max(1, Number(profile.defaultCrateEggCount) || 30),
        totalCapacity: profile.totalCapacity === null || Number.isNaN(Number(profile.totalCapacity))
          ? null : Number(profile.totalCapacity),
      }

      if (hasProfile) await updatePoultryCompanyProfile(payload)
      else { await setupPoultryCompany(payload); setHasProfile(true) }

      const updated = await updateFarmCurrency({ currencyCode: code, currencySymbol: symbol, showCurrencySymbol: showSymbol })
      if (updated) apply(updated)

      toast({ title: hasProfile ? "Company settings saved" : "Poultry Company set up", description: hasProfile ? undefined : "Default cash accounts seeded." })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  if (loading) {
    return (
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b">
          <div className="flex items-center gap-2 text-slate-700">
            <Building2 className="h-5 w-5 text-amber-600" />
            <span className="font-semibold">Company</span>
          </div>
          <Button asChild size="sm" variant="outline">
            <Link href="/poultry-company-setup"><Pencil className="h-4 w-4 mr-1" /> Open full page</Link>
          </Button>
        </div>
        <CardContent className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</CardContent>
      </Card>
    )
  }

  return (
    <Card>
      {/* Same header bar the entity tabs get, so Company doesn't read as a
          different kind of tab. There is no Add button — a farm has exactly one
          company — but it does have a dedicated page, so the escape hatch
          belongs here too. */}
      <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b">
        <div className="flex items-center gap-2 text-slate-700">
          <Building2 className="h-5 w-5 text-amber-600" />
          <span className="font-semibold">Company</span>
          {hasProfile && (
            <Badge variant="secondary" className="ml-1">Set up</Badge>
          )}
        </div>
        <Button asChild size="sm" variant="outline">
          <Link href="/poultry-company-setup"><Pencil className="h-4 w-4 mr-1" /> Open full page</Link>
        </Button>
      </div>
      <CardContent className="p-4 md:p-6 space-y-6">
        <div>
          <h2 className="text-base font-semibold text-slate-900 mb-3 flex items-center gap-2">
            <Building2 className="h-4 w-4 text-amber-600" /> Business details
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="md:col-span-2"><Label>Farm / brand name</Label>
              <Input value={profile.brandName} onChange={(e) => setProfile({ ...profile, brandName: e.target.value })} placeholder="e.g. Gyimah Farm" /></div>

            <div><Label>Business type</Label>
              <Select value={POULTRY_BUSINESS_TYPES.find(o => o.toLowerCase() === profile.businessType.toLowerCase()) ?? "Layers"}
                      onValueChange={(v) => setProfile({ ...profile, businessType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{POULTRY_BUSINESS_TYPES.map(o => <SelectItem key={o} value={o}>{o}</SelectItem>)}</SelectContent>
              </Select></div>

            <div><Label>Housing system</Label>
              <Select value={POULTRY_HOUSING_SYSTEMS.find(o => o.toLowerCase() === profile.housingSystem.toLowerCase()) ?? "DeepLitter"}
                      onValueChange={(v) => setProfile({ ...profile, housingSystem: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{POULTRY_HOUSING_SYSTEMS.map(o => <SelectItem key={o} value={o}>{POULTRY_HOUSING_LABELS[o]}</SelectItem>)}</SelectContent>
              </Select></div>

            <div className="md:col-span-2"><Label>Farm site address</Label>
              <Input value={profile.farmSiteAddress} onChange={(e) => setProfile({ ...profile, farmSiteAddress: e.target.value })} /></div>

            <div><Label>Main location / town</Label>
              <Input value={profile.mainLocation} onChange={(e) => setProfile({ ...profile, mainLocation: e.target.value })} /></div>

            <div><Label>Owner name</Label>
              <Input value={profile.ownerName} onChange={(e) => setProfile({ ...profile, ownerName: e.target.value })} /></div>

            <div><Label>Phone</Label>
              <Input value={profile.phoneNumber} onChange={(e) => setProfile({ ...profile, phoneNumber: e.target.value })} placeholder="+233..." /></div>

            <div><Label>Email</Label>
              <Input type="email" value={profile.email} onChange={(e) => setProfile({ ...profile, email: e.target.value })} /></div>

            <div><Label>Eggs per crate</Label>
              <NumberInput min={1} value={profile.defaultCrateEggCount}
                onChange={(e) => setProfile({ ...profile, defaultCrateEggCount: Number(e.target.value) || 30 })} />
              <p className="mt-1 text-xs text-slate-500">Converts crates to eggs when a vehicle is loaded and a driver return is reconciled.</p></div>

            <div><Label>Total capacity (birds)</Label>
              <NumberInput min={0} value={profile.totalCapacity ?? ""}
                onChange={(e) => setProfile({ ...profile, totalCapacity: e.target.value === "" ? null : Number(e.target.value) })} /></div>

            <div><Label>Operating hours</Label>
              <Input value={profile.operatingHours} onChange={(e) => setProfile({ ...profile, operatingHours: e.target.value })} placeholder="e.g. 6:00 AM – 6:00 PM" /></div>

            <div className="md:col-span-2"><Label>Notes</Label>
              <Textarea value={profile.notes} onChange={(e) => setProfile({ ...profile, notes: e.target.value })} /></div>
          </div>
        </div>

        <div className="border-t pt-5">
          <h2 className="text-base font-semibold text-slate-900 mb-3 flex items-center gap-2">
            <DollarSign className="h-4 w-4 text-amber-600" /> Currency
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div><Label htmlFor="farm-currency">Currency</Label>
              {/* Picking a currency fills in its standard symbol, but the field
                  stays editable: plenty of Ghanaian businesses write "GHC"
                  rather than the ICU symbol "₵". */}
              <CurrencySelect id="farm-currency" value={code}
                onChange={(o) => { setCode(o.code); setSymbol(o.symbol) }} /></div>
            <div><Label>Symbol</Label>
              <Input value={symbol} onChange={(e) => setSymbol(e.target.value)} placeholder="GHC" /></div>
            <div className="flex items-end gap-3 pb-2">
              <Switch checked={showSymbol} onCheckedChange={setShowSymbol} id="show-symbol" />
              <Label htmlFor="show-symbol" className="mb-0">Show symbol on amounts</Label>
            </div>
          </div>
        </div>

        <div className="flex justify-end">
          <Button onClick={save} disabled={saving}>
            {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {hasProfile ? "Save changes" : "Set up Poultry Company"}</>}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

export default function PoultrySetupPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard") }
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center gap-3">
            <div className="rounded-lg bg-amber-100 p-2"><Settings className="h-6 w-6 text-amber-700" /></div>
            <div>
              <h1 className="text-2xl font-semibold text-slate-900">Poultry farm setup</h1>
              <p className="text-sm text-slate-600">
                Everything the daily flow depends on — products, drivers, houses, flock groups, suppliers, staff.
                Add a row here to make it available in production, sales, deliveries and payroll.
              </p>
            </div>
          </div>

          <Tabs defaultValue="company" className="w-full">
            <div className="mb-2.5 text-sm font-semibold text-slate-800">Choose setup area</div>
            <TabsList className="grid h-auto w-full grid-cols-2 gap-2 bg-transparent p-0 sm:flex sm:flex-wrap">
              <TabsTrigger
                value="company"
                className="shrink-0 cursor-pointer justify-start rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-slate-700 shadow-sm transition hover:border-amber-300 hover:text-amber-700 data-[state=active]:border-amber-500 data-[state=active]:bg-amber-50 data-[state=active]:text-amber-700 data-[state=active]:shadow"
              >
                <DollarSign className="h-4 w-4 mr-1.5 shrink-0" /> Company
              </TabsTrigger>
              {tabs.map((t) => (
                <TabsTrigger
                  key={t.key}
                  value={t.key}
                  className="shrink-0 cursor-pointer items-start justify-start whitespace-normal text-left leading-tight rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-slate-700 shadow-sm transition hover:border-amber-300 hover:text-amber-700 data-[state=active]:border-amber-500 data-[state=active]:bg-amber-50 data-[state=active]:text-amber-700 data-[state=active]:shadow"
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

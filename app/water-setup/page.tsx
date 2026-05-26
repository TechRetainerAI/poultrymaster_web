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
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Settings, Plus, Pencil, Trash2, Loader2, AlertCircle,
  ShoppingBag, Users, Truck, Route as RouteIcon, Cog, Droplets, Box, Users2,
} from "lucide-react"
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
  addHref: string
  columns: Column<T>[]
}

function SetupSection<T>({ tab }: { tab: SetupTab<T> }) {
  const { toast } = useToast()
  const [items, setItems] = useState<T[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<T | null>(null)

  async function load() {
    setLoading(true); setError(null)
    try { setItems(await tab.fetch()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
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
        <div className="flex items-center justify-between gap-2 px-4 py-3 border-b">
          <div className="flex items-center gap-2 text-slate-700">
            <tab.icon className="h-5 w-5 text-sky-600" />
            <span className="font-semibold">{tab.label}</span>
            {!loading && <Badge variant="secondary" className="ml-1">{items.length}</Badge>}
          </div>
          <div className="flex items-center gap-2">
            <Button asChild size="sm" variant="outline">
              <Link href={tab.addHref}><Pencil className="h-4 w-4 mr-1" /> Open full page</Link>
            </Button>
            <Button asChild size="sm">
              <Link href={tab.addHref}><Plus className="h-4 w-4 mr-1" /> Add {tab.label.toLowerCase()}</Link>
            </Button>
          </div>
        </div>
        {loading ? (
          <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : error ? (
          <div className="p-4 text-rose-700 flex items-center gap-2 bg-rose-50"><AlertCircle className="h-4 w-4" /> {error}</div>
        ) : items.length === 0 ? (
          <div className="p-8 text-center text-slate-500">
            No {tab.label.toLowerCase()} yet. Click <span className="font-medium">Add {tab.label.toLowerCase()}</span> above to create your first one.
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                {tab.columns.map((c) => <TableHead key={c.header}>{c.header}</TableHead>)}
                {tab.delete && <TableHead className="text-right">Actions</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((item) => (
                <TableRow key={tab.idOf(item)}>
                  {tab.columns.map((c) => <TableCell key={c.header}>{c.accessor(item)}</TableCell>)}
                  {tab.delete && (
                    <TableCell className="text-right">
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-rose-600 hover:bg-rose-50"
                        onClick={() => setDeleteTarget(item)}
                        title={`Delete ${tab.label.toLowerCase()}`}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
        title={`Delete ${tab.label.toLowerCase()}?`}
        description={deleteTarget ? `${tab.labelOf(deleteTarget)} will be permanently removed. Records that reference it may stop resolving.` : ""}
        onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
      />
    </Card>
  )
}

const fmtGhc = (n?: number | null) => `GHC ${(n ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

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
  },
  {
    key: "raw-materials",
    label: "Raw materials",
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

          <Tabs defaultValue={tabs[0].key} className="w-full">
            <TabsList className="flex flex-wrap h-auto gap-1 bg-slate-100 p-1">
              {tabs.map((t) => (
                <TabsTrigger key={t.key} value={t.key} className="data-[state=active]:bg-white">
                  <t.icon className="h-4 w-4 mr-1.5" />
                  {t.label}
                </TabsTrigger>
              ))}
            </TabsList>
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

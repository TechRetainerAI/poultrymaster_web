"use client"

/**
 * Inline create/edit modals for the Water Company Setup tabs (Prompt 2 §13).
 *
 * Each modal:
 *   - is controlled (`open` + `onOpenChange`)
 *   - accepts an optional `item` to enter edit mode (no item → add mode)
 *   - calls `onSaved()` after a successful API write so the parent can refresh
 *
 * The forms are intentionally minimal (the existing full pages keep the rich
 * versions — these cover the common fields operators need at setup time).
 */

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Save } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  // Products
  createWaterProduct, updateWaterProduct,
  // Customers
  createWaterCustomer, updateWaterCustomer,
  // Drivers
  createWaterDriver, updateWaterDriver,
  // Vehicles
  createWaterVehicle, updateWaterVehicle,
  // Routes
  createWaterRoute, updateWaterRoute,
  // Machines
  createWaterMachine, updateWaterMachine,
  // Boreholes
  createWaterBorehole, updateWaterBorehole,
  // Raw materials
  createWaterRawMaterialItem, updateWaterRawMaterialItem,
  // Staff
  createWaterStaff, updateWaterStaff,
  // Lookups for dropdowns
  listWaterVehicles,
  type WaterProduct, type WaterCustomer, type WaterDriver, type WaterVehicle,
  type WaterRoute, type WaterMachine, type WaterBorehole, type WaterRawMaterialItem,
  type WaterStaff,
} from "@/lib/api/water"

type BaseModalProps<T> = {
  open: boolean
  item: T | null
  onOpenChange: (open: boolean) => void
  onSaved: () => void
}

// =============================================================================
// Products
// =============================================================================
export function ProductModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterProduct>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({
    name: "", sku: "", sizeMl: 0, unit: "bag", unitPrice: 0,
    isActive: true, productType: "FinishedGood" as any, notes: "",
  })
  useEffect(() => {
    if (open) setForm(item ? {
      name: item.name ?? "",
      sku: item.sku ?? "",
      sizeMl: item.sizeMl ?? 0,
      unit: item.unit ?? "bag",
      unitPrice: item.unitPrice ?? 0,
      isActive: item.isActive,
      productType: item.productType ?? "FinishedGood",
      notes: item.notes ?? "",
    } : { name: "", sku: "", sizeMl: 0, unit: "bag", unitPrice: 0, isActive: true, productType: "FinishedGood", notes: "" })
  }, [open, item])

  async function save() {
    if (!form.name.trim()) return toast({ title: "Name is required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = {
        name: form.name.trim(),
        sku: form.sku || null,
        sizeMl: form.sizeMl || null,
        unit: form.unit || null,
        unitPrice: form.unitPrice,
        isActive: form.isActive,
        productType: form.productType,
        notes: form.notes || null,
      }
      if (item) await updateWaterProduct(item.waterProductId, payload)
      else      await createWaterProduct(payload)
      toast({ title: item ? "Product updated" : "Product added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit product" : "New product"}</DialogTitle>
          <DialogDescription>Finished good or raw material the company makes/sells.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Basics" color="indigo">
            <FormField label="Name *" full>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </FormField>
            <FormField label="SKU"><Input value={form.sku} onChange={(e) => setForm({ ...form, sku: e.target.value })} /></FormField>
            <FormField label="Size (mL)">
              <Input type="number" min={0} value={form.sizeMl} onChange={(e) => setForm({ ...form, sizeMl: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Unit"><Input value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })} /></FormField>
            <FormField label="Unit price">
              <Input type="number" min={0} step="0.01" value={form.unitPrice} onChange={(e) => setForm({ ...form, unitPrice: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Type">
              <Select value={form.productType} onValueChange={(v) => setForm({ ...form, productType: v as any })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="FinishedGood">Finished good</SelectItem>
                  <SelectItem value="RawMaterial">Raw material</SelectItem>
                  <SelectItem value="PackagingMaterial">Packaging material</SelectItem>
                  <SelectItem value="Other">Other</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Active" full>
              <div className="flex items-center justify-between rounded border p-2">
                <span className="text-sm text-slate-700">Active product</span>
                <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
              </div>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add product"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Customers
// =============================================================================
export function CustomerModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterCustomer>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({ name: "", contactPhone: "", contactEmail: "", address: "", city: "", notes: "" })
  useEffect(() => {
    if (open) setForm(item ? {
      name: item.name ?? "",
      contactPhone: item.contactPhone ?? "",
      contactEmail: item.contactEmail ?? "",
      address: item.address ?? "",
      city: item.city ?? "",
      notes: item.notes ?? "",
    } : { name: "", contactPhone: "", contactEmail: "", address: "", city: "", notes: "" })
  }, [open, item])

  async function save() {
    if (!form.name.trim()) return toast({ title: "Name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = { ...form, contactPhone: form.contactPhone || null, contactEmail: form.contactEmail || null, address: form.address || null, city: form.city || null, notes: form.notes || null }
      if (item) await updateWaterCustomer(item.waterCustomerId, payload)
      else      await createWaterCustomer(payload)
      toast({ title: item ? "Customer updated" : "Customer added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit customer" : "New customer"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Contact" color="indigo">
            <FormField label="Name *" full><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></FormField>
            <FormField label="Phone"><Input value={form.contactPhone} onChange={(e) => setForm({ ...form, contactPhone: e.target.value })} /></FormField>
            <FormField label="Email"><Input type="email" value={form.contactEmail} onChange={(e) => setForm({ ...form, contactEmail: e.target.value })} /></FormField>
            <FormField label="City"><Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} /></FormField>
            <FormField label="Address"><Input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} /></FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add customer"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Drivers
// =============================================================================
export function DriverModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterDriver>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [form, setForm] = useState({
    driverName: "", phoneNumber: "", licenseNumber: "",
    defaultVehicleId: null as number | null, isActive: true, notes: "",
  })

  useEffect(() => {
    if (open) {
      void listWaterVehicles().then(setVehicles).catch(() => setVehicles([]))
      setForm(item ? {
        driverName: item.driverName ?? "",
        phoneNumber: item.phoneNumber ?? "",
        licenseNumber: item.licenseNumber ?? "",
        defaultVehicleId: item.defaultVehicleId ?? null,
        isActive: item.isActive,
        notes: item.notes ?? "",
      } : { driverName: "", phoneNumber: "", licenseNumber: "", defaultVehicleId: null, isActive: true, notes: "" })
    }
  }, [open, item])

  async function save() {
    if (!form.driverName.trim()) return toast({ title: "Driver name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = { ...form, phoneNumber: form.phoneNumber || null, licenseNumber: form.licenseNumber || null, notes: form.notes || null }
      if (item) await updateWaterDriver(item.waterDriverId, payload)
      else      await createWaterDriver(payload)
      toast({ title: item ? "Driver updated" : "Driver added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit driver" : "New driver"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Identity" color="indigo">
            <FormField label="Driver name *" full><Input value={form.driverName} onChange={(e) => setForm({ ...form, driverName: e.target.value })} /></FormField>
            <FormField label="Phone"><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></FormField>
            <FormField label="License #"><Input value={form.licenseNumber} onChange={(e) => setForm({ ...form, licenseNumber: e.target.value })} /></FormField>
          </FormSection>
          <FormSection title="Assignment" color="blue">
            <FormField label="Assigned vehicle" full>
              <Select value={String(form.defaultVehicleId ?? "")} onValueChange={(v) => setForm({ ...form, defaultVehicleId: v ? Number(v) : null })}>
                <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                <SelectContent>
                  {vehicles.map((v) => (
                    <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Active" full>
              <div className="flex items-center justify-between rounded border p-2">
                <span className="text-sm text-slate-700">Active driver</span>
                <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
              </div>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add driver"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Vehicles
// =============================================================================
export function VehicleModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterVehicle>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({
    vehicleName: "", vehicleType: "Truck", registrationNumber: "",
    capacityBags: 0, fuelType: "", status: "Active" as any, notes: "",
  })
  useEffect(() => {
    if (open) setForm(item ? {
      vehicleName: item.vehicleName ?? "",
      vehicleType: item.vehicleType ?? "Truck",
      registrationNumber: item.registrationNumber ?? "",
      capacityBags: item.capacityBags ?? 0,
      fuelType: item.fuelType ?? "",
      status: item.status,
      notes: item.notes ?? "",
    } : { vehicleName: "", vehicleType: "Truck", registrationNumber: "", capacityBags: 0, fuelType: "", status: "Active", notes: "" })
  }, [open, item])

  async function save() {
    if (!form.vehicleName.trim()) return toast({ title: "Vehicle name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = { ...form, registrationNumber: form.registrationNumber || null, fuelType: form.fuelType || null, capacityBags: form.capacityBags || null, notes: form.notes || null }
      if (item) await updateWaterVehicle(item.waterVehicleId, payload as any)
      else      await createWaterVehicle(payload as any)
      toast({ title: item ? "Vehicle updated" : "Vehicle added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit vehicle" : "New vehicle"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Vehicle" color="indigo">
            <FormField label="Name *" full><Input value={form.vehicleName} onChange={(e) => setForm({ ...form, vehicleName: e.target.value })} /></FormField>
            <FormField label="Type">
              <Select value={form.vehicleType} onValueChange={(v) => setForm({ ...form, vehicleType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Truck">Truck</SelectItem>
                  <SelectItem value="Pickup">Pickup</SelectItem>
                  <SelectItem value="MotorKing">Motor King</SelectItem>
                  <SelectItem value="Van">Van</SelectItem>
                  <SelectItem value="Other">Other</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Registration #"><Input value={form.registrationNumber} onChange={(e) => setForm({ ...form, registrationNumber: e.target.value })} /></FormField>
            <FormField label="Capacity (bags)">
              <Input type="number" min={0} value={form.capacityBags} onChange={(e) => setForm({ ...form, capacityBags: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Fuel type"><Input value={form.fuelType} onChange={(e) => setForm({ ...form, fuelType: e.target.value })} /></FormField>
            <FormField label="Status">
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v as any })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Active">Active</SelectItem>
                  <SelectItem value="Inactive">Inactive</SelectItem>
                  <SelectItem value="UnderMaintenance">Under maintenance</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add vehicle"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Routes
// =============================================================================
export function RouteModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterRoute>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [vehicles, setVehicles] = useState<WaterVehicle[]>([])
  const [form, setForm] = useState({
    routeName: "", areaCovered: "", defaultDriverStaffId: null as number | null,
    defaultVehicleId: null as number | null, expectedCustomers: 0, expectedBagsSold: 0, notes: "",
  })

  useEffect(() => {
    if (open) {
      void listWaterVehicles().then(setVehicles).catch(() => setVehicles([]))
      setForm(item ? {
        routeName: item.routeName ?? "",
        areaCovered: item.areaCovered ?? "",
        defaultDriverStaffId: item.defaultDriverStaffId ?? null,
        defaultVehicleId: item.defaultVehicleId ?? null,
        expectedCustomers: item.expectedCustomers ?? 0,
        expectedBagsSold: item.expectedBagsSold ?? 0,
        notes: item.notes ?? "",
      } : { routeName: "", areaCovered: "", defaultDriverStaffId: null, defaultVehicleId: null, expectedCustomers: 0, expectedBagsSold: 0, notes: "" })
    }
  }, [open, item])

  async function save() {
    if (!form.routeName.trim()) return toast({ title: "Route name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = { ...form, areaCovered: form.areaCovered || null, expectedCustomers: form.expectedCustomers || null, expectedBagsSold: form.expectedBagsSold || null, notes: form.notes || null }
      if (item) await updateWaterRoute(item.waterRouteId, payload)
      else      await createWaterRoute(payload)
      toast({ title: item ? "Route updated" : "Route added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit route" : "New route"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Route" color="indigo">
            <FormField label="Name *" full><Input value={form.routeName} onChange={(e) => setForm({ ...form, routeName: e.target.value })} /></FormField>
            <FormField label="Area covered" full><Input value={form.areaCovered} onChange={(e) => setForm({ ...form, areaCovered: e.target.value })} /></FormField>
            <FormField label="Default vehicle" full>
              <Select value={String(form.defaultVehicleId ?? "")} onValueChange={(v) => setForm({ ...form, defaultVehicleId: v ? Number(v) : null })}>
                <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                <SelectContent>
                  {vehicles.map((v) => (
                    <SelectItem key={v.waterVehicleId} value={String(v.waterVehicleId)}>{v.vehicleName}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Expected customers">
              <Input type="number" min={0} value={form.expectedCustomers} onChange={(e) => setForm({ ...form, expectedCustomers: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Expected bags">
              <Input type="number" min={0} value={form.expectedBagsSold} onChange={(e) => setForm({ ...form, expectedBagsSold: Number(e.target.value) || 0 })} />
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add route"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Machines
// =============================================================================
export function MachineModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterMachine>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({
    machineName: "", machineNumber: "", machineType: "SachetMachine",
    manufacturer: "", capacityPerHour: 0, status: "Active" as any, notes: "",
  })
  useEffect(() => {
    if (open) setForm(item ? {
      machineName: item.machineName ?? "",
      machineNumber: item.machineNumber ?? "",
      machineType: item.machineType ?? "SachetMachine",
      manufacturer: item.manufacturer ?? "",
      capacityPerHour: item.capacityPerHour ?? 0,
      status: item.status,
      notes: item.notes ?? "",
    } : { machineName: "", machineNumber: "", machineType: "SachetMachine", manufacturer: "", capacityPerHour: 0, status: "Active", notes: "" })
  }, [open, item])

  async function save() {
    if (!form.machineName.trim()) return toast({ title: "Machine name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = { ...form, machineNumber: form.machineNumber || null, manufacturer: form.manufacturer || null, capacityPerHour: form.capacityPerHour || null, notes: form.notes || null }
      if (item) await updateWaterMachine(item.waterMachineId, payload as any)
      else      await createWaterMachine(payload as any)
      toast({ title: item ? "Machine updated" : "Machine added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit machine" : "New machine"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Machine" color="indigo">
            <FormField label="Name *" full><Input value={form.machineName} onChange={(e) => setForm({ ...form, machineName: e.target.value })} /></FormField>
            <FormField label="Machine #"><Input value={form.machineNumber} onChange={(e) => setForm({ ...form, machineNumber: e.target.value })} /></FormField>
            <FormField label="Type">
              <Select value={form.machineType} onValueChange={(v) => setForm({ ...form, machineType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="SachetMachine">Sachet machine</SelectItem>
                  <SelectItem value="BottleMachine">Bottle machine</SelectItem>
                  <SelectItem value="DispenserFiller">Dispenser filler</SelectItem>
                  <SelectItem value="Other">Other</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Manufacturer"><Input value={form.manufacturer} onChange={(e) => setForm({ ...form, manufacturer: e.target.value })} /></FormField>
            <FormField label="Capacity / hour">
              <Input type="number" min={0} value={form.capacityPerHour} onChange={(e) => setForm({ ...form, capacityPerHour: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Status">
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v as any })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Active">Active</SelectItem>
                  <SelectItem value="Inactive">Inactive</SelectItem>
                  <SelectItem value="UnderMaintenance">Under maintenance</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add machine"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Boreholes
// =============================================================================
export function BoreholeModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterBorehole>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({
    boreholeName: "", location: "", pumpType: "", pumpCapacity: "",
    tankCapacity: "", waterTreatmentMethod: "", filtrationSystem: "",
    uvSterilizationAvailable: false, status: "Active" as any, notes: "",
  })
  useEffect(() => {
    if (open) setForm(item ? {
      boreholeName: item.boreholeName ?? "",
      location: item.location ?? "",
      pumpType: item.pumpType ?? "",
      pumpCapacity: item.pumpCapacity ?? "",
      tankCapacity: item.tankCapacity ?? "",
      waterTreatmentMethod: item.waterTreatmentMethod ?? "",
      filtrationSystem: item.filtrationSystem ?? "",
      uvSterilizationAvailable: item.uvSterilizationAvailable ?? false,
      status: item.status,
      notes: item.notes ?? "",
    } : { boreholeName: "", location: "", pumpType: "", pumpCapacity: "", tankCapacity: "", waterTreatmentMethod: "", filtrationSystem: "", uvSterilizationAvailable: false, status: "Active", notes: "" })
  }, [open, item])

  async function save() {
    if (!form.boreholeName.trim()) return toast({ title: "Borehole name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = {
        ...form,
        location: form.location || null,
        pumpType: form.pumpType || null,
        pumpCapacity: form.pumpCapacity || null,
        tankCapacity: form.tankCapacity || null,
        waterTreatmentMethod: form.waterTreatmentMethod || null,
        filtrationSystem: form.filtrationSystem || null,
        notes: form.notes || null,
      }
      if (item) await updateWaterBorehole(item.waterBoreholeId, payload as any)
      else      await createWaterBorehole(payload as any)
      toast({ title: item ? "Borehole updated" : "Borehole added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit borehole" : "New borehole"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Borehole" color="indigo">
            <FormField label="Name *" full><Input value={form.boreholeName} onChange={(e) => setForm({ ...form, boreholeName: e.target.value })} /></FormField>
            <FormField label="Location" full><Input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} /></FormField>
            <FormField label="Pump type"><Input value={form.pumpType} onChange={(e) => setForm({ ...form, pumpType: e.target.value })} /></FormField>
            <FormField label="Pump capacity"><Input placeholder="e.g. 5000 L/hr" value={form.pumpCapacity} onChange={(e) => setForm({ ...form, pumpCapacity: e.target.value })} /></FormField>
            <FormField label="Tank capacity"><Input placeholder="e.g. 10000 L" value={form.tankCapacity} onChange={(e) => setForm({ ...form, tankCapacity: e.target.value })} /></FormField>
            <FormField label="Treatment method"><Input value={form.waterTreatmentMethod} onChange={(e) => setForm({ ...form, waterTreatmentMethod: e.target.value })} /></FormField>
            <FormField label="Filtration system"><Input value={form.filtrationSystem} onChange={(e) => setForm({ ...form, filtrationSystem: e.target.value })} /></FormField>
            <FormField label="UV sterilization?" full>
              <div className="flex items-center justify-between rounded border p-2">
                <span className="text-sm text-slate-700">Has UV sterilization</span>
                <Switch checked={form.uvSterilizationAvailable} onCheckedChange={(v) => setForm({ ...form, uvSterilizationAvailable: v })} />
              </div>
            </FormField>
            <FormField label="Status">
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v as any })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Active">Active</SelectItem>
                  <SelectItem value="Inactive">Inactive</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add borehole"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Raw materials
// =============================================================================
export function RawMaterialModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterRawMaterialItem>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({
    itemName: "", category: "Packaging", unitOfMeasure: "rolls",
    minimumStockAlert: 0, isActive: true, notes: "",
  })
  useEffect(() => {
    if (open) setForm(item ? {
      itemName: item.itemName ?? "",
      category: item.category ?? "Packaging",
      unitOfMeasure: item.unitOfMeasure ?? "rolls",
      minimumStockAlert: item.minimumStockAlert ?? 0,
      isActive: item.isActive,
      notes: item.notes ?? "",
    } : { itemName: "", category: "Packaging", unitOfMeasure: "rolls", minimumStockAlert: 0, isActive: true, notes: "" })
  }, [open, item])

  async function save() {
    if (!form.itemName.trim()) return toast({ title: "Item name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = {
        ...form,
        unitOfMeasure: form.unitOfMeasure || null,
        minimumStockAlert: form.minimumStockAlert || null,
        notes: form.notes || null,
      }
      if (item) await updateWaterRawMaterialItem(item.waterRawMaterialItemId, payload as any)
      else      await createWaterRawMaterialItem(payload as any)
      toast({ title: item ? "Material updated" : "Material added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit raw material" : "New raw material"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Material" color="indigo">
            <FormField label="Name *" full><Input value={form.itemName} onChange={(e) => setForm({ ...form, itemName: e.target.value })} /></FormField>
            <FormField label="Category">
              <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Packaging">Packaging</SelectItem>
                  <SelectItem value="Chemical">Chemical</SelectItem>
                  <SelectItem value="Bottle">Bottle</SelectItem>
                  <SelectItem value="Cap">Cap</SelectItem>
                  <SelectItem value="Label">Label</SelectItem>
                  <SelectItem value="Other">Other</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Unit of measure"><Input value={form.unitOfMeasure} onChange={(e) => setForm({ ...form, unitOfMeasure: e.target.value })} /></FormField>
            <FormField label="Min stock alert">
              <Input type="number" min={0} value={form.minimumStockAlert} onChange={(e) => setForm({ ...form, minimumStockAlert: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Active" full>
              <div className="flex items-center justify-between rounded border p-2">
                <span className="text-sm text-slate-700">Active material</span>
                <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
              </div>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add material"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// =============================================================================
// Staff
// =============================================================================
export function StaffModal({ open, item, onOpenChange, onSaved }: BaseModalProps<WaterStaff>) {
  const { toast } = useToast()
  const [busy, setBusy] = useState(false)
  const [form, setForm] = useState({
    firstName: "", lastName: "", phoneNumber: "", email: "",
    role: "Operator", salaryType: "Monthly", basePay: 0, commissionRate: 0,
    isActive: true, notes: "",
  })
  useEffect(() => {
    if (open) setForm(item ? {
      firstName: item.firstName ?? "",
      lastName: item.lastName ?? "",
      phoneNumber: item.phoneNumber ?? "",
      email: item.email ?? "",
      role: item.role ?? "Operator",
      salaryType: item.salaryType ?? "Monthly",
      basePay: item.basePay ?? 0,
      commissionRate: item.commissionRate ?? 0,
      isActive: item.isActive,
      notes: item.notes ?? "",
    } : { firstName: "", lastName: "", phoneNumber: "", email: "", role: "Operator", salaryType: "Monthly", basePay: 0, commissionRate: 0, isActive: true, notes: "" })
  }, [open, item])

  async function save() {
    if (!form.firstName.trim() || !form.lastName.trim()) return toast({ title: "First + last name required", variant: "destructive" })
    setBusy(true)
    try {
      const payload = {
        ...form,
        phoneNumber: form.phoneNumber || null,
        email: form.email || null,
        commissionRate: form.commissionRate || null,
        notes: form.notes || null,
      }
      if (item) await updateWaterStaff(item.waterStaffId, payload as any)
      else      await createWaterStaff(payload as any)
      toast({ title: item ? "Staff updated" : "Staff added" })
      onOpenChange(false); onSaved()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? "Edit staff" : "New staff"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <FormSection title="Identity" color="indigo">
            <FormField label="First name *"><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></FormField>
            <FormField label="Last name *"><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></FormField>
            <FormField label="Phone"><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></FormField>
            <FormField label="Email"><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></FormField>
            <FormField label="Role">
              <Select value={form.role} onValueChange={(v) => setForm({ ...form, role: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Operator">Operator</SelectItem>
                  <SelectItem value="Driver">Driver</SelectItem>
                  <SelectItem value="Sales">Sales</SelectItem>
                  <SelectItem value="Manager">Manager</SelectItem>
                  <SelectItem value="Cashier">Cashier</SelectItem>
                  <SelectItem value="Other">Other</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Compensation" color="blue">
            <FormField label="Salary type">
              <Select value={form.salaryType} onValueChange={(v) => setForm({ ...form, salaryType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Monthly">Monthly</SelectItem>
                  <SelectItem value="Daily">Daily</SelectItem>
                  <SelectItem value="Commission">Commission</SelectItem>
                  <SelectItem value="Mixed">Mixed</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Base pay">
              <Input type="number" min={0} step="0.01" value={form.basePay} onChange={(e) => setForm({ ...form, basePay: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Commission rate (%)">
              <Input type="number" min={0} step="0.01" value={form.commissionRate} onChange={(e) => setForm({ ...form, commissionRate: Number(e.target.value) || 0 })} />
            </FormField>
            <FormField label="Active" full>
              <div className="flex items-center justify-between rounded border p-2">
                <span className="text-sm text-slate-700">Active staff</span>
                <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
              </div>
            </FormField>
          </FormSection>
          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={save} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : <><Save className="h-4 w-4 mr-1" /> {item ? "Save changes" : "Add staff"}</>}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

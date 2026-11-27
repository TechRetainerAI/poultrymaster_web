"use client"

import { useEffect, useMemo, useState, useCallback } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Plus, Pencil, Trash2, Eye, Archive, Power, PowerOff } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  getServices, createService, updateService, deleteService,
  archiveService, activateService, deactivateService, serviceHasPostedSales,
  getServiceCategories, createServiceCategory,
  type GenericService, type GenericServiceInput, type GenericServiceCategory,
} from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { ListFilters } from "@/components/ui/list-filters"

// =============================================================================
// Constants
// =============================================================================

const PRICING_UNITS = [
  "Per Job", "Per Hour", "Per Day", "Per Week", "Per Month",
  "Per Unit", "Per Session", "Per Visit", "Custom",
]

const EMPTY_FORM = {
  serviceName: "",
  serviceCode: "",
  description: "",
  pricingUnit: "Per Job",
  defaultPrice: "",
  estimatedCost: "",
  durationMinutes: "",
  genericServiceCategoryId: "",
  isActive: true,
  notes: "",
}

// =============================================================================
// Helpers
// =============================================================================

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

// =============================================================================
// Component
// =============================================================================

export function GenericServicesTab({ newRequest = 0, onNewHandled, hideNewButton = false }: {
  /** Bumped by the page's "New service" button: open the new-service form once. */
  newRequest?: number
  onNewHandled?: () => void
  /** The page shows its own "New service" button beside "New item". */
  hideNewButton?: boolean
} = {}) {
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericService[]>([])
  const [search, setSearch] = useState("")
  const [loading, setLoading] = useState(true)
  const [filterCategory, setFilterCategory] = useState("")
  const [filterStatus, setFilterStatus] = useState<"all" | "active" | "inactive">("all")

  // Dialog state
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<GenericService | null>(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [categories, setCategories] = useState<GenericServiceCategory[]>([])
  const [newCategoryName, setNewCategoryName] = useState("")

  // Detail panel
  const [detailItem, setDetailItem] = useState<GenericService | null>(null)

  // =========================================================================
  // Load
  // =========================================================================

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [svcs, cats] = await Promise.all([getServices(), getServiceCategories()])
      setRows(svcs)
      setCategories(cats)
    } catch (e: any) {
      toast({ title: "Failed to load services", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }, [toast])

  useEffect(() => { load() }, [load])

  // =========================================================================
  // Filtered rows
  // =========================================================================

  const filtered = useMemo(() => {
    let list = rows
    if (filterStatus === "active") list = list.filter((s) => s.isActive)
    if (filterStatus === "inactive") list = list.filter((s) => !s.isActive)
    if (filterCategory) list = list.filter((s) => String(s.genericServiceCategoryId) === filterCategory)
    if (search.trim()) {
      const q = search.toLowerCase()
      list = list.filter((s) =>
        s.serviceName.toLowerCase().includes(q) ||
        (s.serviceCode?.toLowerCase().includes(q)) ||
        (s.categoryName?.toLowerCase().includes(q)) ||
        (s.description?.toLowerCase().includes(q))
      )
    }
    return list
  }, [rows, search, filterCategory, filterStatus])

  // =========================================================================
  // Form helpers
  // =========================================================================

  const openNew = () => {
    setEditingId(null)
    setForm(EMPTY_FORM)
    setOpen(true)
  }

  // The page asked for a new service (possibly from the Physical Items tab).
  useEffect(() => {
    if (newRequest > 0) { openNew(); onNewHandled?.() }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [newRequest])

  const openEdit = (s: GenericService) => {
    setEditingId(s.genericServiceId)
    setForm({
      serviceName: s.serviceName,
      serviceCode: s.serviceCode || "",
      description: s.description || "",
      pricingUnit: s.pricingUnit || "Per Job",
      defaultPrice: s.defaultPrice != null ? String(s.defaultPrice) : "",
      estimatedCost: s.estimatedCost != null ? String(s.estimatedCost) : "",
      durationMinutes: s.durationMinutes != null ? String(s.durationMinutes) : "",
      genericServiceCategoryId: s.genericServiceCategoryId ? String(s.genericServiceCategoryId) : "",
      isActive: s.isActive,
      notes: s.notes || "",
    })
    setOpen(true)
  }

  const handleSave = async () => {
    if (!form.serviceName.trim()) {
      toast({ title: "Service name is required", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const input: GenericServiceInput = {
        serviceName: form.serviceName.trim(),
        serviceCode: form.serviceCode.trim() || null,
        description: form.description.trim() || null,
        pricingUnit: form.pricingUnit || "Per Job",
        defaultPrice: form.defaultPrice ? parseFloat(form.defaultPrice) : 0,
        estimatedCost: form.estimatedCost ? parseFloat(form.estimatedCost) : null,
        durationMinutes: form.durationMinutes ? parseInt(form.durationMinutes) : null,
        genericServiceCategoryId: form.genericServiceCategoryId ? parseInt(form.genericServiceCategoryId) : null,
        isActive: form.isActive,
        notes: form.notes.trim() || null,
      }
      if (editingId != null) {
        await updateService(editingId, input)
        toast({ title: "Service updated" })
      } else {
        await createService(input)
        toast({ title: "Service created" })
      }
      setOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Could not save service", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const handleDelete = async () => {
    if (!deleteTarget) return
    try {
      await deleteService(deleteTarget.genericServiceId)
      toast({ title: "Service deleted" })
      setDeleteTarget(null)
      await load()
    } catch (e: any) {
      toast({ title: "Cannot delete service", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const handleToggleActive = async (s: GenericService) => {
    try {
      if (s.isActive) {
        await deactivateService(s.genericServiceId)
        toast({ title: `"${s.serviceName}" deactivated` })
      } else {
        await activateService(s.genericServiceId)
        toast({ title: `"${s.serviceName}" activated` })
      }
      await load()
    } catch (e: any) {
      toast({ title: "Could not update service status", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const handleArchive = async (s: GenericService) => {
    try {
      await archiveService(s.genericServiceId)
      toast({ title: `"${s.serviceName}" archived` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not archive service", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const handleAddCategory = async () => {
    if (!newCategoryName.trim()) return
    try {
      await createServiceCategory({ name: newCategoryName.trim() })
      setNewCategoryName("")
      const cats = await getServiceCategories()
      setCategories(cats)
      toast({ title: "Category created" })
    } catch (e: any) {
      toast({ title: "Could not create category", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const confirmDelete = async (s: GenericService) => {
    try {
      const hasSales = await serviceHasPostedSales(s.genericServiceId)
      if (hasSales) {
        toast({
          title: "Cannot delete",
          description: `"${s.serviceName}" has posted sales. Use deactivation or archival instead.`,
          variant: "destructive",
        })
        return
      }
      setDeleteTarget(s)
    } catch {
      setDeleteTarget(s)
    }
  }

  // =========================================================================
  // Render
  // =========================================================================

  if (loading) {
    return (
      <div className="flex justify-center items-center py-16">
        <Loader2 className="h-8 w-8 animate-spin text-blue-600" />
      </div>
    )
  }

  return (
    <>
      {/* Header button + Filters */}
      {rows.length > 0 && !hideNewButton && (
        <div className="flex justify-end mb-3">
          <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New Service</Button>
        </div>
      )}
      {rows.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-4">
          <div className="flex-1 min-w-[200px] max-w-md">
            <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search services by name, code or category" />
          </div>
          {categories.length > 0 && (
            <Select value={filterCategory || "__all__"} onValueChange={(v) => setFilterCategory(v === "__all__" ? "" : v)}>
              <SelectTrigger className="w-auto min-w-[160px] h-10">
                <SelectValue placeholder="All categories" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="__all__">All categories</SelectItem>
                {categories.filter((c) => c.isActive).map((c) => (
                  <SelectItem key={c.genericServiceCategoryId} value={String(c.genericServiceCategoryId)}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          <Select value={filterStatus} onValueChange={(v) => setFilterStatus(v as typeof filterStatus)}>
            <SelectTrigger className="w-auto min-w-[120px] h-10">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All statuses</SelectItem>
              <SelectItem value="active">Active</SelectItem>
              <SelectItem value="inactive">Inactive</SelectItem>
            </SelectContent>
          </Select>
        </div>
      )}

      {/* Empty state */}
      {rows.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center">
            <p className="text-slate-500 mb-4">No services yet. Create your first service to make it available when recording Sales.</p>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New Service</Button>
          </CardContent>
        </Card>
      ) : filtered.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center">
            <p className="text-slate-500">No services match your filters.</p>
          </CardContent>
        </Card>
      ) : (
        <>
          {/* Desktop table */}
          <Card className="hidden lg:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Service Name</TableHead>
                  <TableHead>Code</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead>Pricing Unit</TableHead>
                  <TableHead className="text-right">Default Price</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((s) => (
                  <TableRow key={s.genericServiceId} className="cursor-pointer hover:bg-slate-50" onClick={() => setDetailItem(s)}>
                    <TableCell>
                      <div className="font-medium">{s.serviceName}</div>
                      {s.description && <div className="text-xs text-slate-400 line-clamp-1">{s.description}</div>}
                    </TableCell>
                    <TableCell className="text-slate-500">{s.serviceCode || "—"}</TableCell>
                    <TableCell className="text-slate-500">{s.categoryName || "—"}</TableCell>
                    <TableCell>{s.pricingUnit}</TableCell>
                    <TableCell className="text-right font-mono">
                      {s.defaultPrice > 0 ? fmt(s.defaultPrice) : <span className="text-slate-400">Variable</span>}
                    </TableCell>
                    <TableCell>
                      <Badge className={s.isActive ? "bg-emerald-100 text-emerald-800" : s.archivedAt ? "bg-slate-100 text-slate-500" : "bg-amber-100 text-amber-800"}>
                        {s.archivedAt ? "Archived" : s.isActive ? "Active" : "Inactive"}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" title="View" onClick={() => setDetailItem(s)}><Eye className="h-4 w-4" /></Button>
                        <Button variant="ghost" size="icon" title="Edit" onClick={() => openEdit(s)}><Pencil className="h-4 w-4" /></Button>
                        <Button variant="ghost" size="icon" title={s.isActive ? "Deactivate" : "Activate"} onClick={() => handleToggleActive(s)}>
                          {s.isActive ? <PowerOff className="h-4 w-4 text-amber-600" /> : <Power className="h-4 w-4 text-emerald-600" />}
                        </Button>
                        {!s.archivedAt && (
                          <Button variant="ghost" size="icon" title="Archive" onClick={() => handleArchive(s)}><Archive className="h-4 w-4 text-slate-500" /></Button>
                        )}
                        <Button variant="ghost" size="icon" title="Delete" onClick={() => confirmDelete(s)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>

          {/* Mobile cards */}
          <div className="lg:hidden space-y-3">
            {filtered.map((s) => (
              <Card key={s.genericServiceId} className="cursor-pointer" onClick={() => setDetailItem(s)}>
                <CardContent className="p-4">
                  <div className="flex justify-between items-start mb-2">
                    <div>
                      <div className="font-medium">{s.serviceName}</div>
                      {s.serviceCode && <div className="text-xs text-slate-400">{s.serviceCode}</div>}
                    </div>
                    <Badge className={s.isActive ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"}>
                      {s.isActive ? "Active" : "Inactive"}
                    </Badge>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-sm text-slate-600">
                    <div><span className="text-slate-400">Unit:</span> {s.pricingUnit}</div>
                    <div className="text-right font-mono">{s.defaultPrice > 0 ? fmt(s.defaultPrice) : "Variable"}</div>
                  </div>
                  <div className="flex justify-end gap-1 mt-2" onClick={(e) => e.stopPropagation()}>
                    <Button variant="ghost" size="sm" onClick={() => openEdit(s)}><Pencil className="h-3 w-3 mr-1" /> Edit</Button>
                    <Button variant="ghost" size="sm" onClick={() => confirmDelete(s)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </>
      )}

      {/* Detail panel (slide-over or inline) */}
      {detailItem && (
        <Dialog open={!!detailItem} onOpenChange={() => setDetailItem(null)}>
          <DialogContent className="max-w-lg">
            <DialogHeader>
              <DialogTitle>{detailItem.serviceName}</DialogTitle>
              <DialogDescription>{detailItem.description || "No description"}</DialogDescription>
            </DialogHeader>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><span className="text-slate-400">Code:</span> {detailItem.serviceCode || "—"}</div>
              <div><span className="text-slate-400">Category:</span> {detailItem.categoryName || "—"}</div>
              <div><span className="text-slate-400">Pricing Unit:</span> {detailItem.pricingUnit}</div>
              <div><span className="text-slate-400">Default Price:</span> {detailItem.defaultPrice > 0 ? fmt(detailItem.defaultPrice) : "Variable"}</div>
              <div><span className="text-slate-400">Status:</span> {detailItem.isActive ? "Active" : detailItem.archivedAt ? "Archived" : "Inactive"}</div>
              {detailItem.estimatedCost != null && <div><span className="text-slate-400">Est. Cost:</span> {fmt(detailItem.estimatedCost)}</div>}
              {detailItem.durationMinutes != null && <div><span className="text-slate-400">Duration:</span> {detailItem.durationMinutes} min</div>}
              {detailItem.notes && <div className="col-span-2"><span className="text-slate-400">Notes:</span> {detailItem.notes}</div>}
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => { setDetailItem(null); openEdit(detailItem) }}>
                <Pencil className="h-4 w-4 mr-1" /> Edit
              </Button>
              <Button variant="outline" onClick={() => setDetailItem(null)}>Close</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}

      {/* Create / Edit dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingId != null ? "Edit Service" : "New Service"}</DialogTitle>
            <DialogDescription>
              {editingId != null ? "Update service details." : "Add a new service to your catalog."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="Basic Information">
              <FormField label="Service Name" hint="Required">
                <Input value={form.serviceName} onChange={(e) => setForm({ ...form, serviceName: e.target.value })} placeholder="e.g. Equipment Installation" />
              </FormField>
              <FormField label="Service Code">
                <Input value={form.serviceCode} onChange={(e) => setForm({ ...form, serviceCode: e.target.value })} placeholder="Optional unique code" />
              </FormField>
              <FormField label="Description">
                <Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="What is included in this service?" rows={2} />
              </FormField>
              <FormField label="Category">
                <div className="flex gap-2">
                  <Select value={form.genericServiceCategoryId || "__none__"} onValueChange={(v) => setForm({ ...form, genericServiceCategoryId: v === "__none__" ? "" : v })}>
                    <SelectTrigger className="flex-1">
                      <SelectValue placeholder="No category" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__none__">No category</SelectItem>
                      {categories.filter((c) => c.isActive).map((c) => (
                        <SelectItem key={c.genericServiceCategoryId} value={String(c.genericServiceCategoryId)}>
                          {c.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex gap-2 mt-2">
                  <Input placeholder="New category name" value={newCategoryName} onChange={(e) => setNewCategoryName(e.target.value)} className="flex-1" />
                  <Button variant="outline" size="sm" onClick={handleAddCategory} disabled={!newCategoryName.trim()}>Add</Button>
                </div>
              </FormField>
            </FormSection>

            <FormSection title="Pricing">
              <FormField label="Pricing Unit" hint="Required">
                <Select value={form.pricingUnit} onValueChange={(v) => setForm({ ...form, pricingUnit: v })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {PRICING_UNITS.map((u) => (
                      <SelectItem key={u} value={u}>{u}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Default Selling Price">
                <NumberInput step="0.01" min="0" value={form.defaultPrice} onChange={(e) => setForm({ ...form, defaultPrice: e.target.value })} placeholder="Leave empty for variable pricing" />
              </FormField>
              <FormField label="Estimated Cost">
                <NumberInput step="0.01" min="0" value={form.estimatedCost} onChange={(e) => setForm({ ...form, estimatedCost: e.target.value })} placeholder="Optional" />
              </FormField>
            </FormSection>

            <FormSection title="Other">
              <FormField label="Duration (minutes)">
                <NumberInput step="1" min="0" value={form.durationMinutes} onChange={(e) => setForm({ ...form, durationMinutes: e.target.value })} placeholder="Optional" />
              </FormField>
              <FormField label="Notes">
                <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} rows={2} />
              </FormField>
              <div className="flex items-center gap-3">
                <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
                <Label>Active</Label>
              </div>
            </FormSection>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={handleSave} disabled={saving}>
              {saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
              {editingId != null ? "Save Changes" : "Create Service"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={() => setDeleteTarget(null)}
        onConfirm={handleDelete}
        title="Delete Service"
        description={`Are you sure you want to delete "${deleteTarget?.serviceName}"? This cannot be undone.`}
      />
    </>
  )
}

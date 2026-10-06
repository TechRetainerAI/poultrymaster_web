"use client"

// Restaurant Suppliers (Setup → Finance → Suppliers). Migration 329.
//
// The Poultry Suppliers page (app/suppliers) for the standalone Restaurant: the
// vendors it buys food ingredients, vegetables, meat, fish, drinks, cooking
// materials, packaging, tableware and cleaning supplies from. Same header, same
// toolbar, same table, same Contact / Address dialog bands and the same words;
// in rose, and with the restaurant supplier's own fields (Category instead of
// City -- restaurantsuppliers has no city column).
//
// Every purchase, supplier payment and capital investment on the Restaurant
// hangs off these rows. A supplier with any of those on record is deactivated
// rather than deleted, and one that is still owed money cannot be removed
// (sprestaurant_supplier_delete, migration 329).

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DataPagination } from "@/components/ui/data-pagination"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Plus, Pencil, Trash2, Mail, Phone, MapPin, Truck, Search, RefreshCw, Loader2, Tag } from "lucide-react"
import { usePagination } from "@/hooks/use-pagination"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { useAuthStore } from "@/lib/store/auth-store"
import { canAccessSuppliersPage } from "@/lib/utils/financial-nav-access"
import { fmtInstant } from "@/lib/utils/company-datetime"
import {
  listSuppliers, createSupplier, updateSupplier, deleteSupplier, SUPPLIER_CATEGORIES,
  type RestaurantSupplierRow, type RestaurantSupplierInput,
} from "@/lib/api/restaurant-suppliers"

const OTHER = "__other__"
const emptyForm: RestaurantSupplierInput = { name: "", phone: "", email: "", address: "", category: "", contactName: "", notes: "" }

// ---------------------------------------------------------------------------
// The two dialog bands (Contact, Address) shared by Add and Edit.
// ---------------------------------------------------------------------------
function SupplierFormFields({
  form, setForm, disabled,
}: {
  form: RestaurantSupplierInput
  setForm: (f: RestaurantSupplierInput) => void
  disabled: boolean
}) {
  const known = (SUPPLIER_CATEGORIES as readonly string[]).includes(form.category ?? "")
  const [typing, setTyping] = useState(!!form.category && !known)
  const selectValue = typing ? OTHER : (form.category || "")
  return (
    <>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-rose-600 px-4 py-2 text-sm font-semibold text-white">Contact</div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Business / name *</Label>
            <Input placeholder="e.g. Makola Fresh Supplies" value={form.name}
                   onChange={(e) => setForm({ ...form, name: e.target.value })} disabled={disabled} />
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Phone *</Label>
            <Input type="tel" placeholder="+233 …" value={form.phone ?? ""}
                   onChange={(e) => setForm({ ...form, phone: e.target.value })} disabled={disabled} />
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Email</Label>
            <Input type="text" placeholder="optional" value={form.email ?? ""}
                   onChange={(e) => setForm({ ...form, email: e.target.value })} disabled={disabled} />
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Category</Label>
            <Select value={selectValue} disabled={disabled}
                    onValueChange={(v) => {
                      if (v === OTHER) { setTyping(true); setForm({ ...form, category: "" }) }
                      else { setTyping(false); setForm({ ...form, category: v }) }
                    }}>
              <SelectTrigger><SelectValue placeholder="What they supply" /></SelectTrigger>
              <SelectContent>
                {SUPPLIER_CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                <SelectItem value={OTHER}>Other</SelectItem>
              </SelectContent>
            </Select>
            {typing && (
              <Input placeholder="Type the category" value={form.category ?? ""}
                     onChange={(e) => setForm({ ...form, category: e.target.value })} disabled={disabled} />
            )}
          </div>
          <div className="space-y-2 md:col-span-2">
            <Label className="text-sm font-medium text-slate-700">Contact person</Label>
            <Input placeholder="optional" value={form.contactName ?? ""}
                   onChange={(e) => setForm({ ...form, contactName: e.target.value })} disabled={disabled} />
          </div>
        </div>
      </div>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Address</div>
        <div className="p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Full address *</Label>
            <Input placeholder="Street, city, region" value={form.address ?? ""}
                   onChange={(e) => setForm({ ...form, address: e.target.value })} disabled={disabled} />
          </div>
        </div>
      </div>
    </>
  )
}

export default function RestaurantSuppliersPage() {
  const router = useRouter()
  const permissions = usePermissions()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [suppliers, setSuppliers] = useState<RestaurantSupplierRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [searchQuery, setSearchQuery] = useState("")
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const handleSort = (key: string) => {
    const r = toggleSort(key, sortKey, sortDir)
    setSortKey(r.key)
    setSortDir(r.direction)
  }

  // One dialog for Add and Edit: editingId null = Add.
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [form, setForm] = useState<RestaurantSupplierInput>(emptyForm)
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState("")

  const [deletingId, setDeletingId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)

  const allowed = canAccessSuppliersPage(permissions.featureAccess, permissions.isAdmin)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!permissions.isLoading && !allowed) router.push("/dashboard")
  }, [activeFarmType, permissions.isLoading, allowed, router])

  const loadSuppliers = async () => {
    try {
      setSuppliers(await listSuppliers())
      setError("")
    } catch (e: any) {
      setError(e?.message || "Failed to load suppliers")
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (permissions.isLoading || !allowed) return
    void loadSuppliers()
  }, [permissions.isLoading, allowed])// eslint-disable-line react-hooks/exhaustive-deps

  const openCreateDialog = () => {
    setEditingId(null); setForm(emptyForm); setFormError(""); setDialogOpen(true)
  }
  const openEditDialog = (s: RestaurantSupplierRow) => {
    setEditingId(s.restaurantsupplierid)
    setForm({
      name: s.name ?? "", phone: s.phone ?? "", email: s.email ?? "", address: s.address ?? "",
      category: s.category ?? "", contactName: s.contactname ?? "", notes: s.notes ?? "",
    })
    setFormError("")
    setDialogOpen(true)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.name.trim() || !(form.phone ?? "").trim() || !(form.address ?? "").trim()) {
      setFormError("Name, phone, and address are required.")
      toastFormGuide(toast, "Add the supplier name, phone, and address — those fields keep purchases and deliveries accurate.")
      return
    }
    setSaving(true)
    setFormError("")
    try {
      const body = { ...form, name: form.name.trim() }
      if (editingId == null) {
        await createSupplier(body)
        toast({ title: "Success!", description: "Supplier created successfully." })
      } else {
        await updateSupplier(editingId, body)
        toast({ title: "Success!", description: "Supplier updated successfully." })
      }
      setDialogOpen(false)
      void loadSuppliers()
    } catch (err: any) {
      setFormError(err?.message ?? "Something went wrong. Please try again.")
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (deletingId == null) return
    setIsDeleting(true)
    try {
      await deleteSupplier(deletingId)
      toast({ title: "Supplier deleted", description: "The supplier has been successfully deleted." })
      void loadSuppliers()
    } catch (err: any) {
      toast({ title: "Delete failed", description: err?.message || "Something went wrong. Please try again.", variant: "destructive" })
    } finally {
      setIsDeleting(false)
      setDeletingId(null)
    }
  }

  const filtered = useMemo(() => {
    const q = searchQuery.trim().toLowerCase()
    if (!q) return suppliers
    return suppliers.filter((s) =>
      [s.name, s.email, s.phone, s.category, s.address].some((v) => (v ?? "").toLowerCase().includes(q)))
  }, [suppliers, searchQuery])
  const sorted = useMemo(() => sortData(filtered, sortKey, sortDir), [filtered, sortKey, sortDir])
  const pg = usePagination(sorted)
  const clearFilters = () => setSearchQuery("")

  const header = (label: string, key: string, className?: string) => (
    <SortableHeader label={label} sortKey={key} currentSort={sortKey} currentDirection={sortDir}
                    onSort={handleSort} className={className ?? "font-semibold text-slate-900"} />
  )

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-rose-100 rounded-lg flex items-center justify-center">
                  <Truck className="w-5 h-5 text-rose-700" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Suppliers</h1>
                  <p className="text-sm text-slate-600">Manage vendors you buy food, drinks and supplies from</p>
                </div>
              </div>
              <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-rose-600 hover:bg-rose-700 shrink-0" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" />
                Add supplier
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {!loading && suppliers.length > 0 && (
              <div className="flex flex-wrap items-center gap-2 p-3 bg-white rounded-lg border">
                <div className="relative flex-1 min-w-[200px]">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search by name, email, phone, category, or address..."
                         value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="pl-9 h-11 sm:h-10" />
                </div>
                {searchQuery && (
                  <Button variant="outline" size="sm" onClick={clearFilters}>
                    <RefreshCw className="h-4 w-4 mr-2" /> Clear
                  </Button>
                )}
              </div>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading suppliers...</p>
                </CardContent>
              </Card>
            ) : filtered.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Search className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No suppliers found</h3>
                  <p className="text-slate-600 mb-6">
                    {searchQuery ? `No suppliers match "${searchQuery}"` : "Get started by adding your first supplier"}
                  </p>
                  {!searchQuery ? (
                    <Button className="gap-2 bg-rose-600 hover:bg-rose-700" onClick={openCreateDialog}>
                      <Plus className="w-4 h-4" /> Add your first supplier
                    </Button>
                  ) : (
                    <Button className="gap-2" variant="outline" onClick={clearFilters}>
                      <RefreshCw className="w-4 h-4" /> Clear search
                    </Button>
                  )}
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  {/* Phones: one card per supplier, actions always visible. */}
                  <div className="md:hidden divide-y">
                    {pg.pageItems.map((s, idx) => (
                      <div key={s.restaurantsupplierid} className={idx % 2 === 0 ? "p-4 bg-rose-50/40" : "p-4 bg-white"}>
                        <div className="font-semibold text-slate-900">{s.name}</div>
                        <div className="mt-1 space-y-0.5 text-sm text-slate-600">
                          {s.phone && <div className="flex items-center gap-2"><Phone className="w-3.5 h-3.5 text-slate-400" />{s.phone}</div>}
                          {s.email && <div className="flex items-center gap-2 truncate"><Mail className="w-3.5 h-3.5 text-slate-400" />{s.email}</div>}
                          {s.category && <div className="flex items-center gap-2"><Tag className="w-3.5 h-3.5 text-slate-400" />{s.category}</div>}
                          {s.address && <div className="flex items-center gap-2"><MapPin className="w-3.5 h-3.5 text-slate-400" />{s.address}</div>}
                        </div>
                        <div className="flex gap-2 pt-3">
                          <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(s)}>
                            <Pencil className="h-4 w-4 mr-2" /> Edit
                          </Button>
                          {permissions.canDelete && (
                            <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50"
                                    onClick={() => setDeletingId(s.restaurantsupplierid)}>
                              <Trash2 className="h-4 w-4 mr-2" /> Delete
                            </Button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="hidden md:block overflow-x-auto">
                    <Table className="w-full min-w-[600px]">
                      <TableHeader>
                        <TableRow className="border-b">
                          {header("Name", "name", "font-semibold text-slate-900 min-w-[120px]")}
                          {header("Email", "email", "font-semibold text-slate-900 min-w-[180px]")}
                          {header("Phone", "phone", "font-semibold text-slate-900 min-w-[140px]")}
                          {header("Category", "category", "font-semibold text-slate-900 min-w-[120px] hidden lg:table-cell")}
                          {header("Address", "address", "font-semibold text-slate-900 min-w-[180px] hidden xl:table-cell")}
                          {header("Date added", "createdat", "font-semibold text-slate-900 min-w-[120px] hidden xl:table-cell")}
                          <TableHead className="font-semibold text-slate-900 text-center min-w-[100px]">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((s) => (
                          <TableRow key={s.restaurantsupplierid} className="hover:bg-slate-50 transition-colors">
                            <TableCell className="font-medium text-slate-900">{s.name}</TableCell>
                            <TableCell className="text-slate-600">
                              <div className="flex items-center gap-2">
                                <Mail className="w-4 h-4 text-slate-400" />
                                <span className="truncate max-w-[200px]">{s.email}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600">
                              <div className="flex items-center gap-2">
                                <Phone className="w-4 h-4 text-slate-400" />
                                <span>{s.phone}</span>
                              </div>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden lg:table-cell">{s.category ?? "—"}</TableCell>
                            <TableCell className="text-slate-600 max-w-[200px] hidden xl:table-cell">
                              <span className="truncate block">{s.address}</span>
                            </TableCell>
                            <TableCell className="text-slate-600 hidden xl:table-cell">
                              {s.createdat ? fmtInstant(s.createdat) : "—"}
                            </TableCell>
                            <TableCell className="text-center whitespace-nowrap">
                              <div className="flex items-center justify-center gap-1 min-w-[90px]">
                                <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-rose-50 hover:text-rose-700"
                                        title="Edit" onClick={() => openEditDialog(s)}>
                                  <Pencil className="w-4 h-4" />
                                </Button>
                                {permissions.canDelete && (
                                  <Button variant="ghost" size="icon" className="h-8 w-8 text-red-600 hover:text-red-700 hover:bg-red-50"
                                          title="Delete" onClick={() => setDeletingId(s.restaurantsupplierid)}>
                                    <Trash2 className="w-4 h-4" />
                                  </Button>
                                )}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                  <div className="p-3 border-t">
                    <DataPagination {...pg.paginationProps} variant="records" />
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editingId == null
                ? <><Truck className="w-5 h-5 text-rose-600" /> Add new supplier</>
                : <><Pencil className="w-5 h-5 text-rose-600" /> Edit supplier</>}
            </DialogTitle>
            <DialogDescription>
              {editingId == null ? "Enter the supplier information below" : "Update the supplier information below"}
            </DialogDescription>
          </DialogHeader>
          {formError && (
            <Alert variant="destructive">
              <AlertDescription>{formError}</AlertDescription>
            </Alert>
          )}
          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Keyed so the Category "Other" box re-reads the row being edited. */}
            <SupplierFormFields key={editingId ?? "new"} form={form} setForm={setForm} disabled={saving} />
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                Cancel
              </Button>
              <Button type="submit" disabled={saving} className="bg-rose-600 hover:bg-rose-700">
                {saving ? (
                  <><Loader2 className="w-4 h-4 mr-2 animate-spin" />{editingId == null ? "Creating…" : "Saving…"}</>
                ) : editingId == null ? (
                  <><Plus className="w-4 h-4 mr-2" />Create supplier</>
                ) : (
                  <><Pencil className="w-4 h-4 mr-2" />Save changes</>
                )}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      <AlertDialog open={deletingId != null} onOpenChange={(o) => { if (!o) setDeletingId(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete supplier</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this supplier? A supplier with purchases, payments or capital investments
              on record is deactivated instead, so its history stays; one that is still owed money cannot be deleted.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} disabled={isDeleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting…</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

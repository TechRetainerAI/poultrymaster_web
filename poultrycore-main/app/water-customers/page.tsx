"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Plus, Pencil, Trash2, Loader2, Users, ShieldCheck, Wand2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterCustomers, createWaterCustomer, updateWaterCustomer, deleteWaterCustomer,
  createWaterDefaultCustomers,
  type WaterCustomer, type WaterCustomerInput,
} from "@/lib/api/water"

const EMPTY: WaterCustomerInput = { name: "", contactPhone: "", contactEmail: "", address: "", city: "", notes: "" }

export default function WaterCustomersPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [customers, setCustomers] = useState<WaterCustomer[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleCustomers = useMemo(
    () => filterByDateAndSearch(customers, {
      search, dateFrom, dateTo,
      searchKeys: ["name", "contactPhone", "contactEmail", "city"],
    }),
    [customers, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleCustomers)

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<WaterCustomerInput>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [seeding, setSeeding] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterCustomer | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") {
      router.replace("/dashboard"); return
    }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setCustomers(await listWaterCustomers()) }
    catch (e: any) { toast({ title: "Could not load customers", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(c: WaterCustomer) {
    setEditId(c.waterCustomerId)
    setForm({ name: c.name, contactPhone: c.contactPhone ?? "", contactEmail: c.contactEmail ?? "", address: c.address ?? "", city: c.city ?? "", notes: c.notes ?? "" })
    setOpen(true)
  }

  async function save() {
    if (!form.name.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterCustomer(editId, form); toast({ title: "Customer updated" }) }
      else        { await createWaterCustomer(form);        toast({ title: "Customer created" }) }
      setOpen(false); setForm(EMPTY); setEditId(null); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(c: WaterCustomer) {
    await deleteWaterCustomer(c.waterCustomerId)
    await load()
  }

  // Migration 082 — idempotently create the 3 system-managed default customers
  // (GeneralSales / GeneralDelivery / GeneralCredit). Safe to re-run; the SP
  // skips rows that already exist.
  async function seedDefaults() {
    setSeeding(true)
    try {
      const rows = await createWaterDefaultCustomers()
      const newOnes = rows.filter((r) => r.wasCreated)
      if (newOnes.length === 0) {
        toast({ title: "All default customers already exist." })
      } else {
        toast({
          title: "Default customers created",
          description: newOnes.map((r) => r.name).join(", "),
        })
      }
      await load()
    } catch (e: any) {
      toast({ title: "Could not create defaults", description: e?.message, variant: "destructive" })
    } finally { setSeeding(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Users className="h-6 w-6 text-sky-600" /> Water customers
            </h1>
            <div className="flex flex-wrap gap-2 w-full sm:w-auto">
              <Button variant="outline" onClick={seedDefaults} disabled={seeding} className="h-11 sm:h-10" title="Idempotently create General Sales / Delivery / Credit defaults.">
                {seeding ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Wand2 className="h-4 w-4 mr-1" />}
                Create default customers
              </Button>
              <Button onClick={openNew} className="h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New customer</Button>
            </div>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search name, phone, email or city"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : customers.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No customers yet.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(c) => c.waterCustomerId}
                  primary={(c) => (
                    <span className="inline-flex items-center gap-1">
                      {c.name}
                      {c.isSystemGenerated && (
                        <Badge className="bg-indigo-100 text-indigo-700" title={c.defaultCustomerType ?? "System default"}>
                          <ShieldCheck className="h-3 w-3 mr-0.5" /> System
                        </Badge>
                      )}
                    </span>
                  )}
                  secondary={(c) => (
                    <>
                      <span>{c.contactPhone ?? "—"}</span>
                      <span>·</span>
                      <span>{c.city ?? "—"}</span>
                    </>
                  )}
                  details={(c) => [
                    { label: "Phone", value: c.contactPhone ?? "—" },
                    { label: "Email", value: c.contactEmail ?? "—" },
                    { label: "City", value: c.city ?? "—" },
                    {
                      label: "Outstanding",
                      value: (
                        <span className={c.outstandingBalance > 0 ? "text-rose-600" : "text-slate-500"}>
                          {c.outstandingBalance.toFixed(2)}
                        </span>
                      ),
                    },
                  ]}
                  actions={(c) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(c)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      {!c.isSystemGenerated && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(c)}>
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
                          <TableHead>Name</TableHead>
                          <TableHead>Phone</TableHead>
                          <TableHead>Email</TableHead>
                          <TableHead>City</TableHead>
                          <TableHead className="text-right">Outstanding</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((c) => (
                          <TableRow key={c.waterCustomerId}>
                            <TableCell className="font-medium">
                              <span className="inline-flex items-center gap-2">
                                {c.name}
                                {c.isSystemGenerated && (
                                  <Badge className="bg-indigo-100 text-indigo-700" title={c.defaultCustomerType ?? "System default"}>
                                    <ShieldCheck className="h-3 w-3 mr-0.5" /> System
                                  </Badge>
                                )}
                              </span>
                            </TableCell>
                            <TableCell>{c.contactPhone ?? "—"}</TableCell>
                            <TableCell>{c.contactEmail ?? "—"}</TableCell>
                            <TableCell>{c.city ?? "—"}</TableCell>
                            <TableCell className={`text-right tabular-nums ${c.outstandingBalance > 0 ? "text-rose-600" : "text-slate-500"}`}>
                              {c.outstandingBalance.toFixed(2)}
                            </TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(c)}><Pencil className="h-4 w-4" /></Button>
                              {!c.isSystemGenerated && (
                                <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(c)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Users className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit customer" : "New water customer"}
            </DialogTitle>
            <DialogDescription>Enter the customer information below</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="Name *" full>
                <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              </FormField>
              <FormField label="Phone">
                <Input value={form.contactPhone ?? ""} onChange={(e) => setForm({ ...form, contactPhone: e.target.value })} />
              </FormField>
              <FormField label="Email">
                <Input type="email" value={form.contactEmail ?? ""} onChange={(e) => setForm({ ...form, contactEmail: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Address" color="green">
              <FormField label="Address" full>
                <Input value={form.address ?? ""} onChange={(e) => setForm({ ...form, address: e.target.value })} />
              </FormField>
              <FormField label="City">
                <Input value={form.city ?? ""} onChange={(e) => setForm({ ...form, city: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete customer?"
        itemLabel={deleteTarget?.name}
        successTitle="Customer removed"
        errorTitle="Delete failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}

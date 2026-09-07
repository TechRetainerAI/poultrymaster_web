"use client"

import { useEffect, useState } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Plus, Building2, Bird, Droplets, Loader2, Check, UtensilsCrossed } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getMyCompanies, createCompany, sendCompanyWelcomeEmail, switchCompany, type Company, type CompanyType } from "@/lib/api/companies"
import { BUSINESS_TYPES, findBusinessType, needsTemplate } from "@/lib/companies/business-types"
import { useRouter } from "next/navigation"

export default function CompaniesPage() {
  const { toast } = useToast()
  const setCompanies = useAuthStore((s) => s.setCompanies)
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const userEmail = useAuthStore((s) => s.user?.email)
  const logout = useLogout()

  const [companies, setLocal] = useState<Company[]>([])
  const pg = usePagination(companies)
  const [loading, setLoading] = useState(true)
  const router = useRouter()

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // The dropdown offers BUSINESSES, not company types. Several of them map to
  // the same CompanyType ("Generic") and differ only by template, so the form
  // holds the business-type id and derives the rest from it.
  const [form, setForm] = useState<{ name: string; businessTypeId: string; email: string; phoneNumber: string }>({
    name: "", businessTypeId: "water", email: "", phoneNumber: "",
  })
  const chosen = findBusinessType(form.businessTypeId)
  const companyType: CompanyType = chosen?.companyType ?? "Generic"

  async function load() {
    setLoading(true)
    try {
      const list = await getMyCompanies()
      setLocal(list); setCompanies(list)
    } catch (e: any) { toast({ title: "Could not load companies", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => { void load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function create() {
    if (!form.name.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      const created = await createCompany({ name: form.name, type: companyType, email: form.email || undefined, phoneNumber: form.phoneNumber || undefined })
      toast({ title: `Created ${form.name}` })
      // Email a confirmation to the company email, falling back to the owner's
      // account email so the creator always gets it.
      const to = (form.email.trim() || userEmail || "").trim()
      if (to) {
        const r = await sendCompanyWelcomeEmail({ email: to, companyName: form.name, companyType })
        if (r.success) toast({ title: "Confirmation emailed", description: `Sent to ${to}.` })
        else toast({ title: "Couldn't email confirmation", description: r.message || "Email was not sent.", variant: "destructive" })
      }
      setOpen(false); setForm({ name: "", businessTypeId: "water", email: "", phoneNumber: "" })
      await load()

      // A business type that carries a template needs setting up before it is
      // useful, so switch into the new company and hand over to the wizard.
      // Switching first is what makes the wizard's requests target it.
      if (needsTemplate(chosen) && created?.farmId) {
        try {
          const res = await switchCompany(created.farmId)
          setActiveCompany(res.farmId, res.farmName, companyType, res.accessToken.token)
          router.push(`/generic-setup/wizard?industry=${encodeURIComponent(chosen!.industryTemplate!)}`)
        } catch {
          // Switching failed — the company still exists and the owner can pick
          // it from this list, so say nothing louder than the create toast.
        }
      }
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function switchTo(c: Company) {
    if (c.farmId === activeFarmId) return
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(res.farmId, res.farmName, c.type, res.accessToken.token)
      toast({ title: `Switched to ${c.name}`, duration: 2000 })
    } catch (e: any) { toast({ title: "Switch failed", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Building2 className="h-6 w-6 text-orange-500" /> My companies
            </h1>
            <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New company</Button>
          </div>

          <p className="text-sm text-slate-500 mb-4">
            One login, multiple businesses. Create a poultry farm or a water business — switch between them anytime
            using the company switcher at the top of the page.
          </p>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : companies.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No companies yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead></TableHead>
                      <TableHead>Name</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead>Role</TableHead>
                      <TableHead>Created</TableHead>
                      <TableHead className="text-right"></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pg.pageItems.map((c) => {
                      const Icon = c.type === "Water" ? Droplets : c.type === "Poultry" ? Bird : c.type === "Hotel" ? Building2 : c.type === "Restaurant" ? UtensilsCrossed : Building2
                      const isActive = c.farmId === activeFarmId
                      return (
                        <TableRow key={c.farmId}>
                          <TableCell>
                            <Icon className={`h-5 w-5 ${c.type === "Water" ? "text-sky-500" : c.type === "Hotel" ? "text-purple-500" : c.type === "Restaurant" ? "text-rose-600" : "text-orange-500"}`} />
                          </TableCell>
                          <TableCell className="font-medium">{c.name}</TableCell>
                          <TableCell>{c.type}</TableCell>
                          <TableCell>{c.role}</TableCell>
                          <TableCell className="text-slate-500">{new Date(c.createdAt).toLocaleDateString()}</TableCell>
                          <TableCell className="text-right">
                            {isActive ? (
                              <span className="inline-flex items-center gap-1 text-emerald-600 text-sm">
                                <Check className="h-4 w-4" /> Active
                              </span>
                            ) : (
                              <Button size="sm" variant="outline" onClick={() => switchTo(c)}>Switch</Button>
                            )}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              )}
              <DataPagination {...pg.paginationProps} />
            </CardContent>
          </Card>
        </main>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Create new company</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Type</Label>
              <Select value={form.businessTypeId} onValueChange={(v) => setForm({ ...form, businessTypeId: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {BUSINESS_TYPES.map((t) => (
                    <SelectItem key={t.id} value={t.id}>{t.label} — {t.description}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {needsTemplate(chosen) && (
                <p className="text-xs text-slate-500 mt-1">
                  We&apos;ll set up the right menus and starter categories for this, and you can change any of it later.
                </p>
              )}
            </div>
            <div><Label>Company name *</Label>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Cool Spring Water Co." /></div>
            <div><Label>Contact email</Label>
              <Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div><Label>Phone</Label>
              <Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={create} disabled={saving}>{saving ? "Creating…" : "Create"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

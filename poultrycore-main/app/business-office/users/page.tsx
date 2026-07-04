"use client"

// Doc 3 §6-7: Business Office → Users & Permissions.
// Company-neutral, org-wide employee list. Unlike the per-company /employees
// page (scoped to the active company's FarmId), this lists every employee
// across all companies in the organization and lets an admin grant/revoke each
// employee's access to individual companies (UserFarms).
import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Loader2, Search, ShieldCheck, UserPlus, Building2, Check } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import {
  getOrganizationEmployees, assignCompanyAccess, removeCompanyAccess,
  type OrgEmployee,
} from "@/lib/api/admin"
import { getMyCompanies, type Company } from "@/lib/api/companies"

const TYPE_BADGE: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-700", Water: "bg-blue-100 text-blue-700", Generic: "bg-slate-100 text-slate-700",
}

export default function BusinessOfficeUsersPage() {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [employees, setEmployees] = useState<OrgEmployee[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [query, setQuery] = useState("")
  const [managed, setManaged] = useState<OrgEmployee | null>(null)
  const [busyFarm, setBusyFarm] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    try {
      const [empRes, comps] = await Promise.all([getOrganizationEmployees(), getMyCompanies().catch(() => [])])
      if (empRes.success) setEmployees(empRes.data || [])
      else toast({ title: "Could not load employees", description: empRes.message, variant: "destructive" })
      setCompanies(comps || [])
    } finally { setLoading(false) }
  }
  useEffect(() => { load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return employees
    return employees.filter((e) =>
      [e.firstName, e.lastName, e.email, e.userName, e.farmName].filter(Boolean).some((v) => v!.toLowerCase().includes(q)))
  }, [employees, query])

  function accessSet(e: OrgEmployee): Set<string> {
    return new Set((e.companies || []).map((c) => c.farmId))
  }

  async function toggleAccess(emp: OrgEmployee, company: Company, hasAccess: boolean) {
    setBusyFarm(company.farmId)
    try {
      const res = hasAccess
        ? await removeCompanyAccess(emp.id, company.farmId)
        : await assignCompanyAccess(emp.id, company.farmId, "Staff")
      if (!res.success) { toast({ title: "Update failed", description: res.message, variant: "destructive" }); return }
      // Optimistic local update + keep the open dialog in sync.
      const nextCompanies = hasAccess
        ? (emp.companies || []).filter((c) => c.farmId !== company.farmId)
        : [...(emp.companies || []), { farmId: company.farmId, name: company.name, type: company.type, role: "Staff" }]
      const updated = { ...emp, companies: nextCompanies }
      setEmployees((list) => list.map((x) => (x.id === emp.id ? updated : x)))
      setManaged((m) => (m && m.id === emp.id ? updated : m))
      toast({ title: hasAccess ? "Access revoked" : "Access granted", description: company.name })
    } finally { setBusyFarm(null) }
  }

  return (
    <BusinessOfficeShell active="users">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2"><ShieldCheck className="h-6 w-6 text-indigo-600" /> Users & Permissions</h1>
            <p className="text-slate-600">Everyone in your organization. Grant each person access to the companies they work in.</p>
          </div>
          <Link href="/employees?bo=1&add=1"><Button><UserPlus className="h-4 w-4 mr-2" /> Add employee</Button></Link>
        </div>

        <div className="relative max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search employees…" className="pl-9" />
        </div>

        {loading ? (
          <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : filtered.length === 0 ? (
          <Card><CardContent className="p-10 text-center text-slate-500">
            <ShieldCheck className="h-10 w-10 mx-auto mb-3 text-slate-300" />
            <p className="font-medium text-slate-700">No employees yet</p>
            <p className="text-sm">Add your first employee, then assign them to companies.</p>
          </CardContent></Card>
        ) : (
          <Card><CardContent className="p-0 overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
                <tr>
                  <th className="text-left font-semibold px-4 py-3">Employee</th>
                  <th className="text-left font-semibold px-4 py-3">Role</th>
                  <th className="text-left font-semibold px-4 py-3">Company access</th>
                  <th className="text-right font-semibold px-4 py-3">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filtered.map((e) => (
                  <tr key={e.id} className="hover:bg-slate-50/60">
                    <td className="px-4 py-3">
                      <div className="font-medium text-slate-900">{[e.firstName, e.lastName].filter(Boolean).join(" ") || e.userName}</div>
                      <div className="text-xs text-slate-500">{e.email || e.userName}</div>
                    </td>
                    <td className="px-4 py-3">
                      {e.isAdmin ? <Badge className="bg-orange-100 text-orange-700 hover:bg-orange-100">{e.adminTitle || "Admin"}</Badge>
                        : <Badge variant="secondary">Staff</Badge>}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1">
                        {(e.companies || []).length === 0 ? <span className="text-xs text-slate-400">No companies</span> :
                          (e.companies || []).map((c) => (
                            <span key={c.farmId} className={`text-[11px] px-2 py-0.5 rounded ${TYPE_BADGE[c.type] ?? "bg-slate-100 text-slate-700"}`}>{c.name}</span>
                          ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Button variant="outline" size="sm" onClick={() => setManaged(e)}><Building2 className="h-4 w-4 mr-1.5" /> Manage access</Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent></Card>
        )}
      </main>

      <Dialog open={!!managed} onOpenChange={(o) => !o && setManaged(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Company access — {managed ? ([managed.firstName, managed.lastName].filter(Boolean).join(" ") || managed.userName) : ""}</DialogTitle>
          </DialogHeader>
          <div className="space-y-1 max-h-96 overflow-auto">
            {companies.length === 0 ? <p className="text-sm text-slate-500 py-4">No companies in this organization yet.</p> :
              companies.map((c) => {
                const has = managed ? accessSet(managed).has(c.farmId) : false
                return (
                  <button
                    key={c.farmId}
                    disabled={busyFarm === c.farmId}
                    onClick={() => managed && toggleAccess(managed, c, has)}
                    className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border text-left transition-colors ${has ? "border-indigo-200 bg-indigo-50" : "border-slate-200 hover:bg-slate-50"}`}
                  >
                    <span className={`h-5 w-5 grid place-items-center rounded border ${has ? "bg-indigo-600 border-indigo-600 text-white" : "border-slate-300"}`}>
                      {busyFarm === c.farmId ? <Loader2 className="h-3 w-3 animate-spin" /> : has ? <Check className="h-3.5 w-3.5" /> : null}
                    </span>
                    <span className="flex-1 truncate text-slate-800">{c.name}</span>
                    <span className={`text-[10px] px-1.5 py-0.5 rounded ${TYPE_BADGE[c.type] ?? "bg-slate-100 text-slate-700"}`}>{c.type}</span>
                  </button>
                )
              })}
          </div>
          <p className="text-xs text-slate-400">Toggling access adds or removes this employee from the company. Changes apply immediately.</p>
        </DialogContent>
      </Dialog>
    </BusinessOfficeShell>
  )
}

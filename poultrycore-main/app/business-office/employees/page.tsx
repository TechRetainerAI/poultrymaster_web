"use client"

// Business Office → Employees. A read-only, org-wide roster showing each
// person's role and the companies they can access. Managing access/permissions
// lives on the sibling Users & Permissions page (/business-office/users).

import { useEffect, useMemo, useState } from "react"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Loader2, Search, Users } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { getOrganizationEmployees, type OrgEmployee } from "@/lib/api/admin"

const TYPE_BADGE: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-700", Water: "bg-blue-100 text-blue-700", Generic: "bg-slate-100 text-slate-700",
}

export default function BusinessOfficeEmployeesPage() {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [employees, setEmployees] = useState<OrgEmployee[]>([])
  const [query, setQuery] = useState("")

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true)
      try {
        const res = await getOrganizationEmployees()
        if (cancelled) return
        if (res.success) setEmployees(res.data || [])
        else toast({ title: "Could not load employees", description: res.message, variant: "destructive" })
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return employees
    return employees.filter((e) =>
      [e.firstName, e.lastName, e.email, e.userName, e.farmName].filter(Boolean).some((v) => v!.toLowerCase().includes(q)))
  }, [employees, query])

  return (
    <BusinessOfficeShell active="employees">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2"><Users className="h-6 w-6 text-indigo-600" /> Employees</h1>
          <p className="text-slate-600">Everyone in your organization, with their role and the companies they can access.</p>
        </div>

        <div className="relative max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search employees…" className="pl-9" />
        </div>

        {loading ? (
          <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : filtered.length === 0 ? (
          <Card><CardContent className="p-10 text-center text-slate-500">
            <Users className="h-10 w-10 mx-auto mb-3 text-slate-300" />
            <p className="font-medium text-slate-700">No employees yet</p>
            <p className="text-sm">Add employees from Users &amp; Permissions.</p>
          </CardContent></Card>
        ) : (
          <Card><CardContent className="p-0 overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
                <tr>
                  <th className="text-left font-semibold px-4 py-3">Employee</th>
                  <th className="text-left font-semibold px-4 py-3">Role</th>
                  <th className="text-left font-semibold px-4 py-3">Company access</th>
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
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent></Card>
        )}
      </main>
    </BusinessOfficeShell>
  )
}

"use client"

// Doc 3 §10: global Company Selector for the Business Office header — replaces
// the old "Search companies…" box. Lists companies the user can access and
// switches into the chosen one (same logic as the company card "Open" button).

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Building2, Loader2, ChevronDown } from "lucide-react"
import { getMyCompanies, switchCompany, dashboardHomeForType, type Company } from "@/lib/api/companies"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"

const TYPE_BADGE: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-700", Water: "bg-blue-100 text-blue-700", Generic: "bg-slate-100 text-slate-700",
}

export function BoCompanySelector({ className }: { className?: string }) {
  const router = useRouter()
  const { toast } = useToast()
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)
  const [companies, setCompanies] = useState<Company[]>([])
  const [open, setOpen] = useState(false)
  const [busyId, setBusyId] = useState<string | null>(null)

  useEffect(() => {
    getMyCompanies().then(setCompanies).catch(() => {})
  }, [])

  async function pick(c: Company) {
    setBusyId(c.farmId)
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(c.farmId, c.name, c.type, res?.accessToken?.token)
      setOpen(false)
      router.push(dashboardHomeForType(c.type))
    } catch (e: any) {
      toast({ title: "Could not open company", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setBusyId(null) }
  }

  return (
    <div className={className ?? "hidden md:block relative ml-4 flex-1 max-w-sm"}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center gap-2 h-9 px-3 rounded-lg border border-slate-200 bg-slate-50 text-sm text-slate-600 hover:bg-slate-100"
      >
        <Building2 className="h-4 w-4 text-slate-400" />
        <span className="truncate">Select a company…</span>
        <ChevronDown className="h-4 w-4 text-slate-400 ml-auto" />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute z-50 mt-1 w-full max-h-80 overflow-auto rounded-lg border border-slate-200 bg-white shadow-lg py-1">
            {companies.length === 0 ? (
              <div className="px-3 py-3 text-sm text-slate-500">No companies available.</div>
            ) : companies.map((c) => (
              <button
                key={c.farmId}
                onClick={() => pick(c)}
                disabled={!!busyId}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm hover:bg-slate-50 text-left"
              >
                <span className="truncate flex-1 text-slate-800">{c.name}</span>
                <span className={`text-[10px] px-1.5 py-0.5 rounded ${TYPE_BADGE[c.type] ?? "bg-slate-100 text-slate-700"}`}>{c.type}</span>
                {busyId === c.farmId && <Loader2 className="h-3.5 w-3.5 animate-spin text-slate-400" />}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

"use client"

// Doc 3 §10: global Company Selector for the Business Office header — replaces
// the old "Search companies…" box. Lists companies the user can access and
// switches into the chosen one (same logic as the company card "Open" button).

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Building2, Loader2, ChevronDown, Bird, Droplets, ShoppingBag } from "lucide-react"
import { cn } from "@/lib/utils"
import { getMyCompanies, switchCompany, dashboardHomeForType, type Company } from "@/lib/api/companies"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"

const TYPE_BADGE: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-700", Water: "bg-blue-100 text-blue-700", Generic: "bg-violet-100 text-violet-700",
}
// Type-driven icon + tinted badge (mirrors the in-app company switcher).
function typeIcon(type?: string | null) {
  if (type === "Water") return Droplets
  if (type === "Poultry") return Bird
  if (type === "Generic") return ShoppingBag
  return Building2
}
const TYPE_ICON_BG: Record<string, string> = {
  Poultry: "bg-amber-100 text-amber-600 ring-amber-200",
  Water: "bg-blue-100 text-blue-600 ring-blue-200",
  Generic: "bg-violet-100 text-violet-600 ring-violet-200",
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
          <div className="absolute z-50 mt-2 w-full max-h-96 overflow-auto rounded-xl border border-slate-200 bg-white shadow-xl ring-1 ring-black/5 p-1.5">
            <div className="px-2.5 pb-1.5 pt-1 text-[11px] font-semibold uppercase tracking-wide text-slate-400">Your companies</div>
            {companies.length === 0 ? (
              <div className="px-2.5 py-3 text-sm text-slate-500">No companies available.</div>
            ) : companies.map((c) => {
              const Icon = typeIcon(c.type)
              return (
                <button
                  key={c.farmId}
                  onClick={() => pick(c)}
                  disabled={!!busyId}
                  className="group w-full flex items-center gap-3 rounded-lg px-2.5 py-2 text-sm text-left hover:bg-slate-50 disabled:opacity-60 transition-colors"
                >
                  <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ring-1 ring-inset", TYPE_ICON_BG[c.type] ?? "bg-slate-100 text-slate-500 ring-slate-200")}>
                    <Icon className="h-4 w-4" />
                  </span>
                  <span className="flex min-w-0 flex-1 flex-col leading-tight">
                    <span className="truncate font-medium text-slate-800">{c.name}</span>
                    <span className="truncate text-[11px] uppercase tracking-wide text-slate-400">{c.type}{c.role ? ` · ${c.role}` : ""}</span>
                  </span>
                  <span className={cn("shrink-0 text-[10px] px-1.5 py-0.5 rounded-full font-medium", TYPE_BADGE[c.type] ?? "bg-slate-100 text-slate-700")}>{c.type}</span>
                  {busyId === c.farmId && <Loader2 className="h-3.5 w-3.5 animate-spin text-slate-400" />}
                </button>
              )
            })}
          </div>
        </>
      )}
    </div>
  )
}

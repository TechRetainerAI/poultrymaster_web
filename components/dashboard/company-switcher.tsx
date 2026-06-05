"use client"

import { useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { createPortal } from "react-dom"
import { Building2, ChevronsUpDown, Check, Loader2, Plus, Bird, Droplets } from "lucide-react"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { getMyCompanies, switchCompany, type Company } from "@/lib/api/companies"
import { useToast } from "@/hooks/use-toast"

function typeIcon(type: string) {
  if (type === "Water") return Droplets
  if (type === "Poultry") return Bird
  return Building2
}

export function CompanySwitcher() {
  const router = useRouter()
  const { toast } = useToast()
  const triggerRef = useRef<HTMLButtonElement>(null)
  const popoverRef = useRef<HTMLDivElement>(null)

  const companies = useAuthStore((s) => s.companies)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const setCompanies = useAuthStore((s) => s.setCompanies)
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)

  const [open, setOpen] = useState(false)
  const [pos, setPos] = useState({ top: 0, left: 0, width: 240 })
  const [loading, setLoading] = useState(false)
  const [switchingId, setSwitchingId] = useState<string | null>(null)
  const [mounted, setMounted] = useState(false)

  useEffect(() => { setMounted(true) }, [])

  const refresh = async () => {
    setLoading(true)
    try {
      const list = await getMyCompanies()
      setCompanies(list)
    } catch (err) {
      console.error("[CompanySwitcher] refresh failed", err)
    } finally {
      setLoading(false)
    }
  }

  // Always refresh on mount when we have a token. The previous guard
  // `companies.length === 0` meant a stale persisted list (e.g. containing
  // a phantom farm that was deleted server-side) was never re-validated, so
  // users could stay locked in a session pointing at a non-existent farm.
  // /Companies/mine is cheap and `setCompanies` auto-evicts stale active
  // farms (see auth-store.setCompanies — picks first if current is gone).
  useEffect(() => {
    const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null
    if (token) {
      refresh()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const updatePos = () => {
    if (!triggerRef.current) return
    const r = triggerRef.current.getBoundingClientRect()
    setPos({ top: r.bottom + 6, left: r.left, width: Math.max(r.width, 260) })
  }

  useEffect(() => {
    if (!open) return
    updatePos()
    const handleClickOutside = (e: MouseEvent) => {
      const t = e.target as Node
      if (triggerRef.current && !triggerRef.current.contains(t) &&
          popoverRef.current && !popoverRef.current.contains(t)) {
        setOpen(false)
      }
    }
    document.addEventListener("mousedown", handleClickOutside)
    window.addEventListener("resize", updatePos)
    window.addEventListener("scroll", updatePos, true)
    return () => {
      document.removeEventListener("mousedown", handleClickOutside)
      window.removeEventListener("resize", updatePos)
      window.removeEventListener("scroll", updatePos, true)
    }
  }, [open])

  const handleSwitch = async (c: Company) => {
    if (c.farmId === activeFarmId) { setOpen(false); return }
    setSwitchingId(c.farmId)
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(res.farmId, res.farmName, c.type, res.accessToken.token)
      toast({ title: `Switched to ${c.name}`, description: c.type === "Water" ? "Water company" : `${c.type} company` })
      setOpen(false)
      // Land on the most useful page for the new type. Falling through to
      // /dashboard for Generic was the bug behind "I switched to Generic but
      // the nav is still showing flocks/houses": Poultry dashboard +
      // Poultry top-nav. Each company type now lands on its own home.
      if (c.type === "Water")        router.push("/water-dashboard")
      else if (c.type === "Generic") router.push("/generic-dashboard")
      else                           router.push("/dashboard")
    } catch (err: any) {
      toast({ title: "Switch failed", description: err?.message ?? String(err), variant: "destructive" })
    } finally {
      setSwitchingId(null)
    }
  }

  const ActiveIcon = typeIcon(activeFarmType ?? "Poultry")

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={() => { updatePos(); setOpen((o) => !o) }}
        className={cn(
          "flex items-center gap-2 rounded-md border border-slate-700 bg-slate-800 px-3 py-1.5",
          "text-sm text-white hover:bg-slate-700 transition-colors min-w-0 max-w-[260px]"
        )}
      >
        <ActiveIcon className="h-4 w-4 shrink-0 text-orange-300" />
        <div className="flex min-w-0 flex-col items-start leading-tight">
          <span className="text-[10px] uppercase tracking-wide text-slate-400">Company</span>
          <span className="truncate font-medium">{activeFarmName ?? "Select…"}</span>
        </div>
        <ChevronsUpDown className="h-4 w-4 shrink-0 text-slate-400" />
      </button>

      {open && mounted && createPortal(
        <div
          ref={popoverRef}
          style={{ position: "fixed", top: pos.top, left: pos.left, width: pos.width }}
          className="z-[9999] rounded-md border border-slate-700 bg-slate-900 py-1 shadow-xl"
        >
          <div className="flex items-center justify-between border-b border-slate-800 px-3 py-2">
            <span className="text-[11px] uppercase tracking-wide text-slate-400">Your companies</span>
            {loading ? <Loader2 className="h-3 w-3 animate-spin text-slate-400" /> : null}
          </div>

          {companies.length === 0 && !loading && (
            <div className="px-3 py-3 text-sm text-slate-400">No companies yet.</div>
          )}

          {companies.map((c) => {
            const Icon = typeIcon(c.type)
            const isActive = c.farmId === activeFarmId
            const isLoadingThis = switchingId === c.farmId
            return (
              <button
                key={c.farmId}
                type="button"
                onClick={() => handleSwitch(c)}
                disabled={isLoadingThis}
                className={cn(
                  "flex w-full items-center gap-2 px-3 py-2 text-left text-sm",
                  isActive ? "bg-slate-800 text-white" : "text-slate-200 hover:bg-slate-800/70"
                )}
              >
                <Icon className={cn("h-4 w-4", c.type === "Water" ? "text-sky-300" : "text-orange-300")} />
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate font-medium">{c.name}</span>
                  <span className="text-[10px] uppercase tracking-wide text-slate-400">{c.type} · {c.role}</span>
                </div>
                {isLoadingThis ? <Loader2 className="h-4 w-4 animate-spin text-slate-300" />
                  : isActive ? <Check className="h-4 w-4 text-emerald-400" /> : null}
              </button>
            )
          })}

          <div className="mt-1 border-t border-slate-800 px-1 py-1">
            <button
              type="button"
              onClick={() => { setOpen(false); router.push("/companies") }}
              className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-slate-200 hover:bg-slate-800"
            >
              <Plus className="h-4 w-4 text-emerald-300" />
              Create new company
            </button>
          </div>
        </div>,
        document.body
      )}
    </>
  )
}

"use client"

// =============================================================================
// Poultry Changes Report (/poultry/reports/changes)
//
// An audit / change-history report: every create, update and delete of records
// on the active farm — who did it, when, and (in the detail view) the before /
// after data. Reuses the existing farm-scoped AuditLogsService, so there is no
// new backend. Surfaced in the Reports mega-menu next to the Closing report.
// =============================================================================

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { History, Search, Download, Eye, RefreshCw } from "lucide-react"
import { useIsMobile } from "@/hooks/use-mobile"
import { useLogout } from "@/hooks/use-logout"
import { useAuthStore } from "@/lib/store/auth-store"
import { getUserContext } from "@/lib/utils/user-context"
import { AuditLogsService, type AuditLog } from "@/lib/services/audit-logs.service"
import { cn } from "@/lib/utils"

type ActionKind = "Created" | "Updated" | "Deleted" | "Viewed" | "Other"

// The audit log stores the HTTP method in `action`; map it to a business verb.
function actionKind(action: string): ActionKind {
  switch ((action || "").toUpperCase()) {
    case "POST": case "CREATE": case "CREATED": return "Created"
    case "PUT": case "PATCH": case "UPDATE": case "UPDATED": return "Updated"
    case "DELETE": case "DELETED": return "Deleted"
    case "GET": case "VIEW": case "VIEWED": return "Viewed"
    default: return "Other"
  }
}

const actionBadgeClass: Record<ActionKind, string> = {
  Created: "bg-emerald-100 text-emerald-700",
  Updated: "bg-amber-100 text-amber-700",
  Deleted: "bg-rose-100 text-rose-700",
  Viewed: "bg-slate-100 text-slate-600",
  Other: "bg-slate-100 text-slate-600",
}

const formatDateTime = (s: string) => (s ? new Date(s).toLocaleString() : "—")

const displayUser = (name?: string) => {
  if (name && name.toLowerCase() !== "unknown") return name
  if (typeof window !== "undefined") {
    const local = localStorage.getItem("username") || localStorage.getItem("userName")
    if (local) return local
  }
  return "Unknown"
}

// Friendly record name: "PoultryPayment" -> "Payment", "ProductionRecord" -> "Production Record".
function friendlyResource(r?: string) {
  if (!r) return "Record"
  const out = r.replace(/^Poultry/i, "").replace(/([a-z0-9])([A-Z])/g, "$1 $2").trim()
  return out || r
}

// --- Human-readable change fields -------------------------------------------
// The audit `data` blob is the raw request/response envelope. We surface only the
// meaningful submitted values as a clean label→value list, hiding internal noise
// (GUIDs, wrapper params, zero ids, empty dates, method/path) from end users.
const NOISE_KEYS = new Set([
  "farmid", "createdby", "updatedby", "deletedby", "userid", "companyid", "tenantid",
])
const isGuid = (v: unknown) =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)
const isEmptyDate = (v: unknown) => typeof v === "string" && v.startsWith("0001-01-01")
const isIsoDate = (k: string, v: unknown) =>
  typeof v === "string" && /date|time/i.test(k) && /^\d{4}-\d{2}-\d{2}T/.test(v)

function safeParse(raw?: string | null): any {
  if (!raw) return null
  try { return JSON.parse(raw) } catch { return null }
}

// Pull the actual record object out of the request envelope, unwrapping a single
// wrapper param (e.g. `{ request: { m: {...} } }`).
function extractEntity(data: any): Record<string, unknown> | null {
  if (!data || typeof data !== "object") return null
  let req: any = data.request ?? data
  if (req && typeof req === "object" && !Array.isArray(req)) {
    const keys = Object.keys(req).filter((k) => !["method", "path", "response"].includes(k))
    if (keys.length === 1 && req[keys[0]] && typeof req[keys[0]] === "object" && !Array.isArray(req[keys[0]])) {
      req = req[keys[0]]
    }
  }
  return req && typeof req === "object" && !Array.isArray(req) ? req : null
}

function humanizeKey(k: string) {
  return k
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/^./, (c) => c.toUpperCase())
    .replace(/\bId\b/g, "ID")
}

function buildFields(raw?: string | null): { label: string; value: string }[] {
  const ent = extractEntity(safeParse(raw))
  if (!ent) return []
  const out: { label: string; value: string }[] = []
  for (const [k, v] of Object.entries(ent)) {
    const lk = k.toLowerCase()
    if (v === null || v === undefined || v === "") continue
    if (NOISE_KEYS.has(lk) || isGuid(v) || isEmptyDate(v)) continue
    if (typeof v === "number" && lk.endsWith("id") && v === 0) continue
    if (typeof v === "object") continue
    let value: string
    if (typeof v === "boolean") value = v ? "Yes" : "No"
    else if (isIsoDate(k, v)) { try { value = new Date(v as string).toLocaleString() } catch { value = String(v) } }
    else value = String(v)
    out.push({ label: humanizeKey(k), value })
  }
  return out
}

const csvCell = (v: unknown) => {
  const s = String(v ?? "")
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

const PAGE_SIZE = 15

export default function PoultryChangesReportPage() {
  const router = useRouter()
  const logout = useLogout()
  const isMobile = useIsMobile()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [logs, setLogs] = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const [search, setSearch] = useState("")
  const [actionFilter, setActionFilter] = useState<"changes" | "Created" | "Updated" | "Deleted" | "all">("changes")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [page, setPage] = useState(1)
  const [viewLog, setViewLog] = useState<AuditLog | null>(null)

  // Gate: Poultry company context only (mirrors the Reports page).
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = async () => {
    const ac = new AbortController()
    const timeoutId = setTimeout(() => ac.abort(), 45000)
    try {
      setLoading(true)
      setError("")
      const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null
      if (token) {
        const { apiClient } = await import("@/lib/api/client")
        apiClient.setToken(token)
      }
      const { farmId } = getUserContext()
      if (!farmId) {
        setError("Farm ID not found. Please log in again.")
        return
      }
      const data = await AuditLogsService.getAll({ farmId, page: 1, pageSize: 500 }, ac.signal)
      setLogs(Array.isArray(data) ? data : [])
    } catch (err: unknown) {
      const name = err instanceof Error ? err.name : ""
      setError(
        name === "AbortError"
          ? "Request timed out. The Farm API may be cold-starting — wait a moment and refresh."
          : err instanceof Error ? err.message : "Failed to load changes. Check your connection.",
      )
      setLogs([])
    } finally {
      clearTimeout(timeoutId)
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    setPage(1)
  }, [search, actionFilter, dateFrom, dateTo])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return logs
      .filter((l) => {
        const kind = actionKind(l.action)
        // "changes" excludes reads (Viewed) — the point of a change history.
        if (actionFilter === "changes" && kind === "Viewed") return false
        if (["Created", "Updated", "Deleted"].includes(actionFilter) && kind !== actionFilter) return false
        return true
      })
      .filter((l) => {
        if (!dateFrom && !dateTo) return true
        const d = (l.timestamp || "").split("T")[0]
        if (dateFrom && d < dateFrom) return false
        if (dateTo && d > dateTo) return false
        return true
      })
      .filter((l) => {
        if (!q) return true
        return (
          (l.resource || "").toLowerCase().includes(q) ||
          (l.action || "").toLowerCase().includes(q) ||
          (l.userName || "").toLowerCase().includes(q) ||
          (l.details || "").toLowerCase().includes(q) ||
          String(l.resourceId || "").toLowerCase().includes(q)
        )
      })
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
  }, [logs, search, actionFilter, dateFrom, dateTo])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const safePage = Math.min(page, totalPages)
  const paginated = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE)

  const exportCsv = () => {
    const headers = ["When", "User", "Action", "Record", "Record ID", "Status", "Details"]
    const rows = filtered.map((l) => [
      formatDateTime(l.timestamp),
      displayUser(l.userName),
      actionKind(l.action),
      l.resource,
      l.resourceId,
      l.status,
      (l.details || "").replace(/\s+/g, " ").trim(),
    ])
    const csv = [headers, ...rows].map((r) => r.map(csvCell).join(",")).join("\n")
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `poultry-changes-report-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Header */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-center justify-between")}>
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-slate-200 rounded-lg flex items-center justify-center">
                  <History className="w-5 h-5 text-slate-700" />
                </div>
                <div className="min-w-0">
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Poultry Changes Report</h1>
                  <p className="text-sm text-slate-600">Every create, update and delete on this farm — who changed what, and when.</p>
                </div>
              </div>
              <div className="flex gap-2 shrink-0">
                <Button variant="outline" size="sm" className="gap-2" onClick={load} disabled={loading}>
                  <RefreshCw className={cn("w-4 h-4", loading && "animate-spin")} /> Refresh
                </Button>
                <Button variant="outline" size="sm" className="gap-2" onClick={exportCsv} disabled={filtered.length === 0}>
                  <Download className="w-4 h-4" /> Export CSV
                </Button>
              </div>
            </div>

            {/* Filters */}
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div className="space-y-1">
                <Label className="text-xs">Search</Label>
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 w-4 h-4" />
                  <Input placeholder="Record, user, details…" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
                </div>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Action</Label>
                <Select value={actionFilter} onValueChange={(v) => setActionFilter(v as typeof actionFilter)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="changes">All changes</SelectItem>
                    <SelectItem value="Created">Created</SelectItem>
                    <SelectItem value="Updated">Updated</SelectItem>
                    <SelectItem value="Deleted">Deleted</SelectItem>
                    <SelectItem value="all">All activity (incl. views)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">From</Label>
                <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">To</Label>
                <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
              </div>
            </div>

            {error && (
              <div className="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</div>
            )}

            {/* Table */}
            <div className="rounded-xl border border-slate-200 bg-white overflow-hidden">
              <div className="overflow-x-auto">
                <Table className={cn(!isMobile && "min-w-[820px]")}>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="whitespace-nowrap">When</TableHead>
                      <TableHead>User</TableHead>
                      <TableHead>Action</TableHead>
                      <TableHead>Record</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Details</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {loading ? (
                      <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-10">Loading changes…</TableCell></TableRow>
                    ) : paginated.length === 0 ? (
                      <TableRow><TableCell colSpan={6} className="text-center text-slate-500 py-10">No changes match the current filters.</TableCell></TableRow>
                    ) : (
                      paginated.map((l) => {
                        const kind = actionKind(l.action)
                        return (
                          <TableRow key={l.id}>
                            <TableCell className="whitespace-nowrap text-sm text-slate-700">{formatDateTime(l.timestamp)}</TableCell>
                            <TableCell className="text-sm font-medium text-slate-800">{displayUser(l.userName)}</TableCell>
                            <TableCell>
                              <span className={cn("inline-flex rounded-full px-2 py-0.5 text-xs font-medium", actionBadgeClass[kind])}>{kind}</span>
                            </TableCell>
                            <TableCell className="text-sm text-slate-700">
                              {friendlyResource(l.resource)}{l.resourceId ? <span className="text-slate-400"> #{l.resourceId}</span> : null}
                            </TableCell>
                            <TableCell>
                              <Badge variant="outline" className={cn(l.status === "Failed" ? "text-rose-700 border-rose-200" : "text-emerald-700 border-emerald-200")}>{l.status}</Badge>
                            </TableCell>
                            <TableCell className="text-right">
                              <Button variant="ghost" size="sm" className="gap-1.5" onClick={() => setViewLog(l)}>
                                <Eye className="w-4 h-4" /> View
                              </Button>
                            </TableCell>
                          </TableRow>
                        )
                      })
                    )}
                  </TableBody>
                </Table>
              </div>

              {/* Pagination */}
              {!loading && filtered.length > 0 && (
                <div className="flex items-center justify-between gap-2 border-t border-slate-100 px-4 py-3 text-sm">
                  <span className="text-slate-500">
                    {(safePage - 1) * PAGE_SIZE + 1}–{Math.min(safePage * PAGE_SIZE, filtered.length)} of {filtered.length}
                  </span>
                  <div className="flex gap-2">
                    <Button variant="outline" size="sm" disabled={safePage <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>Previous</Button>
                    <Button variant="outline" size="sm" disabled={safePage >= totalPages} onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>Next</Button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </main>
      </div>

      {/* Detail dialog — before/after data + request details */}
      <Dialog open={!!viewLog} onOpenChange={(o) => { if (!o) setViewLog(null) }}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {viewLog ? `${actionKind(viewLog.action)} · ${friendlyResource(viewLog.resource)}${viewLog.resourceId ? ` #${viewLog.resourceId}` : ""}` : "Change detail"}
            </DialogTitle>
          </DialogHeader>
          {viewLog && (() => {
            const fields = buildFields(viewLog.data)
            return (
              <div className="space-y-4 text-sm">
                {/* Who / when / status */}
                <div className="grid grid-cols-2 gap-3">
                  <div><span className="text-slate-500">When</span><div className="font-medium">{formatDateTime(viewLog.timestamp)}</div></div>
                  <div><span className="text-slate-500">User</span><div className="font-medium">{displayUser(viewLog.userName)}</div></div>
                  <div><span className="text-slate-500">Action</span><div className="font-medium">{actionKind(viewLog.action)} {friendlyResource(viewLog.resource).toLowerCase()}</div></div>
                  <div><span className="text-slate-500">Status</span><div className="font-medium">{viewLog.status}</div></div>
                </div>

                {/* Human-readable record values */}
                <div>
                  <div className="text-slate-500 mb-1.5">Record details</div>
                  {fields.length > 0 ? (
                    <div className="rounded-md border border-slate-200 divide-y divide-slate-100">
                      {fields.map((f) => (
                        <div key={f.label} className="flex items-start justify-between gap-4 px-3 py-2">
                          <span className="text-slate-500">{f.label}</span>
                          <span className="font-medium text-slate-800 text-right break-words">{f.value}</span>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-slate-500">
                      No field-level details were recorded for this change.
                    </div>
                  )}
                </div>

              </div>
            )
          })()}
        </DialogContent>
      </Dialog>
    </div>
  )
}

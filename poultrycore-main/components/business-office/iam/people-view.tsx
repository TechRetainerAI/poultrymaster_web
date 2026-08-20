"use client"

// Access Management → People. Pick someone, see and change what they can do.
//
// Everything here is scoped to the company chosen in the panel header, because
// assignments are per-company: the same person can be an Accountant in one and
// Data Entry in another. `farmId` null means "show what applies everywhere".
//
// Which company you are VIEWING and which company you are GRANTING in are
// separate choices — the Assign dialog lists every company, so you can be
// looking at the whole organization and still give a role in one place. Where a
// grant is org-wide it says so, so "why can they still do this after I removed
// it here?" has a visible answer.
//
// Three layers, shown in the order they resolve:
//   Roles      — the normal way access is given
//   Overrides  — deliberate exceptions, each carrying a reason and an expiry
//   Effective  — what those two actually add up to, with the source of each grant
import { useEffect, useMemo, useState } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import {
  Loader2, Users, Search, Plus, X, Crown, ShieldOff, ShieldCheck, AlertTriangle, Monitor, LogOut,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import type { OrgEmployee } from "@/lib/api/admin"
import type { Company } from "@/lib/api/companies"
import {
  getUserRoles, getUserOverrides, getEffectivePermissions, assignRole, revokeRole,
  setOverride, clearOverride, getSessions, revokeSession, revokeAllSessions,
  type IamPermission, type IamRole, type IamUserRole, type IamOverride, type IamGrant,
  type IamSession,
} from "@/lib/api/iam"
import { ACTION_LABEL, MODULE_LABEL, dateInputToIso, formatDate } from "./shared"

/** Sentinel for an org-wide assignment — Select cannot hold an empty value. */
const ALL_COMPANIES = "__all__"

export function PeopleView({
  catalog, roles, employees, companies, farmId, farmName, companyType, canEdit,
}: {
  catalog: IamPermission[]
  roles: IamRole[]
  employees: OrgEmployee[]
  /** Every company in the organization — what "Applies to" offers. */
  companies: Company[]
  /** The company being VIEWED. Null means the whole organization. */
  farmId: string | null
  farmName: string | null
  /** Poultry | Water | Generic — filters roles that are restricted to a type. */
  companyType: string | null
  canEdit: boolean
}) {
  const { toast } = useToast()
  const [query, setQuery] = useState("")
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const [userRoles, setUserRoles] = useState<IamUserRole[]>([])
  const [overrides, setOverrides] = useState<IamOverride[]>([])
  const [grants, setGrants] = useState<IamGrant[]>([])
  const [sessions, setSessions] = useState<IamSession[]>([])
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState(false)

  const [assignOpen, setAssignOpen] = useState(false)
  // `scope` holds a farmId, or ALL_COMPANIES for an org-wide assignment. It seeds
  // from whichever company you are viewing, but is chosen independently — you can
  // be looking at all companies and still grant a role in just one.
  const [assignForm, setAssignForm] = useState({ roleId: "", scope: ALL_COMPANIES, expires: "" })

  const [overrideOpen, setOverrideOpen] = useState(false)
  const [overrideForm, setOverrideForm] = useState({
    permissionKey: "", effect: "Allow" as "Allow" | "Deny", reason: "", expires: "", search: "",
  })

  const selected = employees.find((e) => e.id === selectedId) ?? null

  async function load() {
    if (!selectedId) { setUserRoles([]); setOverrides([]); setGrants([]); setSessions([]); return }
    setLoading(true)
    try {
      const [urs, ovs, eff, sess] = await Promise.all([
        getUserRoles(farmId, selectedId),
        getUserOverrides(farmId, selectedId),
        getEffectivePermissions(farmId, selectedId),
        getSessions(selectedId),
      ])
      setUserRoles(urs ?? [])
      setOverrides(ovs ?? [])
      setGrants(eff?.grants ?? [])
      setSessions(sess ?? [])
    } finally { setLoading(false) }
  }

  useEffect(() => { void load() }, [selectedId, farmId]) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return employees
    return employees.filter((e) =>
      [e.firstName, e.lastName, e.email, e.userName].filter(Boolean).some((v) => v!.toLowerCase().includes(q)))
  }, [employees, query])

  /** Roles offerable here: a Water-only role has no business in a Poultry company. */
  const assignableRoles = useMemo(
    () => roles.filter((r) => !r.companyType || !companyType || r.companyType === companyType),
    [roles, companyType]
  )

  const permissionOptions = useMemo(() => {
    const q = overrideForm.search.trim().toLowerCase()
    const list = q
      ? catalog.filter((p) =>
          p.permissionKey.toLowerCase().includes(q) ||
          p.resourceLabel.toLowerCase().includes(q))
      : catalog
    return list.slice(0, 60)
  }, [catalog, overrideForm.search])

  /** Effective permissions folded into module → group, each carrying its source. */
  const byModule = useMemo(() => {
    if (grants.length === 0) return []
    const meta = new Map(catalog.map((p) => [p.permissionKey, p]))
    const modules = new Map<string, Map<string, { key: string; label: string; action: string; source: string }[]>>()
    for (const g of grants) {
      const p = meta.get(g.permissionKey)
      if (!p) continue
      const groups = modules.get(p.module) ?? new Map()
      const list = groups.get(p.permissionGroup) ?? []
      list.push({ key: g.permissionKey, label: p.resourceLabel, action: p.action, source: g.source })
      groups.set(p.permissionGroup, list)
      modules.set(p.module, groups)
    }
    return Array.from(modules.entries()).map(([mod, groups]) => ({
      module: mod,
      groups: Array.from(groups.entries()).map(([group, items]) => ({ group, items })),
    }))
  }, [catalog, grants])

  function displayName(e: OrgEmployee) {
    return [e.firstName, e.lastName].filter(Boolean).join(" ") || e.userName || e.email || "Unnamed"
  }

  /** Seed the scope from whichever company is being viewed — that is the likely intent. */
  function openAssign() {
    setAssignForm({ roleId: "", scope: farmId ?? ALL_COMPANIES, expires: "" })
    setAssignOpen(true)
  }

  async function doAssign() {
    if (!selectedId || !assignForm.roleId) {
      toast({ title: "Choose a role", variant: "destructive" })
      return
    }
    setBusy(true)
    try {
      const res = await assignRole({
        userId: selectedId,
        roleId: Number(assignForm.roleId),
        // A null FarmId is what the resolver treats as "every company".
        farmId: assignForm.scope === ALL_COMPANIES ? null : assignForm.scope,
        expiresAt: dateInputToIso(assignForm.expires),
      })
      if (!res.success) {
        toast({ title: "Could not assign role", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Role assigned" })
      setAssignOpen(false)
      await load()
    } finally { setBusy(false) }
  }

  async function doRevoke(ur: IamUserRole) {
    setBusy(true)
    try {
      const res = await revokeRole(ur.id, farmId)
      if (!res.success) {
        toast({ title: "Could not remove role", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Role removed", description: ur.name })
      await load()
    } finally { setBusy(false) }
  }

  async function doOverride() {
    if (!selectedId || !overrideForm.permissionKey) {
      toast({ title: "Choose a permission", variant: "destructive" })
      return
    }
    if (!overrideForm.reason.trim()) {
      toast({ title: "Reason required", description: "Say why this exception exists.", variant: "destructive" })
      return
    }
    setBusy(true)
    try {
      const res = await setOverride({
        userId: selectedId,
        farmId,
        permissionKey: overrideForm.permissionKey,
        effect: overrideForm.effect,
        reason: overrideForm.reason.trim(),
        expiresAt: dateInputToIso(overrideForm.expires),
      })
      if (!res.success) {
        toast({ title: "Could not save override", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Override saved" })
      setOverrideOpen(false)
      setOverrideForm({ permissionKey: "", effect: "Allow", reason: "", expires: "", search: "" })
      await load()
    } finally { setBusy(false) }
  }

  async function doRevokeSession(s: IamSession) {
    setBusy(true)
    try {
      const res = await revokeSession(s.sessionId, farmId)
      if (!res.success) {
        toast({ title: "Could not end session", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Session ended", description: s.device ?? undefined })
      await load()
    } finally { setBusy(false) }
  }

  async function doRevokeAll() {
    if (!selectedId) return
    setBusy(true)
    try {
      const res = await revokeAllSessions(selectedId, farmId)
      if (!res.success) {
        toast({ title: "Could not sign them out", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Signed out everywhere", description: "Their existing sign-ins have been ended." })
      await load()
    } finally { setBusy(false) }
  }

  async function doClearOverride(o: IamOverride) {
    setBusy(true)
    try {
      const res = await clearOverride(o.id, farmId)
      if (!res.success) {
        toast({ title: "Could not remove override", description: res.message, variant: "destructive" })
        return
      }
      toast({ title: "Override removed" })
      await load()
    } finally { setBusy(false) }
  }

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,320px)_1fr]">
      <div className="space-y-3">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search people…" className="pl-9" />
        </div>
        <Card><CardContent className="p-0 max-h-[32rem] overflow-y-auto divide-y divide-slate-100">
          {filtered.length === 0 ? (
            <p className="p-6 text-sm text-center text-slate-500">No people found.</p>
          ) : filtered.map((e) => (
            <button
              key={e.id}
              onClick={() => setSelectedId(e.id)}
              className={cn(
                "w-full text-left px-4 py-3 transition-colors",
                selectedId === e.id ? "bg-indigo-50" : "hover:bg-slate-50"
              )}
            >
              <div className="font-medium text-slate-900 truncate">{displayName(e)}</div>
              <div className="text-xs text-slate-500 truncate">{e.email || e.userName}</div>
            </button>
          ))}
        </CardContent></Card>
      </div>

      <div>
        {!selected ? (
          <Card><CardContent className="p-10 text-center text-slate-500">
            <Users className="h-10 w-10 mx-auto mb-3 text-slate-300" />
            <p className="font-medium text-slate-700">Choose someone to see and change what they can do</p>
            <p className="text-sm">
              {farmName
                ? `Access is shown for ${farmName}.`
                : "Showing access that applies across every company. Pick a company above to see access granted only there."}
            </p>
          </CardContent></Card>
        ) : loading ? (
          <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : (
          <div className="space-y-4">
            <Card><CardContent className="p-4">
              <div className="font-semibold text-slate-900">{displayName(selected)}</div>
              <div className="text-xs text-slate-500">{selected.email || selected.userName}</div>
            </CardContent></Card>

            {/* ---- Roles ---- */}
            <Card><CardContent className="p-4 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div className="text-sm font-semibold text-slate-900">
                  {farmName ? `Roles in ${farmName}` : "Roles across all companies"}
                </div>
                <Button size="sm" variant="outline" onClick={openAssign} disabled={!canEdit || busy}>
                  <Plus className="h-3.5 w-3.5 mr-1.5" /> Assign role
                </Button>
              </div>
              {userRoles.length === 0 ? (
                <p className="text-sm text-slate-500">
                  No roles assigned. They currently work from the staff permissions set under Employees &amp; Users.
                </p>
              ) : (
                <div className="space-y-1.5">
                  {userRoles.map((r) => (
                    <div key={r.id} className="flex items-center gap-2 px-3 py-2 rounded-lg border border-slate-200">
                      {r.isSuperuser && <Crown className="h-3.5 w-3.5 text-amber-500 shrink-0" />}
                      <span className="font-medium text-sm text-slate-800 truncate">{r.name}</span>
                      {r.isOrgWide && <Badge variant="outline" className="text-[10px]">All companies</Badge>}
                      {r.expiresAt && (
                        <Badge variant="secondary" className="text-[10px]">Until {formatDate(r.expiresAt)}</Badge>
                      )}
                      <Button
                        size="sm"
                        variant="ghost"
                        className="ml-auto h-7 w-7 p-0 text-slate-400 hover:text-red-600"
                        onClick={() => doRevoke(r)}
                        disabled={!canEdit || busy}
                        aria-label={`Remove ${r.name}`}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </CardContent></Card>

            {/* ---- Overrides ---- */}
            <Card><CardContent className="p-4 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div className="text-sm font-semibold text-slate-900">Exceptions</div>
                <Button size="sm" variant="outline" onClick={() => setOverrideOpen(true)} disabled={!canEdit || busy}>
                  <Plus className="h-3.5 w-3.5 mr-1.5" /> Add exception
                </Button>
              </div>
              {overrides.length === 0 ? (
                <p className="text-sm text-slate-500">
                  No exceptions. Everything this person can do comes from their roles.
                </p>
              ) : (
                <div className="space-y-1.5">
                  {overrides.map((o) => (
                    <div key={o.id} className={cn(
                      "flex items-start gap-2 px-3 py-2 rounded-lg border",
                      o.hasExpired ? "border-slate-200 bg-slate-50 opacity-70" : o.effect === "Deny" ? "border-red-200 bg-red-50" : "border-emerald-200 bg-emerald-50"
                    )}>
                      {o.effect === "Deny"
                        ? <ShieldOff className="h-4 w-4 text-red-600 shrink-0 mt-0.5" />
                        : <ShieldCheck className="h-4 w-4 text-emerald-600 shrink-0 mt-0.5" />}
                      <div className="min-w-0 flex-1">
                        <div className="text-sm font-medium text-slate-800">
                          {o.effect === "Deny" ? "Deny" : "Allow"} · {o.resourceLabel}: {ACTION_LABEL[o.action] ?? o.action}
                        </div>
                        <div className="text-xs text-slate-600">{o.reason}</div>
                        <div className="flex flex-wrap items-center gap-1.5 mt-1">
                          {o.isOrgWide && <Badge variant="outline" className="text-[10px]">All companies</Badge>}
                          {o.expiresAt && (
                            <Badge variant="secondary" className="text-[10px]">
                              {o.hasExpired ? "Expired" : "Until"} {formatDate(o.expiresAt)}
                            </Badge>
                          )}
                          {o.hasExpired && (
                            <span className="text-[10px] text-amber-700 flex items-center gap-1">
                              <AlertTriangle className="h-3 w-3" /> No longer in effect
                            </span>
                          )}
                        </div>
                      </div>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-7 w-7 p-0 text-slate-400 hover:text-red-600"
                        onClick={() => doClearOverride(o)}
                        disabled={!canEdit || busy}
                        aria-label="Remove exception"
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </CardContent></Card>

            {/* ---- Sessions ---- */}
            <Card><CardContent className="p-4 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div className="text-sm font-semibold text-slate-900">Signed in on</div>
                {sessions.length > 0 && (
                  <Button
                    size="sm" variant="outline"
                    className="text-red-600 border-red-200 hover:bg-red-50 hover:text-red-700"
                    onClick={doRevokeAll}
                    disabled={!canEdit || busy}
                  >
                    <LogOut className="h-3.5 w-3.5 mr-1.5" /> Sign out everywhere
                  </Button>
                )}
              </div>
              {sessions.length === 0 ? (
                <p className="text-sm text-slate-500">
                  No sign-ins recorded. Sessions start being tracked once the API has been updated.
                </p>
              ) : (
                <div className="space-y-1.5">
                  {sessions.map((s) => (
                    <div key={s.sessionId} className="flex items-center gap-2 px-3 py-2 rounded-lg border border-slate-200">
                      <Monitor className="h-4 w-4 text-slate-400 shrink-0" />
                      <div className="min-w-0 flex-1">
                        <div className="text-sm text-slate-800 truncate">{s.device || "Unknown device"}</div>
                        <div className="text-xs text-slate-500 truncate">
                          {s.ipAddress || "unknown address"} · last seen {new Date(s.lastSeenAt).toLocaleString()}
                        </div>
                      </div>
                      <Button
                        size="sm" variant="ghost"
                        className="h-7 w-7 p-0 text-slate-400 hover:text-red-600"
                        onClick={() => doRevokeSession(s)}
                        disabled={!canEdit || busy}
                        aria-label="End this session"
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}
              <p className="text-xs text-slate-400">
                Signing someone out everywhere also stops tokens they already hold — once the API has
                permission enforcement switched on.
              </p>
            </CardContent></Card>

            {/* ---- Effective ---- */}
            {byModule.length === 0 ? (
              <Card><CardContent className="p-8 text-center text-sm text-slate-500">
                No IAM permissions in this company yet.
              </CardContent></Card>
            ) : byModule.map(({ module: mod, groups }) => (
              <Card key={mod}><CardContent className="p-4">
                <div className="font-semibold text-slate-900 mb-2">{MODULE_LABEL[mod] ?? mod}</div>
                <div className="space-y-3">
                  {groups.map(({ group, items }) => (
                    <div key={group}>
                      <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">{group}</div>
                      <div className="flex flex-wrap gap-1.5">
                        {items.map((i) => (
                          <span
                            key={i.key}
                            title={`${i.key} — from ${i.source}`}
                            className="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-700"
                          >
                            {i.label}: {ACTION_LABEL[i.action] ?? i.action}
                          </span>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent></Card>
            ))}
            <p className="text-xs text-slate-400">Hover a permission to see its key and which role granted it.</p>
          </div>
        )}
      </div>

      {/* ---- Assign role dialog ---- */}
      <Dialog open={assignOpen} onOpenChange={(o) => !busy && setAssignOpen(o)}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>Assign a role</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Role</Label>
              <Select value={assignForm.roleId} onValueChange={(v) => setAssignForm((f) => ({ ...f, roleId: v }))}>
                <SelectTrigger><SelectValue placeholder="Choose a role" /></SelectTrigger>
                <SelectContent>
                  {assignableRoles.map((r) => (
                    <SelectItem key={r.roleId} value={String(r.roleId)}>{r.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Applies to</Label>
              <Select value={assignForm.scope} onValueChange={(v) => setAssignForm((f) => ({ ...f, scope: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL_COMPANIES}>Every company in the organization</SelectItem>
                  {companies.map((c) => (
                    <SelectItem key={c.farmId} value={c.farmId}>{c.name} only</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {companies.length === 0 && (
                <p className="text-xs text-amber-700">
                  No companies found, so only an organization-wide assignment is possible.
                </p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="iam-assign-expiry">Expires (optional)</Label>
              <Input
                id="iam-assign-expiry"
                type="date"
                value={assignForm.expires}
                onChange={(e) => setAssignForm((f) => ({ ...f, expires: e.target.value }))}
              />
              <p className="text-xs text-slate-500">
                Use this for cover — the role stops applying on its own, with nobody having to remember.
              </p>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAssignOpen(false)} disabled={busy}>Cancel</Button>
            <Button onClick={doAssign} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Assigning…</> : "Assign"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---- Override dialog ---- */}
      <Dialog open={overrideOpen} onOpenChange={(o) => !busy && setOverrideOpen(o)}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Add an exception</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Permission</Label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input
                  value={overrideForm.search}
                  onChange={(e) => setOverrideForm((f) => ({ ...f, search: e.target.value }))}
                  placeholder="Search permissions…"
                  className="pl-9"
                />
              </div>
              <div className="max-h-48 overflow-y-auto rounded-lg border border-slate-200 divide-y divide-slate-100">
                {permissionOptions.length === 0 ? (
                  <p className="p-4 text-sm text-center text-slate-500">No matching permissions.</p>
                ) : permissionOptions.map((p) => (
                  <button
                    key={p.permissionKey}
                    onClick={() => setOverrideForm((f) => ({ ...f, permissionKey: p.permissionKey }))}
                    className={cn(
                      "w-full text-left px-3 py-2 text-sm transition-colors",
                      overrideForm.permissionKey === p.permissionKey ? "bg-indigo-50" : "hover:bg-slate-50"
                    )}
                  >
                    <div className="font-medium text-slate-800">
                      {p.resourceLabel}: {ACTION_LABEL[p.action] ?? p.action}
                    </div>
                    <div className="text-[11px] text-slate-500">
                      {MODULE_LABEL[p.module] ?? p.module} · {p.permissionKey}
                    </div>
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-1.5">
              <Label>Effect</Label>
              <Select
                value={overrideForm.effect}
                onValueChange={(v) => setOverrideForm((f) => ({ ...f, effect: v as "Allow" | "Deny" }))}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Allow">Allow — grant this on top of their roles</SelectItem>
                  <SelectItem value="Deny">Deny — take this away</SelectItem>
                </SelectContent>
              </Select>
              {overrideForm.effect === "Deny" && (
                <p className="text-xs text-amber-700">
                  While access management is still additive, a Deny only removes what IAM granted — it cannot
                  take away a permission the older staff settings already allow.
                </p>
              )}
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="iam-override-reason">Reason</Label>
              <Textarea
                id="iam-override-reason"
                value={overrideForm.reason}
                onChange={(e) => setOverrideForm((f) => ({ ...f, reason: e.target.value }))}
                placeholder="Why this person needs an exception."
                rows={2}
              />
              <p className="text-xs text-slate-500">
                Required. Whoever reviews access next needs to tell a deliberate exception from an accident.
              </p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="iam-override-expiry">Expires (optional)</Label>
              <Input
                id="iam-override-expiry"
                type="date"
                value={overrideForm.expires}
                onChange={(e) => setOverrideForm((f) => ({ ...f, expires: e.target.value }))}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOverrideOpen(false)} disabled={busy}>Cancel</Button>
            <Button onClick={doOverride} disabled={busy}>
              {busy ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Saving…</> : "Save exception"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

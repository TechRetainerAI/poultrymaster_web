"use client"

// =============================================================================
// Staff Page Access — the per-company page permission editor.
//
// One component, shown in Edit Employee, Add Employee and Business Office →
// Users & Permissions. It edits the same IAM rows as Access Management (one
// store, two screens). Pages, sections and sensitivity come from the page
// catalog (lib/iam/page-catalog.ts) — the same list the menus, the page guard
// and the server use — so a ticked box is always exactly what the person can
// open.
//
//   PageAccessChecklist — the grouped, searchable checkbox list (controlled).
//   PageAccessEditor    — loads one employee's access per company, lets the
//                          owner change it, and saves it (with a reason and a
//                          history entry per change).
// =============================================================================

import { useCallback, useEffect, useMemo, useState } from "react"
import { ChevronDown, Eye, History, Lock, Loader2, RotateCcw, Save, Search, ShieldAlert, UserX } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"
import { pagesForCompanyType, viewKey, type PageAction, type PageDef } from "@/lib/iam/page-catalog"
import {
  actionKey, defaultProfile, describeKey, diffDrafts, groupForDisplay, sectionTotal,
  sensitiveTurnedOnBy, setPageAction, setPageView, setSection, type ShowFilter,
} from "@/lib/iam/page-access-editor"
import {
  getEffectivePermissions, getMemberships, getPageAccessHistory, setMembershipStatus, setPageAccess,
  type IamAccessAuditEntry, type IamGrant, type MembershipStatus,
} from "@/lib/api/iam"
import { getEmployeeCompanies, type CompanyAccess } from "@/lib/api/admin"

const ACTION_LABEL: Record<PageAction, string> = {
  view: "View", create: "Create", edit: "Edit", delete: "Delete", approve: "Approve", reverse: "Reverse", export: "Export",
}

// ---------------------------------------------------------------------------
// The checklist (controlled)
// ---------------------------------------------------------------------------

export function PageAccessChecklist({
  pages, draft, onDraftChange, sources, disabled = false,
}: {
  pages: PageDef[]
  draft: ReadonlySet<string>
  onDraftChange: (next: Set<string>) => void
  /** Where each currently held key comes from ("role:Organization Admin", "override"…), for the badges. */
  sources?: ReadonlyMap<string, string>
  disabled?: boolean
}) {
  const [query, setQuery] = useState("")
  const [show, setShow] = useState<ShowFilter>("all")
  const [open, setOpen] = useState<Record<string, boolean>>({})
  const [confirmSensitive, setConfirmSensitive] = useState<{ pages: PageDef[]; sectionPages: PageDef[] } | null>(null)

  const sections = useMemo(() => groupForDisplay(pages, draft, query, show), [pages, draft, query, show])
  // While searching, every matching section opens so results are visible.
  const isOpen = (s: string) => (query.trim() ? true : open[s] ?? false)

  const selectAll = (sectionPages: PageDef[]) => {
    const sensitive = sensitiveTurnedOnBy(draft, sectionPages)
    if (sensitive.length > 0) {
      setConfirmSensitive({ pages: sensitive, sectionPages })
      return
    }
    onDraftChange(setSection(draft, sectionPages, true, false))
  }

  const enabledCount = pages.filter((p) => draft.has(viewKey(p))).length

  return (
    <div className="space-y-3">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative flex-1">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" aria-hidden />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search pages…"
            className="pl-8"
            aria-label="Search pages"
          />
        </div>
        <Select value={show} onValueChange={(v) => setShow(v as ShowFilter)}>
          <SelectTrigger className="sm:w-40" aria-label="Show"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All pages</SelectItem>
            <SelectItem value="enabled">Enabled only</SelectItem>
            <SelectItem value="disabled">Disabled only</SelectItem>
          </SelectContent>
        </Select>
        <div className="flex gap-1">
          <Button type="button" variant="ghost" size="sm" onClick={() => setOpen(Object.fromEntries(sections.map((s) => [s.section, true])))}>Expand all</Button>
          <Button type="button" variant="ghost" size="sm" onClick={() => setOpen({})}>Collapse all</Button>
        </div>
      </div>

      <p className="text-xs text-slate-500">
        {enabledCount} of {pages.length} pages enabled. Ticked = can open the page; unticked = no access.
        <span className="ml-1 inline-flex items-center gap-1"><ShieldAlert className="h-3 w-3 text-amber-600" aria-hidden />marks sensitive pages, which are off by default.</span>
      </p>

      <div className="rounded-lg border border-slate-200 divide-y">
        {sections.length === 0 && <p className="p-4 text-sm text-slate-500">No pages match.</p>}
        {sections.map(({ section, pages: shown, enabled }) => {
          const total = sectionTotal(pages, section)
          const sectionPages = pages.filter((p) => p.section === section)
          return (
            <div key={section}>
              <div className="flex items-center gap-2 bg-slate-50 px-3 py-2">
                <button
                  type="button"
                  className="flex min-h-9 flex-1 items-center gap-2 text-left"
                  onClick={() => setOpen((o) => ({ ...o, [section]: !isOpen(section) }))}
                  aria-expanded={isOpen(section)}
                >
                  <ChevronDown className={cn("h-4 w-4 text-slate-500 transition-transform", !isOpen(section) && "-rotate-90")} aria-hidden />
                  <span className="text-sm font-semibold text-slate-800">{section}</span>
                  <span className="text-xs text-slate-500">— {enabled} of {total} pages enabled</span>
                </button>
                <Button type="button" variant="ghost" size="sm" disabled={disabled} onClick={() => selectAll(sectionPages)}>Select all</Button>
                <Button type="button" variant="ghost" size="sm" disabled={disabled} onClick={() => onDraftChange(setSection(draft, sectionPages, false, true))}>Clear</Button>
              </div>

              {isOpen(section) && (
                <ul className="divide-y">
                  {shown.map((page) => {
                    const on = draft.has(viewKey(page))
                    const source = sources?.get(viewKey(page))
                    return (
                      <li key={`${page.module}.${page.resource}`} className="px-3 py-2">
                        <div className="flex items-start gap-3">
                          <Checkbox
                            id={`pa-${page.module}-${page.resource}`}
                            checked={on}
                            disabled={disabled}
                            onCheckedChange={(c) => onDraftChange(setPageView(draft, page, c === true))}
                            className="mt-0.5 h-5 w-5"
                          />
                          <div className="min-w-0 flex-1">
                            <label htmlFor={`pa-${page.module}-${page.resource}`} className="flex flex-wrap items-center gap-1.5 text-sm text-slate-800">
                              {page.label}
                              {page.sensitive && <ShieldAlert className="h-3.5 w-3.5 text-amber-600" aria-label="Sensitive" />}
                              {source?.startsWith("role:") && on && (
                                <Badge variant="secondary" className="text-[10px]">via {source.slice(5)}</Badge>
                              )}
                            </label>
                            <p className="text-xs text-slate-500">{page.group}{page.description ? ` · ${page.description}` : ""}</p>
                            {(page.actions?.length ?? 0) > 0 && (
                              <div className="mt-1.5 flex flex-wrap gap-1.5" role="group" aria-label={`${page.label} actions`}>
                                {page.actions!.map((a) => {
                                  const k = actionKey(page, a)
                                  const held = draft.has(k)
                                  return (
                                    <button
                                      key={a}
                                      type="button"
                                      disabled={disabled || !on}
                                      aria-pressed={held}
                                      onClick={() => onDraftChange(setPageAction(draft, page, a, !held))}
                                      className={cn(
                                        "rounded-full border px-2.5 py-1 text-xs transition-colors disabled:opacity-40",
                                        held ? "border-slate-700 bg-slate-700 text-white" : "border-slate-300 bg-white text-slate-600 hover:bg-slate-50",
                                        (a === "approve" || a === "reverse" || a === "delete") && held && "border-amber-700 bg-amber-700",
                                      )}
                                    >
                                      {ACTION_LABEL[a]}
                                    </button>
                                  )
                                })}
                              </div>
                            )}
                          </div>
                        </div>
                      </li>
                    )
                  })}
                </ul>
              )}
            </div>
          )
        })}
      </div>

      <AlertDialog open={!!confirmSensitive} onOpenChange={(o) => !o && setConfirmSensitive(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Include sensitive pages?</AlertDialogTitle>
            <AlertDialogDescription>
              This section includes pages that are usually kept to owners and managers:{" "}
              <strong>{confirmSensitive?.pages.map((p) => p.label).join(", ")}</strong>.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel
              onClick={() => {
                if (confirmSensitive) onDraftChange(setSection(draft, confirmSensitive.sectionPages, true, false))
                setConfirmSensitive(null)
              }}
            >
              Only the others
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (confirmSensitive) onDraftChange(setSection(draft, confirmSensitive.sectionPages, true, true))
                setConfirmSensitive(null)
              }}
            >
              Include sensitive pages
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

// ---------------------------------------------------------------------------
// The editor (loads, saves, history, status)
// ---------------------------------------------------------------------------

function fmtWhen(iso: string) {
  try { return new Date(iso).toLocaleString() } catch { return iso }
}

export function PageAccessEditor({
  employeeId, companies: companiesProp, disabled = false,
}: {
  employeeId: string
  /** The companies this employee belongs to; loaded when omitted. */
  companies?: CompanyAccess[]
  disabled?: boolean
}) {
  const { toast } = useToast()
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [companies, setCompanies] = useState<CompanyAccess[]>(companiesProp ?? [])
  const [farmId, setFarmId] = useState<string | null>(null)
  const [initial, setInitial] = useState<Set<string>>(new Set())
  const [draft, setDraft] = useState<Set<string>>(new Set())
  const [sources, setSources] = useState<Map<string, string>>(new Map())
  const [isOwner, setIsOwner] = useState(false)
  const [status, setStatus] = useState<MembershipStatus>("active")
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [reason, setReason] = useState("")
  const [previewOpen, setPreviewOpen] = useState(false)
  const [historyOpen, setHistoryOpen] = useState(false)
  const [history, setHistory] = useState<IamAccessAuditEntry[] | null>(null)
  const [pendingFarm, setPendingFarm] = useState<string | null>(null)

  useEffect(() => {
    if (companiesProp) { setCompanies(companiesProp); return }
    void getEmployeeCompanies(employeeId).then((res) => setCompanies(res.success && res.data ? res.data : []))
  }, [employeeId, companiesProp])

  useEffect(() => {
    if (farmId || companies.length === 0) return
    setFarmId(companies.find((c) => c.farmId === activeFarmId)?.farmId ?? companies[0].farmId)
  }, [companies, farmId, activeFarmId])

  const company = companies.find((c) => c.farmId === farmId) ?? null
  const pages = useMemo(() => pagesForCompanyType(company?.type), [company?.type])

  const load = useCallback(async (fid: string) => {
    setLoading(true)
    const [eff, memberships] = await Promise.all([getEffectivePermissions(fid, employeeId), getMemberships(employeeId, fid)])
    const grants: IamGrant[] = eff?.grants ?? []
    const keys = new Set(grants.map((g) => g.permissionKey))
    setSources(new Map(grants.map((g) => [g.permissionKey, g.source])))
    setIsOwner(grants.some((g) => g.source === "owner"))
    setInitial(keys)
    setDraft(new Set(keys))
    setStatus(memberships?.find((m) => m.farmId === fid)?.status ?? "active")
    setReason("")
    setHistory(null)
    setLoading(false)
  }, [employeeId])

  useEffect(() => { if (farmId) void load(farmId) }, [farmId, load])

  const diff = useMemo(() => diffDrafts(initial, draft), [initial, draft])
  const dirty = diff.added.length + diff.removed.length > 0

  // Unsaved-changes warning on leaving the page.
  useEffect(() => {
    if (!dirty) return
    const onBeforeUnload = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = "" }
    window.addEventListener("beforeunload", onBeforeUnload)
    return () => window.removeEventListener("beforeunload", onBeforeUnload)
  }, [dirty])

  const chooseCompany = (fid: string) => {
    if (fid === farmId) return
    if (dirty) { setPendingFarm(fid); return }
    setFarmId(fid)
  }

  const save = async () => {
    if (!farmId) return
    setSaving(true)
    const res = await setPageAccess(employeeId, { farmId, permissionKeys: [...draft], reason: reason.trim() || null })
    setSaving(false)
    if (!res.success) {
      toast({ title: "Could not save page access", description: res.message, variant: "destructive" })
      return
    }
    toast({ title: "Page access saved", description: `${company?.name ?? "Company"}: ${diff.added.length + diff.removed.length} change(s). They apply on the employee's next click.` })
    void load(farmId)
  }

  const changeStatus = async (next: MembershipStatus) => {
    if (!farmId || next === status) return
    const res = await setMembershipStatus(employeeId, { farmId, status: next, reason: reason.trim() || null })
    if (!res.success) {
      toast({ title: "Could not change status", description: res.message, variant: "destructive" })
      return
    }
    setStatus(next)
    toast({
      title: next === "active" ? "Access restored" : next === "suspended" ? "Employee suspended" : "Employee terminated",
      description: next === "active" ? undefined : "They lose access to this company immediately, whatever is ticked.",
    })
  }

  const openHistory = async () => {
    setHistoryOpen(true)
    if (farmId) setHistory(await getPageAccessHistory(employeeId, farmId))
  }

  if (companies.length === 0) {
    return <p className="text-sm text-slate-500">This employee is not linked to any company yet. Give them company access first.</p>
  }

  const enabledPages = pages.filter((p) => draft.has(viewKey(p)))

  return (
    <div className="space-y-3">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="flex-1 space-y-1">
          <Label className="text-xs text-slate-600">Company</Label>
          <Select value={farmId ?? undefined} onValueChange={chooseCompany}>
            <SelectTrigger aria-label="Company"><SelectValue placeholder="Choose a company" /></SelectTrigger>
            <SelectContent>
              {companies.map((c) => <SelectItem key={c.farmId} value={c.farmId}>{c.name} · {c.type}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        {!isOwner && (
          <div className="space-y-1 sm:w-44">
            <Label className="text-xs text-slate-600">Status at this company</Label>
            <Select value={status} onValueChange={(v) => void changeStatus(v as MembershipStatus)} disabled={disabled}>
              <SelectTrigger aria-label="Status"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="active">Active</SelectItem>
                <SelectItem value="suspended">Suspended</SelectItem>
                <SelectItem value="terminated">Terminated</SelectItem>
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      {loading ? (
        <div className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" />Loading access…</div>
      ) : isOwner ? (
        <div className="flex items-start gap-2 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900">
          <Lock className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          This person owns {company?.name}. Owners always have full access and cannot be restricted.
        </div>
      ) : (
        <>
          {status !== "active" && (
            <div className="flex items-start gap-2 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">
              <UserX className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
              {status === "suspended" ? "Suspended" : "Terminated"} at this company: no access at all, whatever is ticked below.
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            <Button type="button" variant="outline" size="sm" onClick={() => setPreviewOpen(true)}><Eye className="mr-1.5 h-4 w-4" />Effective access</Button>
            <Button type="button" variant="outline" size="sm" onClick={() => void openHistory()}><History className="mr-1.5 h-4 w-4" />Permission history</Button>
            <Button type="button" variant="outline" size="sm" disabled={disabled} onClick={() => setDraft(defaultProfile(pages, draft))}>
              <RotateCcw className="mr-1.5 h-4 w-4" />Reset to default profile
            </Button>
          </div>

          <PageAccessChecklist pages={pages} draft={draft} onDraftChange={setDraft} sources={sources} disabled={disabled || saving} />

          <div className="sticky bottom-0 z-10 space-y-2 rounded-lg border border-slate-200 bg-white/95 p-3 backdrop-blur">
            {dirty && (
              <p className="text-xs text-amber-700">
                Unsaved changes: {diff.added.length} added, {diff.removed.length} removed.
              </p>
            )}
            <div className="flex flex-col gap-2 sm:flex-row">
              <Input
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Reason for the change (optional, kept in the history)"
                maxLength={300}
                disabled={disabled || saving}
              />
              <Button type="button" onClick={() => void save()} disabled={disabled || saving || !dirty} className="shrink-0">
                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}Save Permissions
              </Button>
            </div>
          </div>
        </>
      )}

      <Sheet open={previewOpen} onOpenChange={setPreviewOpen}>
        <SheetContent className="overflow-y-auto sm:max-w-md">
          <SheetHeader>
            <SheetTitle>Effective access · {company?.name}</SheetTitle>
            <SheetDescription>
              What this person will be able to open{dirty ? " once you save" : ""}. Where it comes from is shown on the right.
            </SheetDescription>
          </SheetHeader>
          <div className="mt-4 space-y-1 text-sm">
            {status !== "active" && <p className="text-rose-700">Nothing — they are {status} at this company.</p>}
            {status === "active" && enabledPages.length === 0 && <p className="text-slate-500">No pages. They will only see the dashboard.</p>}
            {status === "active" && enabledPages.map((p) => {
              const k = viewKey(p)
              const src = !initial.has(k) ? "pending save" : sources.get(k)?.startsWith("role:") ? `role: ${sources.get(k)!.slice(5)}` : "ticked"
              const acts = (p.actions ?? []).filter((a) => draft.has(actionKey(p, a)))
              return (
                <div key={k} className="flex items-start justify-between gap-3 border-b py-1.5">
                  <div>
                    <p className="text-slate-800">{p.label}</p>
                    {acts.length > 0 && <p className="text-xs text-slate-500">{acts.map((a) => ACTION_LABEL[a]).join(" · ")}</p>}
                  </div>
                  <span className="shrink-0 text-xs text-slate-500">{src}</span>
                </div>
              )
            })}
            {dirty && diff.removed.length > 0 && (
              <div className="pt-3">
                <p className="text-xs font-semibold text-slate-600">Will be removed on save</p>
                <p className="text-xs text-slate-500">{diff.removed.map((k) => describeKey(k, pages)).join(", ")}</p>
              </div>
            )}
          </div>
        </SheetContent>
      </Sheet>

      <Sheet open={historyOpen} onOpenChange={setHistoryOpen}>
        <SheetContent className="overflow-y-auto sm:max-w-md">
          <SheetHeader>
            <SheetTitle>Permission history · {company?.name}</SheetTitle>
            <SheetDescription>Every page-access and status change for this employee, newest first.</SheetDescription>
          </SheetHeader>
          <div className="mt-4 space-y-2 text-sm">
            {history === null && <p className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" />Loading…</p>}
            {history?.length === 0 && <p className="text-slate-500">No changes recorded yet.</p>}
            {history?.map((h) => (
              <div key={h.id} className="border-b pb-2">
                <p className="text-slate-800">{h.detail}</p>
                <p className="text-xs text-slate-500">{fmtWhen(h.occurredAt)} · by {h.actorName || h.actorId || "system"}</p>
              </div>
            ))}
          </div>
        </SheetContent>
      </Sheet>

      <AlertDialog open={!!pendingFarm} onOpenChange={(o) => !o && setPendingFarm(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Discard unsaved changes?</AlertDialogTitle>
            <AlertDialogDescription>
              You changed {diff.added.length + diff.removed.length} permission(s) for {company?.name} without saving.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep editing</AlertDialogCancel>
            <AlertDialogAction onClick={() => { setFarmId(pendingFarm); setPendingFarm(null) }}>Discard and switch</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

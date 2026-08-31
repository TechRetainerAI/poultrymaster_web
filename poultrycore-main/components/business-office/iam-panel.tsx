"use client"

// Business Office → Access. Identity & Access Management.
//
// This is the shell: it loads the shared data once (catalog, roles, people,
// companies) and hands it to the four views, which own their own editing.
//
// Scope comes from the picker in the header, NOT from the auth store. Being in
// the Business Office is by definition the company-neutral state — the shell
// clears the active company on mount — but IAM assignments are per-company, so
// this tab has to ask which company you mean rather than assume one.
//
// Phase 2 — roles can be created and assigned, and per-user exceptions recorded.
// What is still true, and what the banner says out loud: none of it is ENFORCED
// by the API yet. It changes what the UI offers, not what a crafted request can
// do, and it can only widen access, never narrow it. That is phase 3.
import { useCallback, useEffect, useMemo, useState } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Loader2, KeyRound, Check, ShieldAlert, Users, Building2, ShieldCheck } from "lucide-react"
import { usePermissions } from "@/hooks/use-permissions"
import { getOrganizationEmployees, type OrgEmployee } from "@/lib/api/admin"
import { getMyCompanies, type Company } from "@/lib/api/companies"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import { getIamCatalog, getIamRoles, type IamPermission, type IamRole } from "@/lib/api/iam"
import { RolesView } from "./iam/roles-view"
import { MatrixView } from "./iam/matrix-view"
import { PeopleView } from "./iam/people-view"
import { SecurityView } from "./iam/security-view"
import { moduleForCompanyType } from "./iam/shared"

/** Sentinel for the "no single company" scope — Select cannot hold an empty value. */
const ALL_COMPANIES = "__all__"

export function IamPanel({ showHeading = true }: { showHeading?: boolean }) {
  const permissions = usePermissions()

  // Being in the Business Office IS the company-neutral state — the shell clears
  // the active company on mount (business-office-shell.tsx). So this tab cannot
  // read the scope off the auth store the way an in-company page does; it has to
  // ask which company you mean. Assignments are per-company, so without this
  // there is no way to grant a role in one company from here.
  const [companies, setCompanies] = useState<Company[]>([])
  const [scope, setScope] = useState<string>(ALL_COMPANIES)

  const scopeFarmId = scope === ALL_COMPANIES ? null : scope
  const scopeCompany = companies.find((c) => c.farmId === scopeFarmId) ?? null
  const scopeName = scopeCompany?.name ?? null
  const scopeType = scopeCompany?.type ?? null

  const [loading, setLoading] = useState(true)
  const [catalog, setCatalog] = useState<IamPermission[] | null>(null)
  const [roles, setRoles] = useState<IamRole[]>([])
  // Distinct from "no roles": the roles call itself failed. The likely cause is
  // that the server refused it, which happens when 199 is applied but 200 (the
  // bootstrap that grants anyone office.access.view) is not — a state the client
  // would otherwise render as a silently empty tab.
  const [rolesUnavailable, setRolesUnavailable] = useState(false)
  const [employees, setEmployees] = useState<OrgEmployee[]>([])

  const [selectedRoleId, setSelectedRoleId] = useState<number | null>(null)
  const [module, setModule] = useState<string>("poultry")

  // Picking a company should move the matrix to that company's module — looking
  // at a Water company's access while the grid shows Poultry is just confusing.
  useEffect(() => {
    if (scopeType) setModule(moduleForCompanyType(scopeType))
  }, [scopeType])

  const canView = permissions.isLoading || permissions.can("office.access.view")
  const canCreate = permissions.can("office.access.create")
  const canEdit = permissions.can("office.access.edit")
  const canDelete = permissions.can("office.access.delete")

  /** Reload roles after a create/edit/delete, without re-fetching the catalog. */
  const reloadRoles = useCallback(async () => {
    const rs = await getIamRoles(scopeFarmId)
    setRoles(rs ?? [])
    setRolesUnavailable(rs === null)
  }, [scopeFarmId])

  useEffect(() => {
    let cancelled = false
    void (async () => {
      setLoading(true)
      const [cat, rs, emp, comps] = await Promise.all([
        getIamCatalog(),
        getIamRoles(scopeFarmId),
        getOrganizationEmployees().catch(() => ({ success: false, data: [] as OrgEmployee[] })),
        getMyCompanies().catch(() => [] as Company[]),
      ])
      if (cancelled) return
      setCatalog(cat)
      setRoles(rs ?? [])
      setRolesUnavailable(rs === null)
      setEmployees((emp as { success: boolean; data?: OrgEmployee[] }).data ?? [])
      setCompanies(comps ?? [])
      if (rs?.length) setSelectedRoleId((cur) => cur ?? rs[0].roleId)
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [scopeFarmId])

  const heading = useMemo(() => (
    showHeading ? (
      <div>
        <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
          <KeyRound className="h-6 w-6 text-indigo-600" /> Access Management
        </h1>
        <p className="text-slate-600">Roles, what each one can do, and who holds them.</p>
      </div>
    ) : (
      <p className="text-slate-600">Roles, what each one can do, and who holds them.</p>
    )
  ), [showHeading])

  if (!canView) {
    return (
      <Card><CardContent className="p-10 text-center text-slate-500">
        <ShieldAlert className="h-10 w-10 mx-auto mb-3 text-slate-300" />
        <p className="font-medium text-slate-700">You do not have access to this section</p>
        <p className="text-sm">Managing roles and permissions requires the Access Management permission.</p>
      </CardContent></Card>
    )
  }

  if (loading) {
    return <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading access data…</div>
  }

  // catalog === null means the endpoint answered with nothing — almost always a
  // database that has not had the IAM migrations applied. Say so rather than
  // rendering an empty tab that looks broken.
  if (!catalog) {
    return (
      <Card><CardContent className="p-10 text-center text-slate-500">
        <ShieldAlert className="h-10 w-10 mx-auto mb-3 text-amber-400" />
        <p className="font-medium text-slate-700">Access management is not set up on this database yet</p>
        <p className="text-sm">
          Apply <code className="text-xs bg-slate-100 px-1 py-0.5 rounded">199_IamFoundation.sql</code>,{" "}
          <code className="text-xs bg-slate-100 px-1 py-0.5 rounded">200_IamPhase1Reads.sql</code> and{" "}
          <code className="text-xs bg-slate-100 px-1 py-0.5 rounded">201_IamPhase2Writes.sql</code>, then restart the API.
        </p>
      </CardContent></Card>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        {heading}
        {/* The scope picker, not a status badge: the Business Office has no
            active company, so this is where you say which one you mean. */}
        <div className="flex w-full items-center gap-2 sm:w-auto">
          <Building2 className="h-4 w-4 text-slate-400 shrink-0" />
          <Select value={scope} onValueChange={setScope}>
            <SelectTrigger className="h-9 w-full sm:w-[220px]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL_COMPANIES}>All companies</SelectItem>
              {companies.map((c) => (
                <SelectItem key={c.farmId} value={c.farmId}>{c.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      {rolesUnavailable && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Roles could not be loaded. If the database has{" "}
          <code className="text-xs bg-amber-100 px-1 py-0.5 rounded">199_IamFoundation.sql</code> but not{" "}
          <code className="text-xs bg-amber-100 px-1 py-0.5 rounded">200_IamPhase1Reads.sql</code>, nobody holds the
          Access Management permission yet — apply it and restart the API.
        </div>
      )}

      <div className="rounded-lg border border-sky-200 bg-sky-50 px-4 py-3 text-sm text-sky-900">
        Roles set here <strong>add</strong> to what someone can already do — they cannot take access away.
        Existing staff permissions under <strong>Employees &amp; Users</strong> still apply, and the API does not
        enforce these roles yet, so treat this as how access <em>should</em> look rather than a lock.
      </div>

      <Tabs defaultValue="roles">
        {/* Wraps onto a second row on phones instead of running off the side. */}
        <TabsList className="flex h-auto w-full flex-wrap justify-start gap-1 sm:inline-flex sm:h-9 sm:w-fit sm:flex-nowrap sm:gap-0">
          <TabsTrigger value="roles" className="h-8 sm:h-[calc(100%-1px)]"><KeyRound className="h-4 w-4 mr-1.5" /> Roles</TabsTrigger>
          <TabsTrigger value="matrix" className="h-8 sm:h-[calc(100%-1px)]"><Check className="h-4 w-4 mr-1.5" /> Permission Matrix</TabsTrigger>
          <TabsTrigger value="people" className="h-8 sm:h-[calc(100%-1px)]"><Users className="h-4 w-4 mr-1.5" /> People</TabsTrigger>
          <TabsTrigger value="security" className="h-8 sm:h-[calc(100%-1px)]"><ShieldCheck className="h-4 w-4 mr-1.5" /> Security</TabsTrigger>
        </TabsList>

        <TabsContent value="roles" className="pt-4">
          <RolesView
            roles={roles}
            selectedRoleId={selectedRoleId}
            onSelect={setSelectedRoleId}
            farmId={scopeFarmId}
            canCreate={canCreate}
            canEdit={canEdit}
            canDelete={canDelete}
            onChanged={reloadRoles}
          />
        </TabsContent>

        <TabsContent value="matrix" className="pt-4">
          <MatrixView
            catalog={catalog}
            roles={roles}
            selectedRoleId={selectedRoleId}
            onSelectRole={setSelectedRoleId}
            module={module}
            onModuleChange={setModule}
            farmId={scopeFarmId}
            canEdit={canEdit}
            onChanged={reloadRoles}
          />
        </TabsContent>

        <TabsContent value="people" className="pt-4">
          <PeopleView
            catalog={catalog}
            roles={roles}
            employees={employees}
            companies={companies}
            farmId={scopeFarmId}
            farmName={scopeName}
            companyType={scopeType}
            canEdit={canEdit}
          />
        </TabsContent>

        <TabsContent value="security" className="pt-4">
          <SecurityView farmId={scopeFarmId} canEdit={canEdit} />
        </TabsContent>
      </Tabs>
    </div>
  )
}

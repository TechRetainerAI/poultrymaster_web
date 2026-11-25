"use client"

// One project's workspace: its own dashboard, with "work inside the project"
// actions that open the EXISTING forms with this project already chosen.
// Nothing here posts money; every figure comes from the engine (484).

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useParams, useRouter, useSearchParams } from "next/navigation"
import { Suspense } from "react"
import {
  Archive, Briefcase, Flag, HandCoins, Loader2, Package, Pencil, Receipt, RotateCcw, ShoppingCart, TrendingUp,
} from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectKpis } from "@/components/generic/projects/project-kpis"
import { ProjectStatusBadge } from "@/components/generic/projects/project-status-badge"
import {
  BudgetTab, CashTab, ExpensesTab, InventoryTab, MilestonesTab, PnlStatement, SalesTab, TransactionsTab,
} from "@/components/generic/projects/project-tabs"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { invalidateProjectOptions, useProjectsEnabled } from "@/hooks/use-generic-projects"
import { useFmt } from "@/lib/currency"
import {
  archiveProject, getProject, getProjectSummary, getProjectTransactions, restoreProject, setProjectStatus,
  PROJECT_STATUSES, type GenericProject, type ProjectSummary, type ProjectTransactions,
} from "@/lib/api/generic-projects"

const TABS = [
  ["overview", "Overview"], ["transactions", "Transactions"], ["inventory", "Purchases & Inventory"],
  ["sales", "Sales & Receivables"], ["costs", "Expenses & Costs"], ["cash", "Cash Flow & Funding"],
  ["pnl", "Profit & Loss"], ["budget", "Budget"], ["milestones", "Milestones"],
] as const

function Workspace() {
  const { id } = useParams<{ id: string }>()
  const projectId = Number(id)
  const router = useRouter()
  const sp = useSearchParams()
  const fmt = useFmt()
  const { toast } = useToast()
  const { can } = usePermissions()
  const { enabled } = useProjectsEnabled()
  const [tab, setTab] = useState<string>(sp.get("tab") ?? "overview")
  const [project, setProject] = useState<GenericProject | null>(null)
  const [summary, setSummary] = useState<ProjectSummary | null>(null)
  const [tx, setTx] = useState<ProjectTransactions | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [statusOpen, setStatusOpen] = useState(false)
  const [newStatus, setNewStatus] = useState("Active")
  const [statusNote, setStatusNote] = useState("")
  const [newMilestone, setNewMilestone] = useState(false)

  const load = useCallback(async () => {
    try {
      const [p, s, t] = await Promise.all([getProject(projectId), getProjectSummary(projectId), getProjectTransactions(projectId)])
      setProject(p); setSummary(s); setTx(t); setError(null)
    } catch (e: any) {
      setError(e?.message ?? String(e))
    }
  }, [projectId])
  useEffect(() => { void load() }, [load])

  const go = (t: string) => { setTab(t); router.replace(`/generic-projects/${projectId}?tab=${t}`, { scroll: false }) }

  const archived = project?.status === "Archived"
  const canWork = enabled && !archived
  const q = `projectId=${projectId}`
  const actions = useMemo(() => canWork ? [
    { label: "Record purchase", href: `/generic-purchases/new?${q}`, icon: Package, show: can("generic.purchases.create") },
    { label: "Add expense", href: `/generic-expenses/new?${q}`, icon: Receipt, show: can("generic.expenses.create") },
    { label: "Record sale", href: `/generic-sales/new?${q}`, icon: ShoppingCart, show: can("generic.sales.create") },
    { label: "Owner contribution", href: `/generic-owner-money?${q}&new=Contribution`, icon: HandCoins, show: can("generic.owner-entries.create") },
  ] : [], [canWork, q, can])

  const changeStatus = async () => {
    try {
      setProject(await setProjectStatus(projectId, newStatus, statusNote || undefined))
      invalidateProjectOptions(); setStatusOpen(false); setStatusNote("")
    } catch (e: any) { toast({ title: "Could not change status", description: e?.message, variant: "destructive" }) }
  }
  const archive = async () => {
    if (!window.confirm("Archive this project? It disappears from pickers and lists. Nothing linked to it changes, and you can restore it later.")) return
    try { await archiveProject(projectId); invalidateProjectOptions(); await load() }
    catch (e: any) { toast({ title: "Could not archive", description: e?.message, variant: "destructive" }) }
  }
  const restore = async () => {
    try { setProject(await restoreProject(projectId)); invalidateProjectOptions() }
    catch (e: any) { toast({ title: "Could not restore", description: e?.message, variant: "destructive" }) }
  }

  if (error) return <ProjectPage title="Project" back="/generic-projects"><p className="text-sm text-rose-600">{error}</p></ProjectPage>
  if (!project || !summary || !tx) {
    return <ProjectPage title="Project" back="/generic-projects"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></ProjectPage>
  }

  return (
    <ProjectPage
      back="/generic-projects"
      icon={<Briefcase className="h-5 w-5" />}
      title={<>{project.projectNumber} — {project.name} <ProjectStatusBadge status={project.status} className="ml-1" /></>}
      subtitle={<>
        {project.kind}
        {(project.customerName || project.contractingOrganization) && <> · {project.customerName ?? project.contractingOrganization}</>}
        {project.externalContractNumber && <> · Contract {project.externalContractNumber}</>}
        {project.awardValue != null && <> · Award {fmt(project.awardValue)}</>}
        {project.expectedEndDate && <> · Due {project.expectedEndDate}</>}
      </>}
      actions={<>
        {!archived && can("generic.projects.edit") && <>
          <Button variant="outline" size="sm" asChild><Link href={`/generic-projects/${projectId}/edit`}><Pencil className="mr-1 h-4 w-4" />Edit</Link></Button>
          <Button variant="outline" size="sm" onClick={() => { setNewStatus(project.status); setStatusOpen(true) }}><Flag className="mr-1 h-4 w-4" />Status</Button>
        </>}
        {can("generic.projects.delete") && (archived
          ? <Button variant="outline" size="sm" onClick={restore}><RotateCcw className="mr-1 h-4 w-4" />Restore</Button>
          : <Button variant="ghost" size="sm" onClick={archive}><Archive className="mr-1 h-4 w-4" />Archive</Button>)}
      </>}>

      {actions.some((a) => a.show) && (
        <Card>
          <CardContent className="flex flex-wrap items-center gap-2 p-3">
            <span className="mr-1 text-sm text-slate-500">Work inside this project:</span>
            {actions.filter((a) => a.show).map((a) => (
              <Button key={a.label} size="sm" variant="secondary" asChild>
                <Link href={a.href}><a.icon className="mr-1 h-4 w-4" />{a.label}</Link>
              </Button>
            ))}
            <Button size="sm" variant="secondary" onClick={() => go("inventory")}><Package className="mr-1 h-4 w-4" />View inventory</Button>
            <Button size="sm" variant="secondary" onClick={() => go("pnl")}><TrendingUp className="mr-1 h-4 w-4" />View P&amp;L</Button>
            <Button size="sm" variant="secondary" onClick={() => go("cash")}>View cash flow</Button>
            <Button size="sm" variant="secondary" onClick={() => { go("milestones"); setNewMilestone(true) }}><Flag className="mr-1 h-4 w-4" />Add milestone</Button>
          </CardContent>
        </Card>
      )}

      <Tabs value={tab} onValueChange={go}>
        <TabsList className="h-auto flex-wrap justify-start">
          {TABS.map(([v, l]) => <TabsTrigger key={v} value={v}>{l}</TabsTrigger>)}
        </TabsList>
        <TabsContent value="overview" className="space-y-4">
          <ProjectKpis s={summary} />
          {project.description && <Card><CardHeader className="pb-1"><CardTitle className="text-sm">About</CardTitle></CardHeader><CardContent className="text-sm text-slate-700">{project.description}</CardContent></Card>}
          {project.statusHistory && project.statusHistory.length > 0 && (
            <Card>
              <CardHeader className="pb-1"><CardTitle className="text-sm">Status history</CardTitle></CardHeader>
              <CardContent className="space-y-1 text-sm">
                {project.statusHistory.map((h, i) => (
                  <div key={i} className="flex flex-wrap gap-2 text-slate-600">
                    <span className="text-slate-400">{new Date(h.changedAt).toLocaleString()}</span>
                    <span>{h.fromStatus ? `${h.fromStatus} → ` : ""}<b>{h.toStatus}</b></span>
                    {h.note && <span>· {h.note}</span>}{h.changedBy && <span className="text-slate-400">· {h.changedBy}</span>}
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
        </TabsContent>
        <TabsContent value="transactions"><TransactionsTab tx={tx} /></TabsContent>
        <TabsContent value="inventory">{tab === "inventory" && <InventoryTab projectId={projectId} tx={tx} />}</TabsContent>
        <TabsContent value="sales"><SalesTab tx={tx} projectId={projectId} /></TabsContent>
        <TabsContent value="costs"><ExpensesTab tx={tx} /></TabsContent>
        <TabsContent value="cash"><CashTab cash={tx.cash} /></TabsContent>
        <TabsContent value="pnl"><PnlStatement rows={tx.pnl} projectId={projectId} /></TabsContent>
        <TabsContent value="budget">{tab === "budget" && <BudgetTab projectId={projectId} />}</TabsContent>
        <TabsContent value="milestones">{tab === "milestones" && <MilestonesTab projectId={projectId} openNew={newMilestone} />}</TabsContent>
      </Tabs>

      <Dialog open={statusOpen} onOpenChange={setStatusOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Change status</DialogTitle>
            <DialogDescription>Kept in the project&apos;s status history. Marking it Completed fills in the actual completion date.</DialogDescription></DialogHeader>
          <div className="space-y-3">
            <Select value={newStatus} onValueChange={setNewStatus}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{PROJECT_STATUSES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
            </Select>
            <div className="space-y-1"><Label>Note (optional)</Label><Input value={statusNote} onChange={(e) => setStatusNote(e.target.value)} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setStatusOpen(false)}>Cancel</Button><Button onClick={changeStatus}>Save</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </ProjectPage>
  )
}

export default function GenericProjectWorkspacePage() {
  return <Suspense fallback={null}><Workspace /></Suspense>
}

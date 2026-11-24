"use client"

// Projects & Contracts register. One company, unlimited projects: searchable,
// filterable and paged so fifty government contracts stay easy to find.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Briefcase, Columns3, Link2, Loader2, Plus, Search } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectStatusBadge } from "@/components/generic/projects/project-status-badge"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { usePermissions } from "@/hooks/use-permissions"
import { listProjects, PROJECT_STATUSES, type ProjectPage as Page } from "@/lib/api/generic-projects"


const PAGE_SIZE = 25

export default function GenericProjectsPage() {
  const router = useRouter()
  const fmt = useFmt()
  const { toast } = useToast()
  const { can } = usePermissions()
  const [search, setSearch] = useState("")
  const [query, setQuery] = useState("")
  const [status, setStatus] = useState("")
  const [kind, setKind] = useState("all")
  const [page, setPage] = useState(1)
  const [data, setData] = useState<Page | null>(null)
  const [loading, setLoading] = useState(true)

  // Search as you type, without a request per keystroke.
  useEffect(() => {
    const t = setTimeout(() => { setQuery(search); setPage(1) }, 300)
    return () => clearTimeout(t)
  }, [search])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      setData(await listProjects({
        search: query || undefined, status: status || undefined,
        kind: kind === "all" ? undefined : kind, page, pageSize: PAGE_SIZE,
      }))
    } catch (e: any) {
      toast({ title: "Could not load projects", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [query, status, kind, page, toast])

  useEffect(() => { void load() }, [load])

  const pages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1
  const canCreate = can("generic.projects.create")

  return (
    <ProjectPage title="Projects & Contracts" icon={<Briefcase className="h-5 w-5" />}
      subtitle="Every job, project and contract in this company — each with its own profit, cash and balances."
      actions={<>
        <Button variant="outline" asChild><Link href="/generic-projects/compare"><Columns3 className="mr-1 h-4 w-4" />Compare</Link></Button>
        <Button variant="outline" asChild><Link href="/generic-projects/link"><Link2 className="mr-1 h-4 w-4" />Link older transactions</Link></Button>
        {canCreate && data?.enabled !== false && (
          <Button asChild><Link href="/generic-projects/new"><Plus className="mr-1 h-4 w-4" />New project</Link></Button>
        )}
      </>}>
      <Card>
        <CardContent className="flex flex-wrap items-center gap-3 p-4">
          <div className="relative min-w-64 flex-1">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input className="pl-8" placeholder="Search name, PRJ number, contract number, organisation…" value={search}
              onChange={(e) => setSearch(e.target.value)} />
          </div>
          <Select value={status || "open"} onValueChange={(v) => { setStatus(v === "open" ? "" : v); setPage(1) }}>
            <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="open">All but archived</SelectItem>
              {PROJECT_STATUSES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
              <SelectItem value="Archived">Archived</SelectItem>
              <SelectItem value="All">Everything</SelectItem>
            </SelectContent>
          </Select>
          <Select value={kind} onValueChange={(v) => { setKind(v); setPage(1) }}>
            <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Projects &amp; contracts</SelectItem>
              <SelectItem value="Project">Projects</SelectItem>
              <SelectItem value="Contract">Contracts</SelectItem>
            </SelectContent>
          </Select>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Number</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Customer / organisation</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Award value</TableHead>
                <TableHead className="text-right">Budget</TableHead>
                <TableHead>Expected completion</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loading && !data ? (
                <TableRow><TableCell colSpan={7} className="py-10 text-center"><Loader2 className="mx-auto h-5 w-5 animate-spin text-slate-400" /></TableCell></TableRow>
              ) : data && data.items.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="py-10 text-center text-sm text-slate-500">
                  {query || status ? "No project matches these filters." : "No projects yet. Create one, then pick it on your purchases, expenses and sales."}
                </TableCell></TableRow>
              ) : data?.items.map((p) => (
                <TableRow key={p.projectId} className="cursor-pointer hover:bg-slate-50" onClick={() => router.push(`/generic-projects/${p.projectId}`)}>
                  <TableCell className="font-medium">
                    {p.projectNumber}
                    {p.externalContractNumber && <div className="text-xs font-normal text-slate-500">{p.externalContractNumber}</div>}
                  </TableCell>
                  <TableCell>
                    <div className="font-medium text-slate-900">{p.name}</div>
                    <div className="text-xs text-slate-500">{p.kind}{p.category ? ` · ${p.category}` : ""}</div>
                  </TableCell>
                  <TableCell>{p.customerName ?? p.contractingOrganization ?? "—"}</TableCell>
                  <TableCell><ProjectStatusBadge status={p.status} /></TableCell>
                  <TableCell className="text-right">{p.awardValue != null ? fmt(p.awardValue) : "—"}</TableCell>
                  <TableCell className="text-right">{p.approvedBudget != null ? fmt(p.approvedBudget) : "—"}</TableCell>
                  <TableCell>{p.expectedEndDate ?? "—"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          {data && data.total > PAGE_SIZE && (
            <div className="flex items-center justify-between border-t p-3 text-sm text-slate-600">
              <span>{data.total} projects · page {page} of {pages}</span>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</Button>
                <Button variant="outline" size="sm" disabled={page >= pages} onClick={() => setPage((p) => p + 1)}>Next</Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </ProjectPage>
  )
}

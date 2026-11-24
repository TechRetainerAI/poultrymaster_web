"use client"

// Compare projects side by side: which contracts make money, which are waiting
// for payment, which are eating cash. The General row and the reconciliation
// line show that nothing is double counted against the company's own books.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { AlertTriangle, ArrowDown, ArrowUp, CheckCircle2, Columns3, Download, Loader2 } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectStatusBadge } from "@/components/generic/projects/project-status-badge"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { compareProjects, reconcileProjects, PROJECT_STATUSES, type ProjectSummary, type ReconcileResult } from "@/lib/api/generic-projects"

type Col = { key: keyof ProjectSummary; label: string; money?: boolean; pct?: boolean }
const COLS: Col[] = [
  { key: "awardValue", label: "Contract value", money: true },
  { key: "revenue", label: "Revenue", money: true },
  { key: "totalCosts", label: "Costs", money: true },
  { key: "netProfit", label: "Profit", money: true },
  { key: "profitMarginPercent", label: "Margin", pct: true },
  { key: "customerCashReceived", label: "Cash received", money: true },
  { key: "cashOut", label: "Cash paid", money: true },
  { key: "receivable", label: "Customer owes", money: true },
  { key: "payable", label: "Owed to suppliers", money: true },
  { key: "budgetVariance", label: "Budget left", money: true },
  { key: "expectedEndDate", label: "Due" },
]

export default function CompareProjectsPage() {
  const fmt = useFmt()
  const { toast } = useToast()
  const { can } = usePermissions()
  const [rows, setRows] = useState<ProjectSummary[] | null>(null)
  const [general, setGeneral] = useState<ProjectSummary | null>(null)
  const [rec, setRec] = useState<ReconcileResult | null>(null)
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [status, setStatus] = useState("open")
  const [sort, setSort] = useState<{ key: keyof ProjectSummary; dir: 1 | -1 }>({ key: "netProfit", dir: -1 })

  const load = useCallback(async () => {
    setRows(null)
    try {
      const r = { fromDate: from || undefined, toDate: to || undefined }
      const [c, x] = await Promise.all([compareProjects(null, r), reconcileProjects(r)])
      setRows(c.projects); setGeneral(c.general); setRec(x)
    } catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }); setRows([]) }
  }, [from, to, toast])
  useEffect(() => { void load() }, [load])

  const shown = useMemo(() => {
    const list = (rows ?? []).filter((r) =>
      status === "all" ? true : status === "open" ? !["Archived", "Cancelled"].includes(r.status ?? "") : r.status === status)
    return [...list].sort((a, b) => {
      const av = a[sort.key] as any, bv = b[sort.key] as any
      if (av == null && bv == null) return 0
      if (av == null) return 1
      if (bv == null) return -1
      return (av > bv ? 1 : av < bv ? -1 : 0) * sort.dir
    })
  }, [rows, status, sort])

  const cell = (r: ProjectSummary, c: Col) => {
    const v = r[c.key] as any
    if (v == null) return "—"
    if (c.pct) return `${v}%`
    if (c.money) return fmt(v)
    return String(v)
  }

  const exportCsv = () => {
    const head = ["Number", "Name", "Status", ...COLS.map((c) => c.label), "Warnings"]
    const lines = shown.map((r) => [r.projectNumber, r.name, r.status, ...COLS.map((c) => (r[c.key] ?? "") as any), (r.warnings ?? []).join("; ")])
    const csv = [head, ...lines].map((l) => l.map((x) => `"${String(x ?? "").replace(/"/g, '""')}"`).join(",")).join("\n")
    const a = document.createElement("a")
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }))
    a.download = `project-comparison${from ? `-${from}` : ""}${to ? `-to-${to}` : ""}.csv`
    a.click()
  }

  return (
    <ProjectPage title="Compare projects" icon={<Columns3 className="h-5 w-5" />} back="/generic-projects"
      subtitle="Profit, cash and balances for every project, from the same records as the company reports."
      actions={can("generic.project-financials.export") && <Button variant="outline" onClick={exportCsv} disabled={!rows?.length}><Download className="mr-1 h-4 w-4" />Export CSV</Button>}>
      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 p-4">
          <div className="space-y-1"><Label>From</Label><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
          <div className="space-y-1"><Label>To</Label><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
          <div className="space-y-1"><Label>Status</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="open">Open (not cancelled/archived)</SelectItem>
                {PROJECT_STATUSES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
                <SelectItem value="Archived">Archived</SelectItem>
                <SelectItem value="all">All</SelectItem>
              </SelectContent>
            </Select></div>
          <p className="pb-2 text-xs text-slate-500">Leave the dates empty for the whole life of each project. Balances are always as of today.</p>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="overflow-x-auto p-0">
          {!rows ? <div className="p-6"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div> : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Project</TableHead>
                  {COLS.map((c) => (
                    <TableHead key={c.key} className="cursor-pointer whitespace-nowrap text-right select-none"
                      onClick={() => setSort((s) => ({ key: c.key, dir: s.key === c.key ? (s.dir === 1 ? -1 : 1) : -1 }))}>
                      {c.label}{sort.key === c.key && (sort.dir === 1 ? <ArrowUp className="ml-1 inline h-3 w-3" /> : <ArrowDown className="ml-1 inline h-3 w-3" />)}
                    </TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {shown.length === 0 && <TableRow><TableCell colSpan={COLS.length + 1} className="py-8 text-center text-sm text-slate-500">No projects to compare.</TableCell></TableRow>}
                {shown.map((r) => (
                  <TableRow key={r.projectId}>
                    <TableCell className="min-w-56">
                      <Link className="font-medium text-indigo-700 hover:underline" href={`/generic-projects/${r.projectId}`}>{r.projectNumber} — {r.name}</Link>
                      <div className="mt-0.5 flex flex-wrap items-center gap-1"><ProjectStatusBadge status={r.status} />
                        {(r.warnings ?? []).map((w) => <span key={w} className="flex items-center gap-1 text-[11px] text-amber-700"><AlertTriangle className="h-3 w-3" />{w}</span>)}</div>
                    </TableCell>
                    {COLS.map((c) => (
                      <TableCell key={c.key} className={`whitespace-nowrap text-right tabular-nums ${
                        (c.key === "netProfit" || c.key === "budgetVariance") && Number(r[c.key]) < 0 ? "text-rose-700" : ""}`}>{cell(r, c)}</TableCell>
                    ))}
                  </TableRow>
                ))}
                {general && (
                  <TableRow className="bg-slate-50 text-slate-600">
                    <TableCell className="font-medium">General company activity<div className="text-[11px] font-normal">Not assigned to any project</div></TableCell>
                    {COLS.map((c) => <TableCell key={c.key} className="text-right tabular-nums">{c.key === "awardValue" || c.key === "budgetVariance" || c.key === "expectedEndDate" ? "" : cell(general, c)}</TableCell>)}
                  </TableRow>
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {rec && (
        <div className={`flex items-start gap-2 rounded-lg border p-3 text-sm ${rec.balanced ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-rose-200 bg-rose-50 text-rose-900"}`}>
          {rec.balanced ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" /> : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />}
          <span>
            {rec.balanced
              ? "Projects plus General company activity add up exactly to the company's Profit & Loss and cash ledger for this period — nothing is counted twice."
              : "Projects plus General do not add up to the company totals for this period. Please report this — the figures above should not be relied on until it is fixed."}
            {" "}Company cash movement: {fmt(rec.cash.company)} = projects {fmt(rec.cash.projects)} + General {fmt(rec.cash.general)}.
          </span>
        </div>
      )}
    </ProjectPage>
  )
}

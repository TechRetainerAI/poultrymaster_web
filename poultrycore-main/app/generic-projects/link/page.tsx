"use client"

// Link transactions recorded BEFORE a project existed. Nothing is re-posted:
// the transactions stay exactly as they are and company totals do not move;
// they are only labelled with the project, and each link is kept in history.

import { useCallback, useEffect, useMemo, useState } from "react"
import { Link2, Loader2, Search } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectPicker } from "@/components/generic/projects/project-picker"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { projectIdFromQuery } from "@/lib/generic/project-math"
import {
  getLinkCandidates, linkDocuments, previewLink, type LinkCandidate, type LinkDocumentType,
} from "@/lib/api/generic-projects"

const TYPES: { value: LinkDocumentType; label: string }[] = [
  { value: "Sale", label: "Sales" }, { value: "Purchase", label: "Purchases" }, { value: "Expense", label: "Expenses" },
  { value: "OwnerEntry", label: "Owner money" }, { value: "Loan", label: "Loans" }, { value: "PayrollRun", label: "Payroll runs" },
  { value: "CapitalAsset", label: "Capital assets" },
]

export default function LinkOlderTransactionsPage() {
  const fmt = useFmt()
  const { toast } = useToast()
  const { can } = usePermissions()
  const [projectId, setProjectId] = useState<number | null>(null)
  const [type, setType] = useState<LinkDocumentType>("Sale")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [search, setSearch] = useState("")
  const [onlyUnassigned, setOnlyUnassigned] = useState(true)
  const [rows, setRows] = useState<LinkCandidate[] | null>(null)
  const [picked, setPicked] = useState<Set<number>>(new Set())
  const [preview, setPreview] = useState<Awaited<ReturnType<typeof previewLink>> | null>(null)
  const [reason, setReason] = useState("")
  const [busy, setBusy] = useState(false)

  useEffect(() => { setProjectId(projectIdFromQuery(window.location.search)) }, [])

  const load = useCallback(async () => {
    setRows(null); setPicked(new Set())
    try {
      setRows(await getLinkCandidates({ documentType: type, fromDate: from || undefined, toDate: to || undefined, search: search || undefined, onlyUnassigned }))
    } catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }); setRows([]) }
  }, [type, from, to, search, onlyUnassigned, toast])
  useEffect(() => { const t = setTimeout(() => void load(), 250); return () => clearTimeout(t) }, [load])

  const items = useMemo(() => [...picked].map((documentId) => ({ documentType: type, documentId })), [picked, type])
  const total = useMemo(() => (rows ?? []).filter((r) => picked.has(r.documentId)).reduce((a, r) => a + r.amount, 0), [rows, picked])

  const doPreview = async () => {
    if (!projectId) return
    try { setPreview(await previewLink(projectId, items)) } catch (e: any) { toast({ title: "Could not preview", description: e?.message, variant: "destructive" }) }
  }
  const apply = async () => {
    if (!projectId) return
    setBusy(true)
    try {
      const r = await linkDocuments(projectId, items, reason || undefined)
      toast({ title: `${r.linked} linked`, description: "Company totals are unchanged; the project now includes them." })
      setPreview(null); setReason(""); await load()
    } catch (e: any) { toast({ title: "Could not link", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  const canLink = can("generic.project-allocations.edit")

  return (
    <ProjectPage title="Link older transactions" icon={<Link2 className="h-5 w-5" />} back="/generic-projects"
      subtitle="Attach sales, purchases, expenses and owner money recorded before the project was set up. Nothing is recorded again.">
      <Card>
        <CardContent className="grid gap-3 p-4 md:grid-cols-6">
          <div className="space-y-1 md:col-span-2"><Label>Link to project</Label><ProjectPicker value={projectId} onChange={setProjectId} includeClosed allowGeneral={false} placeholder="Choose a project" /></div>
          <div className="space-y-1"><Label>Kind</Label>
            <Select value={type} onValueChange={(v) => setType(v as LinkDocumentType)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
            </Select></div>
          <div className="space-y-1"><Label>From</Label><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
          <div className="space-y-1"><Label>To</Label><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
          <div className="space-y-1"><Label>Search</Label>
            <div className="relative"><Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" /><Input className="pl-8" value={search} onChange={(e) => setSearch(e.target.value)} /></div></div>
          <label className="flex items-center gap-2 text-sm text-slate-600 md:col-span-6">
            <Switch checked={onlyUnassigned} onCheckedChange={setOnlyUnassigned} /> Only transactions not yet on any project
          </label>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0">
          <CardTitle className="text-base">{picked.size} selected · {fmt(total)}</CardTitle>
          <Button disabled={!projectId || picked.size === 0 || !canLink} onClick={doPreview}>Preview &amp; link</Button>
        </CardHeader>
        <CardContent className="p-0">
          {!rows ? <div className="p-6"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div> : (
            <Table>
              <TableHeader><TableRow>
                <TableHead className="w-10"><Checkbox checked={rows.length > 0 && picked.size === rows.length}
                  onCheckedChange={(v) => setPicked(v ? new Set(rows.map((r) => r.documentId)) : new Set())} /></TableHead>
                <TableHead>Date</TableHead><TableHead>Reference</TableHead><TableHead>Party</TableHead><TableHead>Detail</TableHead>
                <TableHead>Status</TableHead><TableHead>Current project</TableHead><TableHead className="text-right">Amount</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {rows.length === 0 && <TableRow><TableCell colSpan={8} className="py-8 text-center text-sm text-slate-500">Nothing found.</TableCell></TableRow>}
                {rows.map((r) => (
                  <TableRow key={r.documentId}>
                    <TableCell><Checkbox checked={picked.has(r.documentId)} onCheckedChange={(v) => setPicked((s) => {
                      const n = new Set(s); if (v) n.add(r.documentId); else n.delete(r.documentId); return n })} /></TableCell>
                    <TableCell>{r.date}</TableCell><TableCell className="font-medium">{r.ref}</TableCell><TableCell>{r.party ?? "—"}</TableCell>
                    <TableCell className="max-w-xs truncate text-slate-500">{r.detail}</TableCell><TableCell>{r.status}</TableCell>
                    <TableCell className="text-xs">{r.projects.length ? r.projects.map((p) => p.label).join(", ") : <span className="text-slate-400">General</span>}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmt(r.amount)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!preview} onOpenChange={(v) => !v && setPreview(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Link {picked.size} transaction(s) to {preview?.before?.projectNumber} — {preview?.before?.name}?</DialogTitle>
            <DialogDescription>{preview?.note}</DialogDescription>
          </DialogHeader>
          {preview && (
            <div className="space-y-2 text-sm">
              <div className="grid grid-cols-3 gap-2 rounded-md bg-slate-50 p-3">
                <div className="text-slate-500" />
                <div className="text-right text-slate-500">Now</div>
                <div className="text-right text-slate-500">After linking</div>
                <div>Revenue</div><div className="text-right">{fmt(preview.before.revenue)}</div><div className="text-right font-medium">{fmt(preview.before.revenue + preview.adds.revenue)}</div>
                <div>Costs</div><div className="text-right">{fmt(preview.before.totalCosts)}</div><div className="text-right font-medium">{fmt(preview.before.totalCosts + preview.adds.costs)}</div>
                <div>Owner funding</div><div className="text-right">{fmt(preview.before.netOwnerFunding)}</div><div className="text-right font-medium">{fmt(preview.before.netOwnerFunding + preview.adds.ownerFunding)}</div>
                <div>Purchases</div><div className="text-right">{fmt(preview.before.purchaseValue)}</div><div className="text-right font-medium">{fmt(preview.before.purchaseValue + preview.adds.purchaseValue)}</div>
              </div>
              <div className="space-y-1"><Label>Reason (kept in history)</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Linked older transaction" /></div>
            </div>
          )}
          <DialogFooter><Button variant="outline" onClick={() => setPreview(null)}>Cancel</Button><Button onClick={apply} disabled={busy}>{busy ? "Linking…" : "Link"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </ProjectPage>
  )
}

"use client"

// Create / edit a project or contract. Only the name is required -- a busy
// owner can open a project in five seconds and fill in the contract details
// later. The contract award value is a PLAN: it never becomes revenue.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Loader2, Plus, Save } from "lucide-react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { invalidateProjectOptions } from "@/hooks/use-generic-projects"
import { getCustomers, getStaff, type GenericCustomer, type GenericStaff } from "@/lib/api/generic"
import {
  createProject, updateProject, listProjects, PROJECT_STATUSES, type GenericProject, type ProjectInput,
} from "@/lib/api/generic-projects"

type Form = Record<string, string>

// General contract categories offered in the picker. Categories the company has
// already used on other projects are added to the list, and they can type their own.
const DEFAULT_CONTRACT_CATEGORIES = [
  "Supply", "Construction", "Service", "Consultancy", "Maintenance & Repairs",
  "Installation", "Transport & Logistics", "Cleaning & Facility Management", "Security",
  "IT & Software", "Training", "Catering", "Printing & Branding", "Events",
  "Renovation", "Engineering", "Design", "Rental & Leasing", "Agriculture", "Other",
]

const TEXT_FIELDS = [
  "name", "kind", "status", "description", "startDate", "expectedEndDate", "actualEndDate", "notes",
  "externalContractNumber", "contractReference", "contractingOrganization", "awardDate",
  "category", "location",
] as const
const NUM_FIELDS = ["awardValue", "approvedBudget", "estimatedDirectCost", "estimatedOverhead", "workingCapitalNeeded"] as const
const ID_FIELDS = ["customerId", "managerStaffId"] as const

function toForm(p?: GenericProject | null): Form {
  const f: Form = { kind: "Project", status: "Active" }
  if (!p) return f
  for (const k of [...TEXT_FIELDS, ...NUM_FIELDS, ...ID_FIELDS]) {
    const v = (p as any)[k]
    if (v !== null && v !== undefined) f[k] = String(v).slice(0, k.toLowerCase().includes("date") ? 10 : undefined)
  }
  return f
}

function toInput(f: Form): ProjectInput {
  const out: any = {}
  for (const k of TEXT_FIELDS) out[k] = f[k]?.trim() ? f[k].trim() : null
  for (const k of NUM_FIELDS) out[k] = f[k] !== undefined && f[k] !== "" ? Number(f[k]) : null
  for (const k of ID_FIELDS) out[k] = f[k] && f[k] !== "none" ? Number(f[k]) : null
  return out
}

export function ProjectForm({ project }: { project?: GenericProject | null }) {
  const router = useRouter()
  const { toast } = useToast()
  const [f, setF] = useState<Form>(() => toForm(project))
  const [saving, setSaving] = useState(false)
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [usedCategories, setUsedCategories] = useState<string[]>([])
  const [newCategory, setNewCategory] = useState("")

  useEffect(() => { setF(toForm(project)) }, [project])
  useEffect(() => {
    getCustomers().then(setCustomers).catch(() => {})
    getStaff().then(setStaff).catch(() => {})
    listProjects({ pageSize: 200 })
      .then((pg) => setUsedCategories(pg.items.map((p) => p.category?.trim() ?? "").filter(Boolean)))
      .catch(() => {})
  }, [])

  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }))
  const num = (k: string) => (e: any) => set(k, String(e?.target?.value ?? ""))
  const isContract = f.kind === "Contract"
  const award = Number(f.awardValue || 0)
  const expectedProfit = award ? award - Number(f.estimatedDirectCost || 0) - Number(f.estimatedOverhead || 0) : null

  const save = async () => {
    if (!f.name?.trim()) { toast({ title: "Give the project a name", variant: "destructive" }); return }
    setSaving(true)
    try {
      const saved = project ? await updateProject(project.projectId, toInput(f)) : await createProject(toInput(f))
      invalidateProjectOptions()
      toast({ title: project ? "Project saved" : `${saved.projectNumber} created` })
      router.push(`/generic-projects/${saved.projectId}`)
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const field = (k: string, label: string, opts: { type?: string; placeholder?: string; hint?: string } = {}) => (
    <div className="space-y-1">
      <Label htmlFor={k}>{label}</Label>
      <Input id={k} type={opts.type ?? "text"} value={f[k] ?? ""} placeholder={opts.placeholder} onChange={(e) => set(k, e.target.value)} />
      {opts.hint && <p className="text-xs text-slate-500">{opts.hint}</p>}
    </div>
  )
  // Common categories first, then this company's own; no name listed twice.
  const categoryOptions = (() => {
    const seen = new Set<string>()
    const out: string[] = []
    for (const c of [...DEFAULT_CONTRACT_CATEGORIES, ...usedCategories, f.category?.trim() ?? ""]) {
      if (c && !seen.has(c.toLowerCase())) { seen.add(c.toLowerCase()); out.push(c) }
    }
    return out
  })()
  const money = (k: string, label: string, hint?: string) => (
    <div className="space-y-1">
      <Label htmlFor={k}>{label}</Label>
      <NumberInput id={k} min={0} value={f[k] ?? ""} onChange={num(k)} />
      {hint && <p className="text-xs text-slate-500">{hint}</p>}
    </div>
  )

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Basic information</CardTitle>
          <CardDescription>Only the name is needed now. Everything else can be added later.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2">
          {field("name", "Project / contract name *", { placeholder: "e.g. Supply of Computers" })}
          <div className="space-y-1">
            <Label>Type</Label>
            <Select value={f.kind} onValueChange={(v) => set("kind", v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Project">Project</SelectItem>
                <SelectItem value="Contract">Contract</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Customer / client</Label>
            <Select value={f.customerId ?? "none"} onValueChange={(v) => set("customerId", v)}>
              <SelectTrigger><SelectValue placeholder="None" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">None</SelectItem>
                {customers.map((c) => <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>{c.customerName}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Status</Label>
            <Select value={f.status} onValueChange={(v) => set("status", v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PROJECT_STATUSES.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Project manager / responsible person</Label>
            <Select value={f.managerStaffId ?? "none"} onValueChange={(v) => set("managerStaffId", v)}>
              <SelectTrigger><SelectValue placeholder="None" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">None</SelectItem>
                {staff.map((s) => <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>{`${s.firstName} ${s.lastName}`.trim()}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          {field("startDate", "Start date", { type: "date" })}
          {field("expectedEndDate", "Expected completion", { type: "date" })}
          {project && field("actualEndDate", "Actual completion", { type: "date", hint: "Filled in automatically when you mark it Completed." })}
          <div className="space-y-1 md:col-span-2">
            <Label htmlFor="description">Description</Label>
            <Textarea id="description" rows={2} value={f.description ?? ""} onChange={(e) => set("description", e.target.value)} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Contract information</CardTitle>
          <CardDescription>
            {isContract ? "The details of the award." : "Optional for a project; use it if the job comes with a contract."}
            {" "}The award value is what the contract is worth — it is <b>not</b> revenue. Revenue is earned only when you record sales.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2">
          {field("externalContractNumber", "Government / client contract number", { hint: "Separate from the project number (PRJ-…) given automatically." })}
          {field("contractReference", "Contract reference")}
          {field("contractingOrganization", "Contracting organisation", { placeholder: "e.g. Ministry of Education" })}
          {field("awardDate", "Award date", { type: "date" })}
          {money("awardValue", "Contract award value")}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Financial planning</CardTitle>
          <CardDescription>Plans only — nothing here is posted. Set a detailed budget on the project&apos;s Budget tab.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2">
          {money("approvedBudget", "Approved budget (costs)")}
          {money("workingCapitalNeeded", "Working capital needed to start")}
          {money("estimatedDirectCost", "Estimated direct cost")}
          {money("estimatedOverhead", "Estimated overhead")}
          <div className="rounded-md bg-slate-50 p-3 text-sm md:col-span-2">
            Expected profit: <b>{expectedProfit == null ? "—" : expectedProfit.toLocaleString()}</b>
            {expectedProfit != null && award > 0 && <> · expected margin <b>{((expectedProfit / award) * 100).toFixed(1)}%</b></>}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-base">Organisation (optional)</CardTitle></CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2">
          <div className="space-y-1">
            <Label>Contract category</Label>
            <Select value={f.category?.trim() || "none"} onValueChange={(v) => set("category", v === "none" ? "" : v)}>
              <SelectTrigger><SelectValue placeholder="e.g. Supply, Construction, Service" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">— No category —</SelectItem>
                {categoryOptions.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
              </SelectContent>
            </Select>
            <div className="flex gap-1.5">
              <Input className="h-8 text-xs" placeholder="New category name" maxLength={100} value={newCategory} onChange={(e) => setNewCategory(e.target.value)} />
              <Button type="button" size="sm" variant="outline" className="h-8 shrink-0 text-xs" disabled={!newCategory.trim()} onClick={() => {
                const name = newCategory.trim()
                setUsedCategories((prev) => [...prev, name])
                set("category", name)
                setNewCategory("")
              }}>
                <Plus className="h-3 w-3 mr-1" /> Add
              </Button>
            </div>
          </div>
          {field("location", "Location / site")}
          <div className="space-y-1 md:col-span-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea id="notes" rows={3} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value)} />
          </div>
        </CardContent>
      </Card>

      <div className="flex justify-end gap-2">
        <Button variant="outline" onClick={() => router.back()}>Cancel</Button>
        <Button onClick={save} disabled={saving}>
          {saving ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Save className="mr-1 h-4 w-4" />}
          {project ? "Save changes" : "Create"}
        </Button>
      </div>
    </div>
  )
}

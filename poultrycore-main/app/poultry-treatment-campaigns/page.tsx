"use client"

// Treatment Campaigns (migration 339): one medication, vaccine or treatment
// given to many flocks over one or more days.
//
// Recording a day adds a medication line to each flock's production record for
// that day, through the same update an individual edit uses — so stock (FIFO /
// LIFO / HIFO), costing and the consumption expense come out exactly as if
// each flock had been edited by hand. Creating a campaign moves nothing; only a
// recorded day does.
//
// The software records treatment, it does not prescribe it. No dose, duration
// or withdrawal period is built in: they are the farm's own figures, typed on
// the campaign or saved for the product. Suggested quantities are plain
// arithmetic on that figure, for review; Actual is what posts.
//
// Views: list (no ?id), new campaign (?new=1), one campaign (?id=).

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import {
  AlertTriangle, ArrowLeft, CheckCircle2, ChevronDown, ChevronUp, Loader2, Lock, Pill, Plus, RotateCcw, XCircle,
} from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useBusinessDate } from "@/hooks/use-business-date"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { useFmt } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { ReasonDialog } from "@/components/closing/daily-closing-dialogs"
import {
  InsufficientMedicationError,
  cancelTreatmentCampaign,
  completeTreatmentCampaign,
  createTreatmentCampaign,
  getTreatmentCampaign,
  getTreatmentDayGrid,
  getTreatmentDayLines,
  listMedicationProducts,
  listTreatmentCampaignFlocks,
  listTreatmentCampaigns,
  listTreatmentDays,
  listTreatmentFlockOptions,
  postTreatmentDay,
  reverseTreatmentDay,
  type MedicationProduct,
  type TreatmentCampaign,
  type TreatmentCampaignFlock,
  type TreatmentDayLine,
  type TreatmentDayPosting,
  type TreatmentFlockOption,
} from "@/lib/api/treatment-campaigns"
import {
  DOSE_BASES,
  dayPostBlocker,
  dayRowState,
  dayTotals,
  daysInclusive,
  describeDose,
  fmtQty,
  isDoseBasis,
  parseQty,
  recordableDays,
  statusLabel,
  statusStyle,
  suggestQuantity,
  type DoseBasis,
  type TreatmentDayRow,
} from "@/lib/production/treatment-campaigns"

const PAGE = "/poultry-treatment-campaigns"

function Shell({ children }: { children: React.ReactNode }) {
  const logout = useLogout()
  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">{children}</div>
        </main>
      </div>
    </div>
  )
}

function Title({ title, sub, back }: { title: string; sub: string; back?: boolean }) {
  return (
    <div className="flex items-start gap-3">
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-violet-100">
        <Pill className="h-5 w-5 text-violet-700" />
      </div>
      <div className="min-w-0">
        {back && (
          <Link href={PAGE} className="mb-1 inline-flex items-center gap-1 text-xs text-slate-500 hover:text-slate-800">
            <ArrowLeft className="h-3.5 w-3.5" /> All campaigns
          </Link>
        )}
        <h1 className="text-2xl font-bold text-slate-900">{title}</h1>
        <p className="text-sm text-slate-600">{sub}</p>
      </div>
    </div>
  )
}

function StatusBadge({ status }: { status: string }) {
  return <span className={cn("rounded-full border px-2 py-0.5 text-xs", statusStyle(status))}>{statusLabel(status)}</span>
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "bad" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("font-semibold tabular-nums", tone === "bad" ? "text-rose-700" : "text-slate-900")}>{value}</div>
    </div>
  )
}

const errText = (e: unknown) => (e instanceof Error ? e.message : "")

// =============================================================================
// List
// =============================================================================

function CampaignList() {
  const { toast } = useToast()
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [rows, setRows] = useState<TreatmentCampaign[] | null>(null)
  const [tab, setTab] = useState<"active" | "all">("active")

  useEffect(() => {
    if (!activeFarmId) return
    listTreatmentCampaigns()
      .then(setRows)
      .catch((e) => { setRows([]); toast({ title: "Could not load campaigns", description: errText(e), variant: "destructive" }) })
  }, [activeFarmId, toast])

  const shown = (rows ?? []).filter((c) => tab === "all" || c.status === "Scheduled" || c.status === "InProgress")

  return (
    <>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <Title title="Treatment Campaigns"
          sub="Give one medication or vaccine to many flocks, over one day or several. Each day you record lands on each flock's production record, exactly as if entered one by one." />
        <Button asChild className="bg-violet-600 text-white hover:bg-violet-700">
          <Link href={`${PAGE}?new=1`}><Plus className="mr-1.5 h-4 w-4" /> New campaign</Link>
        </Button>
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as "active" | "all")}>
        <TabsList>
          <TabsTrigger value="active">Scheduled &amp; in progress</TabsTrigger>
          <TabsTrigger value="all">All</TabsTrigger>
        </TabsList>
      </Tabs>

      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="p-0">
          {!rows ? (
            <p className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
          ) : shown.length === 0 ? (
            <p className="p-4 text-sm text-slate-500">
              {tab === "active" ? "No campaign is scheduled or running." : "No treatment campaigns yet."}{" "}
              <Link href={`${PAGE}?new=1`} className="text-violet-700 underline">Start one</Link>.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[46rem] text-sm">
                <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                  <tr>
                    <th className="px-3 py-2 font-medium">Campaign</th>
                    <th className="px-3 py-2 font-medium">Product</th>
                    <th className="px-3 py-2 font-medium">Dates</th>
                    <th className="px-3 py-2 text-right font-medium">Flocks</th>
                    <th className="px-3 py-2 text-right font-medium">Days recorded</th>
                    <th className="px-3 py-2 font-medium">Withdrawal</th>
                    <th className="px-3 py-2 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {shown.map((c) => (
                    <tr key={c.poultryTreatmentCampaignId} className="hover:bg-slate-50">
                      <td className="px-3 py-2">
                        <Link href={`${PAGE}?id=${c.poultryTreatmentCampaignId}`} className="font-medium text-violet-700 hover:underline">{c.name}</Link>
                        {c.reason && <div className="text-xs text-slate-500">{c.reason}</div>}
                      </td>
                      <td className="px-3 py-2">{c.itemName ?? "—"}</td>
                      <td className="px-3 py-2 whitespace-nowrap">
                        {formatLongDate(c.startDate.slice(0, 10))}
                        {c.plannedDays > 1 && <> – {formatLongDate(c.endDate.slice(0, 10))}</>}
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums">{c.flockCount}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{c.postedDays} of {c.plannedDays}</td>
                      <td className="px-3 py-2 text-xs">
                        {c.eggWithdrawalUntil ? `Eggs until ${formatLongDate(c.eggWithdrawalUntil.slice(0, 10))}` : ""}
                        {c.eggWithdrawalUntil && c.meatWithdrawalUntil ? " · " : ""}
                        {c.meatWithdrawalUntil ? `Meat until ${formatLongDate(c.meatWithdrawalUntil.slice(0, 10))}` : ""}
                        {!c.eggWithdrawalUntil && !c.meatWithdrawalUntil && <span className="text-slate-400">—</span>}
                      </td>
                      <td className="px-3 py-2"><StatusBadge status={c.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </>
  )
}

// =============================================================================
// New campaign
// =============================================================================

function NewCampaign() {
  const router = useRouter()
  const { toast } = useToast()
  const { businessDate: today } = useBusinessDate()
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [products, setProducts] = useState<MedicationProduct[] | null>(null)
  const [flocks, setFlocks] = useState<TreatmentFlockOption[] | null>(null)
  const [name, setName] = useState("")
  const [itemId, setItemId] = useState<number | null>(null)
  const [reason, setReason] = useState("")
  const [start, setStart] = useState(today)
  const [end, setEnd] = useState(today)
  const [instructions, setInstructions] = useState("")
  const [doseText, setDoseText] = useState("")
  const [basis, setBasis] = useState<DoseBasis | "">("")
  // Whether the dose figures are the product's saved ones, untouched.
  const [fromProduct, setFromProduct] = useState(false)
  const [eggText, setEggText] = useState("")
  const [meatText, setMeatText] = useState("")
  const [withdrawalNotes, setWithdrawalNotes] = useState("")
  const [notes, setNotes] = useState("")
  const [saveDefault, setSaveDefault] = useState(false)
  const [picked, setPicked] = useState<Record<number, boolean>>({})
  const [flockDose, setFlockDose] = useState<Record<number, string>>({})
  const [flockNotes, setFlockNotes] = useState<Record<number, string>>({})
  const [saving, setSaving] = useState(false)

  useEffect(() => { setStart(today); setEnd(today) }, [today])

  useEffect(() => {
    if (!activeFarmId) return
    listMedicationProducts().then((p) => setProducts(p.filter((x) => x.isActive))).catch(() => setProducts([]))
    listTreatmentFlockOptions().then(setFlocks).catch(() => setFlocks([]))
  }, [activeFarmId])

  const product = products?.find((p) => p.poultryRawMaterialItemId === itemId) ?? null
  const unit = product?.unitOfMeasure ?? ""

  // Choosing a product brings in the farm's OWN saved figures for it — or
  // nothing, if none were ever saved. Nothing is assumed.
  const chooseProduct = (id: number) => {
    setItemId(id)
    const p = products?.find((x) => x.poultryRawMaterialItemId === id)
    setDoseText(p?.doseQuantity != null ? String(p.doseQuantity) : "")
    setBasis(p?.doseBasis && isDoseBasis(p.doseBasis) ? p.doseBasis : "")
    setFromProduct(p?.doseQuantity != null)
    setEggText(p?.eggWithdrawalDays != null ? String(p.eggWithdrawalDays) : "")
    setMeatText(p?.meatWithdrawalDays != null ? String(p.meatWithdrawalDays) : "")
    setWithdrawalNotes(p?.withdrawalNotes ?? "")
    setSaveDefault(false)
  }

  const dose = parseQty(doseText)
  const days = daysInclusive(start, end)
  const selected = (flocks ?? []).filter((f) => picked[f.flockId])
  const perDay = selected.reduce((s, f) => {
    const own = parseQty(flockDose[f.flockId] ?? "")
    return s + (suggestQuantity(own ?? dose, basis || null, f.birds) ?? 0)
  }, 0)
  const anySuggestion = selected.some((f) => suggestQuantity(parseQty(flockDose[f.flockId] ?? "") ?? dose, basis || null, f.birds) != null)
  const planTotal = perDay * days
  const intDays = (t: string) => (t.trim() === "" ? null : Number.isInteger(Number(t)) && Number(t) >= 0 ? Number(t) : NaN)
  const egg = intDays(eggText)
  const meat = intDays(meatText)

  const problem =
    !name.trim() ? "Give the campaign a name."
    : !itemId ? "Choose the medication product."
    : days === 0 ? "The end date is before the start date."
    : days > 366 ? "A campaign can run for at most a year."
    : (doseText.trim() !== "" && dose == null) || (dose != null && dose <= 0) ? "The dose must be a number above 0."
    : dose == null || basis === "" ? "A dose needs both an amount and what it is per (per bird, per 1,000 birds or per flock)."
    : Number.isNaN(egg) || Number.isNaN(meat) ? "Withdrawal days must be whole numbers."
    : selected.length === 0 ? "Choose at least one flock."
    : selected.some((f) => (flockDose[f.flockId] ?? "").trim() !== "" && !(parseQty(flockDose[f.flockId]) ?? 0)) ? "A flock's own dose must be a number above 0."
    : null

  const save = async () => {
    if (problem || !itemId) return
    setSaving(true)
    try {
      const { poultryTreatmentCampaignId } = await createTreatmentCampaign({
        name: name.trim(),
        itemId,
        reason: reason.trim() || null,
        startDate: start,
        endDate: end,
        doseInstructions: instructions.trim() || null,
        doseQuantity: dose,
        doseBasis: basis || null,
        doseSource: fromProduct ? "Product" : "User",
        eggWithdrawalDays: egg as number | null,
        meatWithdrawalDays: meat as number | null,
        withdrawalNotes: withdrawalNotes.trim() || null,
        notes: notes.trim() || null,
        saveAsProductDefault: saveDefault,
        flocks: selected.map((f) => ({
          flockId: f.flockId,
          doseQuantity: parseQty(flockDose[f.flockId] ?? ""),
          notes: flockNotes[f.flockId]?.trim() || null,
        })),
      })
      toast({ title: "Campaign created", description: "Nothing has left stock yet — record each day's treatment as it is given." })
      router.push(`${PAGE}?id=${poultryTreatmentCampaignId}`)
    } catch (e) {
      toast({ title: "Not created", description: errText(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const allPicked = !!flocks?.length && flocks.every((f) => picked[f.flockId])

  return (
    <>
      <Title back title="New treatment campaign"
        sub="Plan a treatment for several flocks. Creating it moves no stock — each day is recorded separately, when it is given." />

      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-1 sm:col-span-2">
            <Label htmlFor="tc-name" className="text-xs text-slate-500">Campaign name</Label>
            <Input id="tc-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Coccidiosis — Houses 2 to 4" />
          </div>
          <div className="space-y-1 sm:col-span-2">
            <Label className="text-xs text-slate-500">Medication / product</Label>
            <Select value={itemId ? String(itemId) : ""} onValueChange={(v) => chooseProduct(Number(v))}>
              <SelectTrigger>
                <SelectValue placeholder={products === null ? "Loading…" : products.length ? "Choose a product" : "No medication items in Raw Materials"} />
              </SelectTrigger>
              <SelectContent>
                {(products ?? []).map((p) => (
                  <SelectItem key={p.poultryRawMaterialItemId} value={String(p.poultryRawMaterialItemId)}>
                    {p.itemName} — {fmtQty(p.availableQuantity, p.unitOfMeasure)} in stock
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1 sm:col-span-2">
            <Label htmlFor="tc-reason" className="text-xs text-slate-500">Reason</Label>
            <Input id="tc-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Vet diagnosis, routine vaccination" />
          </div>
          <div className="space-y-1">
            <Label htmlFor="tc-start" className="text-xs text-slate-500">Start date</Label>
            <Input id="tc-start" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end < e.target.value) setEnd(e.target.value) }} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="tc-end" className="text-xs text-slate-500">End date</Label>
            <Input id="tc-end" type="date" value={end} min={start} onChange={(e) => setEnd(e.target.value)} />
            <p className="text-xs text-slate-500">{days > 0 ? `${days} day${days === 1 ? "" : "s"}` : "—"}</p>
          </div>

          <div className="space-y-1 sm:col-span-2 lg:col-span-4">
            <Label htmlFor="tc-instr" className="text-xs text-slate-500">Dose / usage information (as on the label or from the vet)</Label>
            <Textarea id="tc-instr" rows={2} value={instructions} onChange={(e) => setInstructions(e.target.value)}
              placeholder="e.g. 1 ml per litre of drinking water for 5 days" />
          </div>

          <div className="space-y-1">
            <Label htmlFor="tc-dose" className="text-xs text-slate-500">Dose amount{unit ? ` (${unit})` : ""}</Label>
            <Input id="tc-dose" type="number" min={0} step="any" value={doseText}
              onChange={(e) => { setDoseText(e.target.value); setFromProduct(false) }} />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-slate-500">Per</Label>
            <Select value={basis} onValueChange={(v) => { setBasis(isDoseBasis(v) ? v : ""); setFromProduct(false) }}>
              <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
              <SelectContent>
                {DOSE_BASES.map((b) => <SelectItem key={b.key} value={b.key}>{b.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="tc-egg" className="text-xs text-slate-500">Egg withdrawal (days)</Label>
            <Input id="tc-egg" type="number" min={0} step={1} value={eggText} onChange={(e) => setEggText(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="tc-meat" className="text-xs text-slate-500">Meat withdrawal (days)</Label>
            <Input id="tc-meat" type="number" min={0} step={1} value={meatText} onChange={(e) => setMeatText(e.target.value)} />
          </div>
          <p className="text-xs text-slate-500 sm:col-span-2 lg:col-span-4">
            {product && fromProduct
              ? `Dose and withdrawal filled from your saved settings for ${product.itemName}. Change them for this campaign if needed.`
              : "Enter the dose from the product label or your vet's instructions — the system has no built-in doses or withdrawal periods."}
          </p>
          <div className="space-y-1 sm:col-span-2">
            <Label htmlFor="tc-wnotes" className="text-xs text-slate-500">Withdrawal notes</Label>
            <Input id="tc-wnotes" value={withdrawalNotes} onChange={(e) => setWithdrawalNotes(e.target.value)} placeholder="e.g. Per label, eggs discarded" />
          </div>
          <div className="space-y-1 sm:col-span-2">
            <Label htmlFor="tc-notes" className="text-xs text-slate-500">Notes</Label>
            <Input id="tc-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          {product && (
            <label className="flex items-center gap-2 text-sm text-slate-700 sm:col-span-2 lg:col-span-4">
              <Checkbox checked={saveDefault} onCheckedChange={(v) => setSaveDefault(v === true)} />
              Save this dose and withdrawal as {product.itemName}&apos;s default for future campaigns
            </label>
          )}
        </CardContent>
      </Card>

      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="p-0">
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-3 py-2">
            <p className="text-sm font-medium text-slate-800">Flocks ({selected.length} selected)</p>
            <p className="text-xs text-slate-500">Open flocks only. Give a flock its own dose only when it differs from the campaign&apos;s.</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[46rem] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                <tr>
                  <th className="w-10 px-3 py-2">
                    <Checkbox checked={allPicked} aria-label="Select all flocks"
                      onCheckedChange={(v) => setPicked(v === true ? Object.fromEntries((flocks ?? []).map((f) => [f.flockId, true])) : {})} />
                  </th>
                  <th className="px-3 py-2 font-medium">Flock</th>
                  <th className="px-3 py-2 font-medium">House/Pen</th>
                  <th className="px-3 py-2 text-right font-medium">Bird count</th>
                  <th className="px-3 py-2 font-medium">Own dose{unit ? ` (${unit})` : ""}</th>
                  <th className="px-3 py-2 text-right font-medium">Suggested / day</th>
                  <th className="px-3 py-2 font-medium">Notes</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {flocks === null && (
                  <tr><td colSpan={7} className="px-3 py-4 text-slate-500"><Loader2 className="mr-2 inline h-4 w-4 animate-spin" />Loading flocks…</td></tr>
                )}
                {flocks?.length === 0 && <tr><td colSpan={7} className="px-3 py-4 text-slate-500">No open flocks.</td></tr>}
                {(flocks ?? []).map((f) => {
                  const on = !!picked[f.flockId]
                  const own = parseQty(flockDose[f.flockId] ?? "")
                  const sug = suggestQuantity(own ?? dose, basis || null, f.birds)
                  return (
                    <tr key={f.flockId} className={cn(!on && "text-slate-500")}>
                      <td className="px-3 py-2">
                        <Checkbox checked={on} aria-label={`Select ${f.flockName}`}
                          onCheckedChange={(v) => setPicked((p) => ({ ...p, [f.flockId]: v === true }))} />
                      </td>
                      <td className="px-3 py-2 font-medium text-slate-900">{f.flockName}</td>
                      <td className="px-3 py-2">{f.houseName ?? "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{f.birds?.toLocaleString() ?? "—"}</td>
                      <td className="px-3 py-2">
                        {on && (
                          <Input type="number" min={0} step="any" className="h-9 w-28 tabular-nums"
                            placeholder={dose != null ? String(dose) : ""} value={flockDose[f.flockId] ?? ""}
                            onChange={(e) => setFlockDose((p) => ({ ...p, [f.flockId]: e.target.value }))} />
                        )}
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums">{on ? fmtQty(sug, unit) : ""}</td>
                      <td className="px-3 py-2">
                        {on && (
                          <Input className="h-9 min-w-[10rem]" value={flockNotes[f.flockId] ?? ""}
                            onChange={(e) => setFlockNotes((p) => ({ ...p, [f.flockId]: e.target.value }))} />
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {product && anySuggestion && (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Stat label="In stock now" value={fmtQty(product.availableQuantity, unit)} />
          <Stat label="Suggested per day" value={fmtQty(perDay, unit)} />
          <Stat label={`Suggested for ${days} day${days === 1 ? "" : "s"}`} value={fmtQty(planTotal, unit)}
            tone={planTotal > product.availableQuantity ? "bad" : undefined} />
          <Stat label="Short by" value={planTotal > product.availableQuantity ? fmtQty(planTotal - product.availableQuantity, unit) : "—"}
            tone={planTotal > product.availableQuantity ? "bad" : undefined} />
        </div>
      )}

      <div className="sticky bottom-0 z-20 -mx-4 border-t border-slate-200 bg-white/95 px-4 py-3 pb-16 backdrop-blur sm:-mx-6 sm:px-6 lg:pb-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className={cn("text-sm", problem ? "text-slate-500" : "text-slate-600")}>
            {problem ?? `${selected.length} flock${selected.length === 1 ? "" : "s"}, ${days} day${days === 1 ? "" : "s"}. No stock moves until a day is recorded.`}
          </p>
          <Button className="bg-violet-600 text-white hover:bg-violet-700" disabled={!!problem || saving} onClick={() => void save()}>
            {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Create campaign
          </Button>
        </div>
      </div>
    </>
  )
}

// =============================================================================
// One campaign
// =============================================================================

function CampaignDetail({ id }: { id: number }) {
  const { toast } = useToast()
  const fmt = useFmt()
  const { fmtInstant } = useCompanyDateTime()
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [c, setC] = useState<TreatmentCampaign | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [product, setProduct] = useState<MedicationProduct | null>(null)
  const [flocks, setFlocks] = useState<TreatmentCampaignFlock[]>([])
  const [days, setDays] = useState<TreatmentDayPosting[]>([])
  const [tab, setTab] = useState("record")
  const [date, setDate] = useState<string | null>(null)
  const [grid, setGrid] = useState<TreatmentDayRow[] | null>(null)
  const [gridLoading, setGridLoading] = useState(false)
  const [actual, setActual] = useState<Record<number, string>>({})
  const [lineNotes, setLineNotes] = useState<Record<number, string>>({})
  const [dayNotes, setDayNotes] = useState("")
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [posting, setPosting] = useState(false)
  const [openDay, setOpenDay] = useState<number | null>(null)
  const [dayLines, setDayLines] = useState<Record<number, TreatmentDayLine[]>>({})
  const [reverseDay, setReverseDay] = useState<TreatmentDayPosting | null>(null)
  const [cancelOpen, setCancelOpen] = useState(false)
  const [completeOpen, setCompleteOpen] = useState(false)
  const [busy, setBusy] = useState(false)

  const loadCampaign = useCallback(async () => {
    try {
      const [camp, fl, ds, prods] = await Promise.all([
        getTreatmentCampaign(id), listTreatmentCampaignFlocks(id), listTreatmentDays(id), listMedicationProducts(),
      ])
      setC(camp)
      setFlocks(fl)
      setDays(ds)
      setProduct(prods.find((p) => p.poultryRawMaterialItemId === camp.poultryRawMaterialItemId) ?? null)
      setError(null)
    } catch (e) {
      setError(errText(e) || "Could not load this campaign.")
    }
  }, [id])

  useEffect(() => { if (activeFarmId) void loadCampaign() }, [activeFarmId, loadCampaign])

  const today = c?.companyToday.slice(0, 10) ?? ""
  const recordable = useMemo(
    () => (c ? recordableDays(c.startDate.slice(0, 10), c.endDate.slice(0, 10), today) : []),
    [c, today],
  )
  const postedDates = useMemo(() => new Set(days.filter((d) => d.status === "Posted").map((d) => d.businessDate.slice(0, 10))), [days])

  // Default: today when it is in the window, else the first day not yet recorded.
  useEffect(() => {
    if (!c || date) return
    if (recordable.length === 0) return
    const firstOpen = recordable.find((d) => !postedDates.has(d))
    setDate(recordable.includes(today) && !postedDates.has(today) ? today : firstOpen ?? recordable[recordable.length - 1])
  }, [c, date, recordable, postedDates, today])

  const loadGrid = useCallback(async () => {
    if (!date) return
    setGridLoading(true)
    try {
      setGrid(await getTreatmentDayGrid(id, date))
      setActual({})
      setLineNotes({})
    } catch (e) {
      toast({ title: "Could not load the flocks for this day", description: errText(e), variant: "destructive" })
    } finally {
      setGridLoading(false)
    }
  }, [id, date, toast])
  useEffect(() => { void loadGrid() }, [loadGrid])

  const unit = c?.unitOfMeasure ?? product?.unitOfMeasure ?? ""
  const rows = useMemo(() => (grid ?? []).map((r) => ({ r, state: dayRowState(r), actualText: actual[r.flockId] ?? "" })), [grid, actual])
  const totals = dayTotals(product?.availableQuantity ?? 0, rows)
  const isOpen = c?.lifecycle === "Open"
  const alreadyPosted = !!date && postedDates.has(date)
  const blocker = dayPostBlocker(totals, rows, { alreadyPosted, campaignOpen: isOpen, inWindow: !!date && recordable.includes(date) })
  const nothingEntered = rows.every((x) => x.actualText.trim() === "")
  const toPost = rows.filter((x) => x.state === "ok" && (parseQty(x.actualText) ?? 0) > 0)

  const fillSuggestions = () => {
    const next = { ...actual }
    for (const x of rows) if (x.state === "ok" && x.r.suggestedQuantity != null) next[x.r.flockId] = String(x.r.suggestedQuantity)
    setActual(next)
  }

  const doPost = async () => {
    if (!date) return
    setPosting(true)
    try {
      await postTreatmentDay(id, {
        businessDate: date,
        notes: dayNotes.trim() || null,
        lines: toPost.map((x) => ({
          flockId: x.r.flockId,
          actualQuantity: parseQty(x.actualText)!,
          suggestedQuantity: x.r.suggestedQuantity,
          notes: lineNotes[x.r.flockId]?.trim() || null,
        })),
      })
      toast({ title: "Treatment recorded", description: `${fmtQty(totals.actual, unit)} to ${toPost.length} flock${toPost.length === 1 ? "" : "s"} on ${formatLongDate(date)}.` })
      setConfirmOpen(false)
      setDayNotes("")
      await loadCampaign()
      await loadGrid()
    } catch (e) {
      toast({
        title: e instanceof InsufficientMedicationError ? "Not enough in stock" : "Not recorded",
        description: errText(e), variant: "destructive",
      })
      if (e instanceof InsufficientMedicationError) await loadCampaign()
    } finally {
      setPosting(false)
    }
  }

  const toggleDay = async (pid: number) => {
    if (openDay === pid) { setOpenDay(null); return }
    setOpenDay(pid)
    if (!dayLines[pid]) {
      try { setDayLines((p) => ({ ...p, [pid]: [] })); const l = await getTreatmentDayLines(pid); setDayLines((p) => ({ ...p, [pid]: l })) }
      catch { /* shown as empty */ }
    }
  }

  const run = async (fn: () => Promise<void>, ok: string, after?: () => void) => {
    setBusy(true)
    try {
      await fn()
      toast({ title: ok })
      after?.()
      await loadCampaign()
      await loadGrid()
    } catch (e) {
      toast({ title: "Not done", description: errText(e), variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  if (error) {
    return (
      <>
        <Title back title="Treatment campaign" sub="" />
        <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>
      </>
    )
  }
  if (!c) {
    return <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>
  }

  const doseText = describeDose(c.doseQuantity, c.doseBasis, unit)
  const recognition = product?.costRecognitionMethod === "EXPENSE_WHEN_CONSUMED"
    ? "Expensed when consumed — recording a day books the medication cost as an expense."
    : "Expensed when purchased — recording a day moves stock only; the cost was expensed at purchase."

  return (
    <>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <Title back title={c.name} sub={[c.itemName, c.reason].filter(Boolean).join(" · ")} />
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge status={c.status} />
          {isOpen && (
            <>
              <Button size="sm" variant="outline" onClick={() => setCompleteOpen(true)} disabled={busy}>
                <CheckCircle2 className="mr-1.5 h-4 w-4" /> Mark completed
              </Button>
              <Button size="sm" variant="outline" className="text-rose-700" onClick={() => setCancelOpen(true)} disabled={busy}>
                <XCircle className="mr-1.5 h-4 w-4" /> Cancel campaign
              </Button>
            </>
          )}
        </div>
      </div>

      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="grid grid-cols-1 gap-x-6 gap-y-2 p-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div><span className="text-slate-500">Dates: </span>{formatLongDate(c.startDate.slice(0, 10))} – {formatLongDate(c.endDate.slice(0, 10))} ({c.plannedDays} day{c.plannedDays === 1 ? "" : "s"})</div>
          <div><span className="text-slate-500">Days recorded: </span>{c.postedDays} of {c.plannedDays}</div>
          <div><span className="text-slate-500">Given so far: </span>{fmtQty(c.totalQuantity, unit)}{c.totalCost != null && ` · ${fmt(c.totalCost)}`}</div>
          <div><span className="text-slate-500">Dose: </span>{doseText ? `${doseText}${c.doseSource === "Product" ? " (product setting)" : ""}` : "None set — quantities are typed each day"}</div>
          <div><span className="text-slate-500">Egg withdrawal: </span>{c.eggWithdrawalDays != null ? `${c.eggWithdrawalDays} day${c.eggWithdrawalDays === 1 ? "" : "s"}${c.eggWithdrawalUntil ? ` — until ${formatLongDate(c.eggWithdrawalUntil.slice(0, 10))}` : ""}` : "not set"}</div>
          <div><span className="text-slate-500">Meat withdrawal: </span>{c.meatWithdrawalDays != null ? `${c.meatWithdrawalDays} day${c.meatWithdrawalDays === 1 ? "" : "s"}${c.meatWithdrawalUntil ? ` — until ${formatLongDate(c.meatWithdrawalUntil.slice(0, 10))}` : ""}` : "not set"}</div>
          {c.doseInstructions && <div className="sm:col-span-2 lg:col-span-3"><span className="text-slate-500">Usage information: </span>{c.doseInstructions}</div>}
          {c.withdrawalNotes && <div className="sm:col-span-2 lg:col-span-3"><span className="text-slate-500">Withdrawal notes: </span>{c.withdrawalNotes}</div>}
          {c.notes && <div className="sm:col-span-2 lg:col-span-3"><span className="text-slate-500">Notes: </span>{c.notes}</div>}
          {c.status === "Cancelled" && (
            <div className="text-rose-700 sm:col-span-2 lg:col-span-3">
              Cancelled by {c.cancelledBy ?? "unknown"} · {fmtInstant(c.cancelledAtUtc)} — {c.cancelReason}. Days already recorded stay recorded.
            </div>
          )}
          {c.status === "Completed" && (
            <div className="text-emerald-700 sm:col-span-2 lg:col-span-3">Completed by {c.completedBy ?? "unknown"} · {fmtInstant(c.completedAtUtc)}</div>
          )}
          <div className="text-xs text-slate-500 sm:col-span-2 lg:col-span-3">
            Withdrawal dates run from the last day recorded. They are your own figures — the system does not hold eggs or birds back on them.
          </div>
        </CardContent>
      </Card>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="record">Record treatment</TabsTrigger>
          <TabsTrigger value="days">Treatment days ({days.length})</TabsTrigger>
          <TabsTrigger value="flocks">Flocks ({flocks.length})</TabsTrigger>
        </TabsList>

        {/* ------------------------------------------------ record a day */}
        <TabsContent value="record" className="mt-4 space-y-4">
          {!isOpen ? (
            <p className="text-sm text-slate-500">This campaign is {statusLabel(c.status).toLowerCase()} — no more treatment can be recorded on it.</p>
          ) : recordable.length === 0 ? (
            <p className="text-sm text-slate-500">This campaign starts on {formatLongDate(c.startDate.slice(0, 10))}. Treatment can be recorded from that day.</p>
          ) : (
            <>
              <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                <CardContent className="space-y-3 p-4">
                  <div className="flex flex-wrap items-end gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs text-slate-500">Treatment day</Label>
                      <Select value={date ?? ""} onValueChange={(v) => setDate(v)}>
                        <SelectTrigger className="w-64"><SelectValue placeholder="Choose a day" /></SelectTrigger>
                        <SelectContent>
                          {recordable.map((d, i) => (
                            <SelectItem key={d} value={d}>
                              Day {i + 1} · {formatLongDate(d)}{postedDates.has(d) ? " — recorded" : ""}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <Button variant="outline" size="sm" className="mb-0.5" onClick={fillSuggestions}
                      disabled={alreadyPosted || !rows.some((x) => x.state === "ok" && x.r.suggestedQuantity != null)}>
                      Fill Actual from suggestions
                    </Button>
                  </div>
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                    <Stat label="In stock" value={fmtQty(totals.available, unit)} />
                    <Stat label="Giving today" value={fmtQty(totals.actual, unit)} />
                    <Stat label="Left after" value={fmtQty(totals.remaining, unit)} tone={totals.remaining < 0 ? "bad" : undefined} />
                  </div>
                  <p className="text-xs text-slate-500">{recognition}</p>
                </CardContent>
              </Card>

              {gridLoading && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading flocks…</p>}

              {grid && !gridLoading && (
                <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                  <CardContent className="p-0">
                    <div className="overflow-x-auto">
                      <table className="w-full min-w-[50rem] text-sm">
                        <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                          <tr>
                            <th className="px-3 py-2 font-medium">Flock</th>
                            <th className="px-3 py-2 text-right font-medium">Bird count</th>
                            <th className="px-3 py-2 font-medium">Dose</th>
                            <th className="px-3 py-2 text-right font-medium">Suggested</th>
                            <th className="px-3 py-2 font-medium">Actual{unit ? ` (${unit})` : ""}</th>
                            <th className="px-3 py-2 font-medium">Notes</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                          {rows.map(({ r, state, actualText }) => {
                            const locked = state !== "ok"
                            const invalid = actualText.trim() !== "" && parseQty(actualText) == null
                            return (
                              <tr key={r.flockId} className={cn(locked && "bg-slate-50 text-slate-500")}>
                                <td className="px-3 py-2">
                                  <div className="font-medium text-slate-900">{r.flockName}</div>
                                  <div className="text-xs text-slate-500">{r.houseName ?? ""}</div>
                                  {r.thisItemQuantity > 0 && state === "ok" && (
                                    <div className="flex items-start gap-1 text-xs text-amber-700">
                                      <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" />
                                      Already {fmtQty(r.thisItemQuantity, unit)} of this product on today&apos;s record
                                    </div>
                                  )}
                                </td>
                                <td className="px-3 py-2 text-right tabular-nums">{r.birds?.toLocaleString() ?? "—"}</td>
                                <td className="px-3 py-2 text-xs">{describeDose(r.doseQuantity, r.doseBasis, unit) ?? "—"}</td>
                                <td className="px-3 py-2 text-right tabular-nums">{locked ? "—" : fmtQty(r.suggestedQuantity, unit)}</td>
                                <td className="px-3 py-2">
                                  {state === "posted" ? (
                                    <span className="inline-flex items-center gap-1 text-xs text-emerald-700">
                                      <CheckCircle2 className="h-3.5 w-3.5" /> {fmtQty(r.postedQuantity, unit)} recorded
                                    </span>
                                  ) : locked ? (
                                    <span className="inline-flex items-center gap-1 text-xs">
                                      <Lock className="h-3.5 w-3.5" />
                                      {state === "closed" ? "Flock is closed"
                                        : state === "noRecord" ? (
                                          <>No production record — <Link className="text-sky-700 underline"
                                            href={`/production-records/new?flockId=${r.flockId}&date=${date}`}>record it first</Link></>
                                        ) : (
                                          <>{r.recordCount} records for this day — <Link className="text-sky-700 underline"
                                            href={`/production-records?date=${date}`}>fix the duplicate</Link></>
                                        )}
                                    </span>
                                  ) : (
                                    <Input type="number" min={0} step="any" inputMode="decimal"
                                      className={cn("h-9 w-32 tabular-nums", invalid && "border-rose-400")}
                                      value={actualText}
                                      onChange={(e) => setActual((p) => ({ ...p, [r.flockId]: e.target.value }))} />
                                  )}
                                </td>
                                <td className="px-3 py-2">
                                  {!locked && (
                                    <Input className="h-9 min-w-[10rem]" value={lineNotes[r.flockId] ?? ""}
                                      onChange={(e) => setLineNotes((p) => ({ ...p, [r.flockId]: e.target.value }))} />
                                  )}
                                </td>
                              </tr>
                            )
                          })}
                        </tbody>
                      </table>
                    </div>
                  </CardContent>
                </Card>
              )}

              <div className="sticky bottom-0 z-20 -mx-4 border-t border-slate-200 bg-white/95 px-4 py-3 pb-16 backdrop-blur sm:-mx-6 sm:px-6 lg:pb-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className={cn("text-sm", blocker && !nothingEntered ? "text-rose-700" : "text-slate-600")}>
                    {alreadyPosted
                      ? blocker
                      : nothingEntered
                        ? "Type the quantity actually given to each flock."
                        : blocker ?? `${fmtQty(totals.actual, unit)} to ${toPost.length} flock${toPost.length === 1 ? "" : "s"} · ${fmtQty(totals.remaining, unit)} left`}
                  </p>
                  <Button className="bg-violet-600 text-white hover:bg-violet-700" disabled={!!blocker || posting}
                    onClick={() => setConfirmOpen(true)}>
                    Record Today&apos;s Treatment
                  </Button>
                </div>
              </div>
            </>
          )}
        </TabsContent>

        {/* ------------------------------------------------ posted days */}
        <TabsContent value="days" className="mt-4">
          <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
            <CardContent className="p-0">
              {days.length === 0 ? (
                <p className="p-4 text-sm text-slate-500">No treatment recorded yet.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[40rem] text-sm">
                    <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                      <tr>
                        <th className="px-3 py-2 font-medium">Day</th>
                        <th className="px-3 py-2 text-right font-medium">Flocks</th>
                        <th className="px-3 py-2 text-right font-medium">Quantity</th>
                        <th className="px-3 py-2 text-right font-medium">Cost</th>
                        <th className="px-3 py-2 font-medium">Status</th>
                        <th className="px-3 py-2 text-right font-medium">Action</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {days.map((d) => {
                        const open = openDay === d.poultryTreatmentCampaignPostId
                        return (
                          <FragmentRows key={d.poultryTreatmentCampaignPostId}>
                            <tr className="cursor-pointer hover:bg-slate-50" onClick={() => void toggleDay(d.poultryTreatmentCampaignPostId)}>
                              <td className="px-3 py-2 font-medium text-slate-900">
                                <span className="mr-1.5 inline-flex align-middle text-slate-500">
                                  {open ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                                </span>
                                {formatLongDate(d.businessDate.slice(0, 10))}
                              </td>
                              <td className="px-3 py-2 text-right tabular-nums">{d.flockCount}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{fmtQty(d.totalQuantity, unit)}</td>
                              <td className="px-3 py-2 text-right tabular-nums">{d.totalCost != null ? fmt(d.totalCost) : "—"}</td>
                              <td className="px-3 py-2">
                                <span className={cn("rounded-full px-2 py-0.5 text-xs",
                                  d.status === "Posted" ? "bg-emerald-100 text-emerald-700" : "bg-slate-200 text-slate-600")}>
                                  {d.status === "Posted" ? "Recorded" : "Reversed"}
                                </span>
                              </td>
                              <td className="px-3 py-2 text-right">
                                {d.status === "Posted" && (
                                  <Button size="sm" variant="outline" className="h-7 gap-1 px-2.5 text-xs"
                                    onClick={(e) => { e.stopPropagation(); setReverseDay(d) }}>
                                    <RotateCcw className="h-3.5 w-3.5" /> Reverse
                                  </Button>
                                )}
                              </td>
                            </tr>
                            {open && (
                              <tr className="bg-slate-50/80">
                                <td colSpan={6} className="px-3 py-3 pl-9 text-xs text-slate-600">
                                  <p>Recorded by {d.postedBy ?? "unknown"} · {fmtInstant(d.postedAtUtc)}{d.notes ? ` · “${d.notes}”` : ""}</p>
                                  {d.status === "Reversed" && (
                                    <p className="text-rose-700">Reversed by {d.reversedBy ?? "unknown"} · {fmtInstant(d.reversedAtUtc)} — {d.reversalReason}</p>
                                  )}
                                  <table className="mt-2 w-full">
                                    <tbody>
                                      {(dayLines[d.poultryTreatmentCampaignPostId] ?? []).map((l) => (
                                        <tr key={l.poultryTreatmentCampaignPostLineId}>
                                          <td className="py-0.5 pr-3 text-slate-800">{l.flockName}</td>
                                          <td className="py-0.5 pr-3 tabular-nums">
                                            {fmtQty(l.actualQuantity, unit)}{l.suggestedQuantity != null && ` (suggested ${fmtQty(l.suggestedQuantity, unit)})`}
                                          </td>
                                          <td className="py-0.5 pr-3 tabular-nums">{l.totalCost != null ? fmt(l.totalCost) : ""}</td>
                                          <td className="py-0.5 pr-3">
                                            <Link className="text-sky-700 underline" href={`/production-records/${l.productionRecordId}`}>production record</Link>
                                          </td>
                                          <td className="py-0.5">{l.notes ?? ""}{l.reversalNote ? ` · ${l.reversalNote}` : ""}</td>
                                        </tr>
                                      ))}
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            )}
                          </FragmentRows>
                        )
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* ------------------------------------------------ flocks */}
        <TabsContent value="flocks" className="mt-4">
          <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full min-w-[40rem] text-sm">
                  <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                    <tr>
                      <th className="px-3 py-2 font-medium">Flock</th>
                      <th className="px-3 py-2 text-right font-medium">Birds at start</th>
                      <th className="px-3 py-2 font-medium">Own dose</th>
                      <th className="px-3 py-2 text-right font-medium">Days given</th>
                      <th className="px-3 py-2 text-right font-medium">Total given</th>
                      <th className="px-3 py-2 font-medium">Notes</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {flocks.map((f) => (
                      <tr key={f.flockId}>
                        <td className="px-3 py-2">
                          <Link href={`/flocks/${f.flockId}`} className="font-medium text-violet-700 hover:underline">{f.flockName}</Link>
                          {f.isClosed && <span className="ml-1.5 text-xs text-slate-500">(closed)</span>}
                          <div className="text-xs text-slate-500">{f.houseName ?? ""}</div>
                        </td>
                        <td className="px-3 py-2 text-right tabular-nums">{f.birdsAtCreation?.toLocaleString() ?? "—"}</td>
                        <td className="px-3 py-2 text-xs">{f.doseQuantity != null ? describeDose(f.doseQuantity, c.doseBasis, unit) : "Campaign dose"}</td>
                        <td className="px-3 py-2 text-right tabular-nums">{f.postedDays}</td>
                        <td className="px-3 py-2 text-right tabular-nums">{fmtQty(f.totalQuantity, unit)}</td>
                        <td className="px-3 py-2 text-xs">{f.notes ?? ""}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Record this treatment?</DialogTitle>
            <DialogDescription>
              {fmtQty(totals.actual, unit)} of {c.itemName} on {date ? formatLongDate(date) : ""}, to {toPost.length} flock
              {toPost.length === 1 ? "" : "s"}. Stock is checked again when you record. Each flock&apos;s production record gets the
              medication as a line, and stock goes down now.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1">
            <Label htmlFor="tc-daynotes" className="text-xs text-slate-500">Notes (optional)</Label>
            <Input id="tc-daynotes" value={dayNotes} onChange={(e) => setDayNotes(e.target.value)} placeholder="e.g. Given in morning water" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmOpen(false)} disabled={posting}>Cancel</Button>
            <Button onClick={() => void doPost()} disabled={posting} className="bg-violet-600 text-white hover:bg-violet-700">
              {posting && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Record
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={completeOpen} onOpenChange={setCompleteOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Mark this campaign completed?</DialogTitle>
            <DialogDescription>
              {c.postedDays} of {c.plannedDays} days are recorded. Completing stops further recording; the days already recorded stay as they are.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCompleteOpen(false)} disabled={busy}>Not yet</Button>
            <Button disabled={busy} className="bg-emerald-600 text-white hover:bg-emerald-700"
              onClick={() => void run(() => completeTreatmentCampaign(id), "Campaign completed", () => setCompleteOpen(false))}>
              {busy && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Mark completed
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ReasonDialog
        open={cancelOpen} onOpenChange={setCancelOpen} busy={busy} destructive
        title="Cancel this campaign?"
        description="No more treatment can be recorded on it. Days already recorded stay recorded — those birds were treated. To take a wrong day back, reverse it under Treatment days."
        confirmLabel="Cancel campaign"
        onConfirm={(r) => void run(() => cancelTreatmentCampaign(id, r), "Campaign cancelled", () => setCancelOpen(false))} />

      <ReasonDialog
        open={!!reverseDay} onOpenChange={(v) => { if (!v) setReverseDay(null) }} busy={busy} destructive
        title="Reverse this treatment day?"
        description="The medication comes off each flock's production record for that day and goes back into stock. The day stays in the history, marked Reversed, and can be recorded again."
        confirmLabel="Reverse"
        onConfirm={(r) => {
          const d = reverseDay
          if (!d) return
          void run(() => reverseTreatmentDay(d.poultryTreatmentCampaignPostId, r), "Treatment day reversed", () => {
            setReverseDay(null)
            setDayLines((p) => { const n = { ...p }; delete n[d.poultryTreatmentCampaignPostId]; return n })
          })
        }} />
    </>
  )
}

/** Two table rows under one key. */
function FragmentRows({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}

// =============================================================================

function TreatmentCampaignsInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const id = Number(searchParams.get("id")) || null
  const isNew = searchParams.get("new") === "1"

  return (
    <Shell>
      {id ? <CampaignDetail key={id} id={id} /> : isNew ? <NewCampaign /> : <CampaignList />}
    </Shell>
  )
}

export default function TreatmentCampaignsPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <TreatmentCampaignsInner />
    </Suspense>
  )
}

"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { ArrowLeft, Banknote, Building2, Landmark, TrendingUp } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { PeriodSelect } from "@/components/ui/period-select"
import { StatementPanel } from "@/components/reports/statement-sections"
import { PlInfoSection } from "@/components/reports/pl-info-section"
import { RichCard } from "@/components/reports/report-header"
import { defaultReportRange, type PeriodKey } from "@/lib/date-ranges"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useCurrency } from "@/lib/currency"
import { getProfitLossEntries, type GenericProfitLossEntry as Entry } from "@/lib/api/generic"
import { downloadCsv } from "@/lib/utils/download-csv"
import { exportTableToPdf, emailTableAsPdf } from "@/lib/utils/pdf-export"

const panels = [
  { id: "revenue", title: "Revenue", tone: "emerald" },
  { id: "direct", title: "Direct costs", tone: "rose" },
  { id: "operating", title: "Operating expenses", tone: "amber" },
  { id: "other", title: "Depreciation & financing", tone: "violet" },
] as const

const information = [
  { id: "owner", title: "Owner funding & draws", total: "Net owner funding", note: "Contributions and withdrawals change the owner’s investment.", href: "/generic-owner-money", link: "View owner money", icon: Banknote },
  { id: "borrowing", title: "Loans", total: "Net borrowing", note: "Loan proceeds and principal repayments change the amount owed. Interest and fees appear above.", href: "/generic-loans", link: "View loans", icon: Landmark },
  { id: "capital", title: "Capital investments", total: "Total capital investments", note: "Asset purchases are recorded at acquisition cost. Only dated depreciation expenses enter this statement.", href: "/generic-assets", link: "View assets", icon: Building2 },
] as const

type Line = { lineKey: string; lineLabel: string; amount: number; entries: Entry[] }
function summarise(entries: Entry[]) {
  const groups = new Map<Entry["section"], Map<string, Line>>()
  for (const entry of entries) {
    const section = groups.get(entry.section) ?? new Map<string, Line>()
    const line = section.get(entry.line) ?? { lineKey: entry.line, lineLabel: entry.line, amount: 0, entries: [] }
    line.amount += entry.amount
    line.entries.push(entry)
    section.set(entry.line, line)
    groups.set(entry.section, section)
  }
  const lines = (section: Entry["section"]) => Array.from(groups.get(section)?.values() ?? [])
  const total = (section: Entry["section"]) => lines(section).reduce((sum, line) => sum + line.amount, 0)
  return { lines, total }
}

export function GenericProfitLossView({ report = false }: { report?: boolean }) {
  const router = useRouter()
  const logout = useLogout()
  const farmId = useAuthStore(s => s.activeFarmId)
  const farmType = useAuthStore(s => s.activeFarmType)
  const farmName = useAuthStore(s => s.activeFarmName)
  const [range, setRange] = useState(() => defaultReportRange())
  const [period, setPeriod] = useState<PeriodKey>("last30")
  const [refresh, setRefresh] = useState(0)
  useEffect(() => {
    if (farmType && farmType !== "Generic") router.replace("/dashboard")
  }, [farmType, router])
  return <div className="flex h-screen bg-slate-50">
    <DashboardSidebar onLogout={logout} />
    <div className="flex flex-1 min-w-0 flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 sm:p-6"><div className="mx-auto max-w-7xl space-y-4">
        <Link href={report ? "/generic-reports" : "/generic-dashboard"} className="inline-flex items-center gap-1 text-sm text-slate-600"><ArrowLeft size={15} /> Back to {report ? "reports" : "dashboard"}</Link>
        <header className={report ? "rounded-lg border border-t-4 border-t-amber-500 bg-white p-5" : ""}>
          {report && <p className="text-sm font-semibold text-amber-700">{farmName}</p>}
          <h1 className="flex items-center gap-2 text-2xl font-bold"><TrendingUp className="text-emerald-700" /> Profit &amp; Loss</h1>
          <p className="text-sm text-slate-600">Revenue, costs and profit for the selected period.</p>
        </header>
        <div className="flex flex-wrap items-end gap-3">
          <PeriodSelect value={period} onChange={(p, dates) => { setPeriod(p); if (dates) setRange(dates) }} />
          {(["from", "to"] as const).map(field => <label key={field} className="text-xs capitalize">{field}
            <Input type="date" value={range[field]} onChange={e => { setPeriod("custom"); setRange({ ...range, [field]: e.target.value }) }} />
          </label>)}
          <Button variant="outline" onClick={() => { setRange(defaultReportRange()); setPeriod("last30") }}>Reset</Button>
          <Button onClick={() => setRefresh(n => n + 1)}>Refresh</Button>
        </div>
        {(!range.from || !range.to || range.from > range.to) ? <p role="alert">Choose a valid start and end date.</p>
          : farmType === "Generic" && farmId && <Statement key={[farmId, range.from, range.to, refresh].join("/")} farmId={farmId} from={range.from} to={range.to} farmName={farmName ?? "Company"} />}
      </div></main>
    </div>
  </div>
}

function Statement({ from, to, farmName, farmId }: { farmId: string; from: string; to: string; farmName: string }) {
  const { labels, isSubscriptionBusiness } = useGenericModules()
  const [generated, setGenerated] = useState("")
  const { fmt, code } = useCurrency()
  const { toast } = useToast()
  const [entries, setEntries] = useState<Entry[] | null>(null)
  const [error, setError] = useState(false)
  const [selected, setSelected] = useState<Line | null>(null)
  const [search, setSearch] = useState("")
  const [exporting, setExporting] = useState(false)
  useEffect(() => {
    let active = true
    getProfitLossEntries(farmId, from, to).then(data => {
      if (active) {
        setEntries(data)
        setGenerated(new Date().toLocaleString())
      }
    })
      .catch(() => { if (active) setError(true) })
    return () => { active = false }
  }, [farmId, from, to])
  const { lines, total } = useMemo(() => summarise(entries ?? []), [entries])
  if (error) return <p role="alert">Could not load this statement. Use Refresh to try again.</p>
  if (!entries) return <p role="status">Loading statement…</p>

  const revenue = total("revenue")
  const expenses = total("direct") + total("operating") + total("other")
  const gross = revenue - total("direct")
  const operating = gross - total("operating")
  const net = operating - total("other")
  const margin = revenue ? (net * 100 / revenue).toFixed(1) + "% margin" : "Margin unavailable without revenue"
  const subscriptionIncome = lines("revenue").find(line => line.lineKey === "Subscription income")?.amount ?? 0
  const cards = [
    { label: "Total revenue", amount: revenue, note: "Approved sales excluding sales tax" },
    { label: "Total expenses", amount: expenses, note: "Direct, operating and financing costs plus depreciation" },
    { label: "Gross profit", amount: gross, note: "Revenue less direct costs" },
    { label: "Operating profit", amount: operating, note: "Gross profit less operating expenses" },
    { label: net < 0 ? "Net loss" : "Net profit", amount: net, note: margin },
  ]
  const open = (line: Line) => { setSearch(""); setSelected(line) }
  const matching = selected?.entries.filter(e => [e.date, e.reference, e.description].join(" ").toLowerCase().includes(search.trim().toLowerCase())) ?? []

  async function exportReport(format: "CSV" | "Email" | "PDF") {
    const rows: (string | number)[][] = []
    for (const section of [...panels, ...information]) {
      const title = "href" in section ? section.title + " (excluded from profit)" : section.title
      for (const line of lines(section.id)) rows.push([title, line.lineLabel, Number(line.amount.toFixed(2))])
      rows.push([title, "Total", Number(total(section.id).toFixed(2))])
    }
    for (const card of cards) rows.push(["Summary", card.label, Number(card.amount.toFixed(2))])
    const headers = ["Section", "Line", "Amount (" + code + ")"]
    const filename = "generic-profit-loss-" + from + "-" + to
    const pdf = { title: "Profit & Loss", filename, farmName, currencyLabel: code, fromDate: from, toDate: to,
      columns: headers.map(header => ({ header })), rows, summaryCards: cards.map(c => ({ label: c.label, value: fmt(c.amount) })) }
    setExporting(true)
    try {
      if (format === "CSV") downloadCsv(filename, headers, rows)
      else if (format === "PDF") await exportTableToPdf(pdf)
      else {
        const result = await emailTableAsPdf(pdf)
        if (!result.success) throw new Error(result.message ?? "Delivery failed.")
        toast({ title: "Report emailed", description: result.recipient })
      }
    } catch (e) { toast({ title: "Export failed", description: e instanceof Error ? e.message : undefined, variant: "destructive" }) }
    finally { setExporting(false) }
  }

  return <>
    <div className="flex flex-wrap items-center justify-between gap-3">
      <p className="text-sm text-slate-600">{from} to {to} · {code}</p>
      <div className="flex gap-2">{(["CSV", "Email", "PDF"] as const).map(format =>
        <Button key={format} size="sm" variant="outline" disabled={exporting} onClick={() => exportReport(format)}>{format}</Button>)}</div>
    </div>
    {!entries.length && <p className="text-sm text-slate-600">No posted activity in this period.</p>}
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-5">{cards.map(c =>
      <RichCard key={c.label} label={c.label} value={fmt(c.amount)} lines={[c.note]} accent={c.label === "Total expenses" || c.amount < 0 ? "red" : "emerald"} />)}</div>
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">{panels.map(s =>
      <StatementPanel key={s.id} title={s.title} tone={s.tone} totalLabel={"Total " + s.title.toLowerCase()} total={total(s.id)}
        negative={s.id !== "revenue"} gh={fmt} lines={lines(s.id).map(l => ({ id: l.lineKey, label: l.lineLabel, amount: l.amount, entryCount: l.entries.length, onOpen: () => open(l) }))} />)}</div>
    <p className="text-sm text-slate-600">Stock purchases enter direct costs as the stock is sold or written off. Approved bills enter expenses even when payment comes later.</p>
    <div className="grid gap-3 md:grid-cols-3">{information.map(s =>
      <PlInfoSection key={s.id} title={s.title} subtitle="Excluded from profit" note={s.note} icon={<s.icon size={18} />}
        lines={lines(s.id)} onOpen={open} gh={fmt} links={[{ href: s.href, label: s.link }]} footer={<p className="text-sm">{s.total} <strong>{fmt(total(s.id))}</strong></p>} />)}</div>
    {isSubscriptionBusiness && <section aria-label="Income breakdown" className="grid gap-3 md:grid-cols-3">
      <RichCard label={labels.subscription + " income"} value={fmt(subscriptionIncome)} />
      <RichCard label="Other income" value={fmt(revenue - subscriptionIncome)} />
      <RichCard label="Recurring share" value={revenue ? (100 * subscriptionIncome / revenue).toFixed(1) + "%" : "?"} />
    </section>}
    <Link href="/generic-cash-flow" className="inline-block text-sm text-sky-700 underline">View cash flow</Link>
    <Dialog open={!!selected} onOpenChange={value => { if (!value) setSelected(null) }}>
      <DialogContent className="sm:max-w-3xl"><DialogHeader><DialogTitle>{selected?.lineLabel}</DialogTitle>
        <DialogDescription>{from} to {to} · Total {fmt(selected?.amount ?? 0)}</DialogDescription></DialogHeader>
        <Input aria-label="Search entries" placeholder="Search by date, reference or description" value={search} onChange={e => setSearch(e.target.value)} />
        <div className="max-h-[55vh] overflow-auto"><table className="w-full text-left text-sm">
          <thead><tr>{["Date", "Reference", "Description", "Amount"].map(label => <th key={label} className="p-2">{label}</th>)}</tr></thead>
          <tbody>{matching.map((e, i) => <tr key={i} className="border-t"><td className="p-2 whitespace-nowrap">{e.date}</td><td className="p-2">{e.reference}</td>
            <td className="p-2">{e.description}</td><td className="p-2 whitespace-nowrap">{fmt(e.amount)}</td></tr>)}</tbody></table>
          {!matching.length && <p className="p-2">No matching entries.</p>}</div>
        <p className="text-sm">Showing {matching.length} entries · Subtotal {fmt(matching.reduce((sum, e) => sum + e.amount, 0))}</p>
      </DialogContent>
    </Dialog>
  </>
}

"use client"

// The Poultry Sales page (app/sales) as a shell the Restaurant and Hotel Sales
// pages share: header with the add action, search, Filters sheet on phones /
// filter bar on desktop, PDF and Email, the scorecards, "Recent Sales" as
// expandable phone cards with "View table format", a sortable table, and
// pagination under both. Each module passes its rows through `toRow` and
// renders its own buttons; the Invoice button is built in, printing the sale
// (with line items when the module can load them).

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import Link from "next/link"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { DataPagination } from "@/components/ui/data-pagination"
import { SortableHeader, sortData, toggleSort, type SortDirection } from "@/components/ui/sortable-header"
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS, MOBILE_FILTER_SELECT_CONTENT_CLASS, MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS, MobileFilterSheetBody, MobileFilterSheetFooter, MobileFilterSheetHeader,
} from "@/components/dashboard/mobile-filters"
import {
  ChevronDown, ChevronUp, DollarSign, Download, FileText, Filter, Loader2, Mail, Package, Plus, Printer, Search,
  ShoppingCart, TrendingUp, Wallet, type LucideIcon,
} from "lucide-react"
import { usePagination } from "@/hooks/use-pagination"
import { useIsMobile } from "@/hooks/use-mobile"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { cn, formatDateShort } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { emailTableAsPdf, exportTableToPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

export type SaleStatus = "Paid" | "Partial" | "Pending"

/** One sale as the shell shows it. */
export interface ModuleSaleRow {
  key: string
  reference: string
  date: string
  customer: string
  /** What was sold: "Room 12 · 3 nights", "Dine-in · 4 items". */
  product: string
  quantity: number | null
  total: number
  paid: number
  balance: number
  method: string | null
  status: SaleStatus
  /** Extra label/value pairs for the phone card (Room, Type, Booking…). */
  details?: { label: string; value: ReactNode }[]
}

export interface SalesExtraFilter<T> {
  key: string
  label: string
  allLabel: string
  options: { value: string; label: string }[]
  test: (item: T, value: string) => boolean
}

export interface InvoiceLine { description: string; quantity: number; unitPrice: number; total: number }

interface Props<T> {
  subtitle: string
  /** Tailwind classes for the module colour: rose for Restaurant, violet for Hotel. */
  accent: { iconBg: string; iconText: string; button: string; spinner: string }
  addAction?: { label: string; href: string } | null
  headerExtra?: ReactNode
  items: T[]
  loading: boolean
  toRow: (item: T) => ModuleSaleRow
  quantityLabel: string
  quantityHint: string
  searchPlaceholder: string
  extraFilters?: SalesExtraFilter<T>[]
  /** Called with the committed date range so the page can reload from the server. */
  onRangeChange: (from: string, to: string) => void
  /** Pay / Payments / module buttons on the phone card (grid of two). */
  renderCardActions: (item: T, row: ModuleSaleRow) => ReactNode
  /** The same actions as icon buttons in the table. */
  renderTableActions: (item: T, row: ModuleSaleRow) => ReactNode
  /** Buttons after Invoice (Poultry's order: Pay, Edit, Invoice, Payments, Delete). */
  renderCardActionsEnd?: (item: T, row: ModuleSaleRow) => ReactNode
  renderTableActionsEnd?: (item: T, row: ModuleSaleRow) => ReactNode
  loadInvoiceLines?: (item: T) => Promise<InvoiceLine[]>
  pdf: { title: string; filename: string; headFillColor: [number, number, number] }
  banner?: ReactNode
  emptyTitle: string
  emptyText: string
}

const STATUS_CLS: Record<SaleStatus, string> = {
  Paid: "bg-emerald-100 text-emerald-700",
  Partial: "bg-amber-100 text-amber-700",
  Pending: "bg-slate-100 text-slate-700",
}

export function SaleStatusBadge({ status }: { status: SaleStatus }) {
  return <span className={cn("inline-flex w-fit rounded-full px-2 py-0.5 text-xs font-medium", STATUS_CLS[status])}>{status}</span>
}

/** Paid / Partial / Pending from the amounts, the way Poultry derives it. */
export function saleStatusOf(total: number, paid: number): SaleStatus {
  if (total > 0 && paid >= total - 0.005) return "Paid"
  if (paid > 0) return "Partial"
  return total <= 0 ? "Paid" : "Pending"
}

const dateKey = (d: string) => (d ?? "").slice(0, 10)

export function ModuleSalesView<T>(p: Props<T>) {
  const fmt = useFmt()
  const isMobile = useIsMobile()
  const { toast } = useToast()
  const farmName = useAuthStore((s) => s.activeFarmName) ?? ""
  const extraFilters = p.extraFilters ?? []

  const [search, setSearch] = useState("")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [extras, setExtras] = useState<Record<string, string>>({})
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [draft, setDraft] = useState<{ from: string; to: string; extras: Record<string, string> }>({ from: "", to: "", extras: {} })
  const [showTable, setShowTable] = useState(false)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [emailing, setEmailing] = useState(false)

  const [invoiceFor, setInvoiceFor] = useState<{ item: T; row: ModuleSaleRow } | null>(null)
  const [invoiceLines, setInvoiceLines] = useState<InvoiceLine[] | null>(null)
  const invoiceRef = useRef<HTMLDivElement>(null)

  const onRangeChange = p.onRangeChange
  useEffect(() => { onRangeChange(from, to) }, [from, to, onRangeChange])

  const pairs = useMemo(() => p.items.map((item) => ({ item, row: p.toRow(item) })), [p.items, p.toRow])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return pairs.filter(({ item, row }) =>
      (!from || dateKey(row.date) >= from) && (!to || dateKey(row.date) <= to) &&
      extraFilters.every((f) => !extras[f.key] || extras[f.key] === "all" || f.test(item, extras[f.key])) &&
      (!q || [row.customer, row.reference, row.product].some((v) => (v ?? "").toLowerCase().includes(q))))
  }, [pairs, search, from, to, extras, extraFilters])

  const sorted = useMemo(
    () => sortData(filtered, sortKey, sortDir, (x, k) => (x.row as unknown as Record<string, unknown>)[k]),
    [filtered, sortKey, sortDir],
  )
  const pg = usePagination(sorted)

  const totalSales = filtered.reduce((s, x) => s + Number(x.row.total), 0)
  const totalQty = filtered.reduce((s, x) => s + Number(x.row.quantity ?? 0), 0)
  const totalPaid = filtered.reduce((s, x) => s + Number(x.row.paid), 0)
  const totalOwed = filtered.reduce((s, x) => s + Number(x.row.balance), 0)

  const activeCount = [search, from, to, ...extraFilters.map((f) => (extras[f.key] && extras[f.key] !== "all" ? "x" : ""))].filter(Boolean).length
  const clearFilters = () => { setSearch(""); setFrom(""); setTo(""); setExtras({}) }
  const onSort = (k: string) => { const n = toggleSort(k, sortKey, sortDir); setSortKey(n.key); setSortDir(n.direction) }

  const pdfOpts = (): PdfExportOptions => ({
    title: p.pdf.title,
    filename: p.pdf.filename,
    farmName,
    orientation: "landscape",
    fromDate: from || undefined,
    toDate: to || undefined,
    columns: [
      { header: "Sale ID" }, { header: "Date" }, { header: "Sale" }, { header: "Customer" },
      { header: p.quantityLabel, align: "right" }, { header: "Total", align: "right" }, { header: "Paid", align: "right" },
      { header: "Balance", align: "right" }, { header: "Method" }, { header: "Status" },
    ],
    rows: filtered.map(({ row }) => [
      row.reference, formatDateShort(row.date), row.product, row.customer, row.quantity ?? "",
      fmt(row.total), fmt(row.paid), fmt(row.balance), row.method ?? "", row.status,
    ]),
    totalsRow: ["", "", "", "TOTALS", totalQty.toLocaleString(), fmt(totalSales), fmt(totalPaid), fmt(totalOwed), "", ""],
    summaryLines: [`Total sales: ${fmt(totalSales)}  |  ${p.quantityLabel}: ${totalQty.toLocaleString()}  |  Transactions: ${filtered.length}`],
    headFillColor: p.pdf.headFillColor,
  })

  const exportPdf = async () => {
    if (filtered.length === 0) { toast({ title: "Nothing to export", description: "No sales match the current filters.", variant: "destructive" }); return }
    try { await exportTableToPdf(pdfOpts()) } catch {
      toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" })
    }
  }
  const emailReport = async () => {
    if (filtered.length === 0) { toast({ title: "Nothing to email", description: "No sales match the current filters.", variant: "destructive" }); return }
    setEmailing(true)
    try {
      const res = await emailTableAsPdf(pdfOpts())
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${res.recipient}.` })
      else toast({ title: "Email failed", description: res.message || "Could not send report.", variant: "destructive" })
    } finally { setEmailing(false) }
  }

  const openInvoice = (item: T, row: ModuleSaleRow) => {
    setInvoiceFor({ item, row })
    setInvoiceLines(null)
    const fallback: InvoiceLine[] = [{ description: row.product, quantity: 1, unitPrice: row.total, total: row.total }]
    if (!p.loadInvoiceLines) { setInvoiceLines(fallback); return }
    p.loadInvoiceLines(item)
      .then((lines) => setInvoiceLines(lines.length ? lines : fallback))
      .catch(() => setInvoiceLines(fallback))
  }
  const printInvoice = () => {
    const html = invoiceRef.current?.innerHTML
    const win = html ? window.open("", "_blank", "width=800,height=900") : null
    if (!win || !html) return
    win.document.write(`<html><head><title>Invoice ${invoiceFor?.row.reference ?? ""}</title><style>
      body{font-family:Arial,sans-serif;color:#0f172a;padding:24px} table{width:100%;border-collapse:collapse;margin-top:12px}
      th,td{padding:6px 8px;border-bottom:1px solid #e2e8f0;text-align:left;font-size:13px} .r{text-align:right}
      .muted{color:#64748b;font-size:12px} h2{margin:0}
    </style></head><body>${html}</body></html>`)
    win.document.close()
    win.print()
  }

  const invoiceButton = (item: T, row: ModuleSaleRow, icon = false) => icon ? (
    <Button variant="ghost" size="sm" onClick={() => openInvoice(item, row)} aria-label="Invoice" title="Invoice"><FileText className="h-4 w-4" /></Button>
  ) : (
    <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => openInvoice(item, row)}><FileText className="mr-2 h-4 w-4" /> Invoice</Button>
  )

  const extraSelect = (f: SalesExtraFilter<T>, value: string, onChange: (v: string) => void, mobile: boolean) => (
    <Select value={value || "all"} onValueChange={onChange}>
      <SelectTrigger className={mobile ? "h-12 text-base" : "w-[170px]"}><SelectValue /></SelectTrigger>
      <SelectContent className={mobile ? MOBILE_FILTER_SELECT_CONTENT_CLASS : undefined}>
        <SelectItem value="all">{f.allLabel}</SelectItem>
        {f.options.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
      </SelectContent>
    </Select>
  )

  const cards: { title: string; icon: LucideIcon; value: string; hint: string; cls?: string }[] = [
    { title: "Total Sales", icon: DollarSign, value: fmt(totalSales), hint: `${filtered.length} transactions` },
    { title: p.quantityLabel, icon: Package, value: totalQty.toLocaleString(), hint: p.quantityHint },
    { title: "Average Sale", icon: TrendingUp, value: fmt(filtered.length ? totalSales / filtered.length : 0), hint: "per transaction" },
    { title: "Balance", icon: Wallet, value: fmt(totalOwed), hint: "still owed", cls: totalOwed > 0 ? "text-amber-700" : "" },
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex min-w-0 items-start gap-3">
          <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg", p.accent.iconBg)}>
            <ShoppingCart className={cn("h-5 w-5", p.accent.iconText)} />
          </div>
          <div className="min-w-0">
            <h1 className="truncate text-xl font-bold text-slate-900 sm:text-2xl">Sales</h1>
            <p className="text-sm text-slate-600">{p.subtitle}</p>
          </div>
        </div>
        <div className="flex shrink-0 flex-col gap-2 sm:flex-row">
          {p.headerExtra}
          {p.addAction && (
            <Button asChild className={cn("h-11 w-full gap-2 sm:h-10 sm:w-auto", p.accent.button)}>
              <Link href={p.addAction.href}><Plus className="h-4 w-4" /> {p.addAction.label}</Link>
            </Button>
          )}
        </div>
      </div>

      {p.banner}

      {isMobile ? (
        <div className="w-full min-w-0 space-y-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <Input placeholder={p.searchPlaceholder} value={search} onChange={(e) => setSearch(e.target.value)} className="h-11 pl-10" />
          </div>
          <div className={MOBILE_FILTERS_TOOLBAR_ROW_CLASS}>
            <Sheet open={filtersOpen} onOpenChange={(o) => { setFiltersOpen(o); setDraft({ from, to, extras }) }}>
              <SheetTrigger asChild>
                <Button variant="outline" className={MOBILE_FILTERS_TRIGGER_BUTTON_CLASS}>
                  <Filter className="h-4 w-4" />
                  <span className="truncate">Filters</span>
                  {activeCount > 0 && (
                    <span className="ml-1 flex h-5 min-w-[20px] items-center justify-center rounded-full bg-orange-500 px-1.5 text-xs text-white">{activeCount}</span>
                  )}
                </Button>
              </SheetTrigger>
              <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                <MobileFilterSheetHeader />
                <MobileFilterSheetBody>
                  <div className="space-y-3">
                    <p className="text-sm font-medium text-slate-700">Date range</p>
                    <div className="flex flex-col gap-4">
                      <div className="min-w-0 space-y-2">
                        <label htmlFor="msales-from" className="text-xs font-medium text-slate-500">Start date</label>
                        <Input id="msales-from" type="date" value={draft.from} onChange={(e) => setDraft({ ...draft, from: e.target.value })} className="h-12 w-full min-w-0 text-base" />
                      </div>
                      <div className="min-w-0 space-y-2">
                        <label htmlFor="msales-to" className="text-xs font-medium text-slate-500">End date</label>
                        <Input id="msales-to" type="date" value={draft.to} onChange={(e) => setDraft({ ...draft, to: e.target.value })} className="h-12 w-full min-w-0 text-base" />
                      </div>
                    </div>
                  </div>
                  {extraFilters.map((f) => (
                    <div key={f.key} className="space-y-2">
                      <label className="text-sm font-medium text-slate-700">{f.label}</label>
                      {extraSelect(f, draft.extras[f.key] ?? "all", (v) => setDraft({ ...draft, extras: { ...draft.extras, [f.key]: v } }), true)}
                    </div>
                  ))}
                </MobileFilterSheetBody>
                <MobileFilterSheetFooter>
                  <div className="flex gap-3">
                    <Button type="button" variant="outline" className="h-12 flex-1" onClick={() => { clearFilters(); setFiltersOpen(false); toast({ title: "Filters cleared" }) }}>
                      Clear all
                    </Button>
                    <Button type="button" className="h-12 flex-1" onClick={() => { setFrom(draft.from); setTo(draft.to); setExtras(draft.extras); setFiltersOpen(false) }}>
                      Apply
                    </Button>
                  </div>
                </MobileFilterSheetFooter>
              </SheetContent>
            </Sheet>
            <Button variant="outline" size="sm" onClick={exportPdf} className="h-11 gap-2 px-4"><Download className="h-4 w-4" /> PDF</Button>
            <Button variant="outline" size="sm" onClick={emailReport} disabled={emailing} className="h-11 gap-2 px-4">
              {emailing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />} Email
            </Button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap items-end gap-3 rounded border bg-white p-3">
          <div className="w-full sm:w-[220px]">
            <Label className="text-xs text-slate-500">Search</Label>
            <Input placeholder={p.searchPlaceholder} value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
          <div>
            <Label className="text-xs text-slate-500">From</Label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-[160px]" />
          </div>
          <div>
            <Label className="text-xs text-slate-500">To</Label>
            <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-[160px]" />
          </div>
          {extraFilters.map((f) => (
            <div key={f.key}>
              <Label className="text-xs text-slate-500">{f.label}</Label>
              {extraSelect(f, extras[f.key] ?? "all", (v) => setExtras({ ...extras, [f.key]: v }), false)}
            </div>
          ))}
          <div className="ml-auto flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={exportPdf} className="gap-2"><Download className="h-4 w-4" /> Export PDF</Button>
            <Button variant="outline" size="sm" onClick={emailReport} disabled={emailing} className="gap-2">
              {emailing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />} Email Report
            </Button>
            <Button variant="outline" onClick={clearFilters}>Reset filters</Button>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        {cards.map((c) => (
          <Card key={c.title} className="bg-white">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">{c.title}</CardTitle>
              <c.icon className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className={cn("break-words text-xl font-bold leading-tight sm:text-2xl", c.cls)}>{c.value}</div>
              <p className="text-xs text-muted-foreground">{c.hint}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {p.loading ? (
        <Card className="bg-white"><CardContent className="py-12 text-center"><Loader2 className={cn("mx-auto h-6 w-6 animate-spin", p.accent.spinner)} /></CardContent></Card>
      ) : p.items.length === 0 ? (
        <Card className="bg-white">
          <CardContent className="py-12 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-slate-50"><ShoppingCart className="h-8 w-8 text-slate-400" /></div>
            <h3 className="mb-2 text-lg font-semibold text-slate-900">{p.emptyTitle}</h3>
            <p className="text-slate-600">{p.emptyText}</p>
          </CardContent>
        </Card>
      ) : filtered.length === 0 ? (
        <Card className="bg-white">
          <CardContent className="space-y-3 py-12 text-center">
            <p className="text-slate-600">No sales match the current filters.</p>
            <Button variant="outline" onClick={clearFilters}>Reset filters</Button>
          </CardContent>
        </Card>
      ) : (
        <Card className="overflow-hidden bg-white">
          <CardHeader>
            <CardTitle>Recent Sales</CardTitle>
            <CardDescription>View and manage your sales transactions</CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            {isMobile && !showTable ? (
              <div className="space-y-3 px-3 pb-3">
                {pg.pageItems.map(({ item, row }, idx) => (
                  <Collapsible key={row.key} defaultOpen className={cn("group overflow-hidden rounded-xl border shadow-sm", idx % 2 === 0 ? "border-amber-300 bg-amber-100" : "border-slate-200 bg-white")}>
                    <div className="p-4">
                      <CollapsibleTrigger asChild>
                        <div className="flex cursor-pointer items-start justify-between gap-3">
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center gap-2">
                              <span className="text-xs tabular-nums text-slate-500">{row.reference}</span>
                              <span className="font-semibold text-slate-900">{formatDateShort(row.date)}</span>
                              <span className="text-slate-500">•</span>
                              <span className="truncate text-slate-600">{row.customer}</span>
                            </div>
                            <div className="mt-1 flex items-baseline gap-3">
                              <span className="text-lg font-bold text-emerald-600">{fmt(row.total)}</span>
                              <span className="truncate text-xs text-slate-500">{row.product}</span>
                            </div>
                          </div>
                          <ChevronDown className="h-5 w-5 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
                        </div>
                      </CollapsibleTrigger>
                      <CollapsibleContent>
                        <div className="mt-4 space-y-2 border-t border-slate-100 pt-4 text-sm">
                          <div className="grid grid-cols-2 gap-2">
                            <div><span className="text-slate-500">{p.quantityLabel.replace(/^Total /, "")}</span> <span className="font-medium">{row.quantity ?? "—"}</span></div>
                            {(row.details ?? []).map((d) => (
                              <div key={d.label}><span className="text-slate-500">{d.label}</span> <span className="font-medium">{d.value}</span></div>
                            ))}
                            <div><span className="text-slate-500">Paid</span> <span className="font-medium tabular-nums text-emerald-700">{fmt(row.paid)}</span></div>
                            <div><span className="text-slate-500">Balance</span> <span className={cn("font-medium tabular-nums", row.balance > 0 ? "text-amber-700" : "text-slate-400")}>{fmt(row.balance)}</span></div>
                            <div><span className="text-slate-500">Method</span> <span className="font-medium">{row.method ?? "—"}</span></div>
                            <div className="flex items-center gap-2"><span className="text-slate-500">Status</span> <SaleStatusBadge status={row.status} /></div>
                          </div>
                          <div className="grid grid-cols-2 gap-2 pt-2">
                            {p.renderCardActions(item, row)}
                            {invoiceButton(item, row)}
                            {p.renderCardActionsEnd?.(item, row)}
                          </div>
                        </div>
                      </CollapsibleContent>
                    </div>
                  </Collapsible>
                ))}
                <div className="border-t bg-slate-50/50 px-4 py-3">
                  <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowTable(true)}>
                    View table format <ChevronDown className="ml-1 h-4 w-4" />
                  </Button>
                </div>
              </div>
            ) : (
              <div className="overflow-x-auto pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                {isMobile && (
                  <div className="sticky top-0 z-10 flex items-center justify-between gap-2 border-b bg-slate-50 px-4 py-2">
                    <span className="text-xs text-slate-600">Table • Scroll → for more</span>
                    <Button variant="ghost" size="sm" onClick={() => setShowTable(false)}><ChevronUp className="mr-1 h-4 w-4" /> Cards</Button>
                  </div>
                )}
                <Table className="w-full min-w-[1100px]">
                  <TableHeader>
                    <TableRow>
                      <SortableHeader label="Sale ID" sortKey="reference" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Sale" sortKey="product" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Customer" sortKey="customer" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label={p.quantityLabel.replace(/^Total /, "")} sortKey="quantity" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Total" sortKey="total" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Paid" sortKey="paid" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Balance" sortKey="balance" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Method" sortKey="method" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <SortableHeader label="Status" sortKey="status" currentSort={sortKey} currentDirection={sortDir} onSort={onSort} />
                      <TableHead className="min-w-[140px] whitespace-nowrap">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pg.pageItems.map(({ item, row }) => (
                      <TableRow key={row.key}>
                        <TableCell className="whitespace-nowrap tabular-nums text-slate-500">{row.reference}</TableCell>
                        <TableCell className="whitespace-nowrap">{fmtDateTime(row.date)}</TableCell>
                        <TableCell>{row.product}</TableCell>
                        <TableCell>{row.customer}</TableCell>
                        <TableCell className="tabular-nums">{row.quantity ?? "—"}</TableCell>
                        <TableCell className="font-medium tabular-nums">{fmt(row.total)}</TableCell>
                        <TableCell className="tabular-nums text-emerald-700">{fmt(row.paid)}</TableCell>
                        <TableCell className={cn("tabular-nums", row.balance > 0 ? "font-semibold text-amber-700" : "text-slate-400")}>{fmt(row.balance)}</TableCell>
                        <TableCell>{row.method ? <Badge variant="outline" className="w-fit">{row.method}</Badge> : "—"}</TableCell>
                        <TableCell><SaleStatusBadge status={row.status} /></TableCell>
                        <TableCell className="whitespace-nowrap">
                          <div className="flex items-center gap-1">
                            {p.renderTableActions(item, row)}
                            {invoiceButton(item, row, true)}
                            {p.renderTableActionsEnd?.(item, row)}
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
            <DataPagination {...pg.paginationProps} variant="records" />
          </CardContent>
        </Card>
      )}

      <Dialog open={!!invoiceFor} onOpenChange={(o) => { if (!o) setInvoiceFor(null) }}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Invoice</DialogTitle>
            <DialogDescription>Review the invoice and print or save a PDF for your customer.</DialogDescription>
          </DialogHeader>
          {invoiceFor && (
            <div ref={invoiceRef} className="space-y-3 text-sm">
              <div className="flex items-start justify-between gap-4">
                <div><h2 className="text-lg font-bold">{farmName}</h2><div className="muted text-xs text-slate-500">Invoice</div></div>
                <div className="text-right">
                  <div className="font-semibold">{invoiceFor.row.reference}</div>
                  <div className="muted text-xs text-slate-500">{formatDateShort(invoiceFor.row.date)}</div>
                </div>
              </div>
              <div><span className="text-slate-500">Bill to: </span><span className="font-medium">{invoiceFor.row.customer}</span></div>
              {invoiceLines === null ? (
                <div className="flex items-center gap-2 py-6 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : (
                <table className="w-full border-collapse">
                  <thead>
                    <tr className="border-b text-left text-xs text-slate-500">
                      <th className="py-1.5">Description</th><th className="r py-1.5 text-right">Qty</th>
                      <th className="r py-1.5 text-right">Unit price</th><th className="r py-1.5 text-right">Amount</th>
                    </tr>
                  </thead>
                  <tbody>
                    {invoiceLines.map((l, i) => (
                      <tr key={i} className="border-b">
                        <td className="py-1.5">{l.description}</td>
                        <td className="r py-1.5 text-right tabular-nums">{l.quantity}</td>
                        <td className="r py-1.5 text-right tabular-nums">{fmt(l.unitPrice)}</td>
                        <td className="r py-1.5 text-right tabular-nums">{fmt(l.total)}</td>
                      </tr>
                    ))}
                    <tr><td colSpan={3} className="r py-1.5 text-right font-semibold">Total</td><td className="r py-1.5 text-right font-semibold tabular-nums">{fmt(invoiceFor.row.total)}</td></tr>
                    <tr><td colSpan={3} className="r py-1 text-right text-slate-500">Paid</td><td className="r py-1 text-right tabular-nums">{fmt(invoiceFor.row.paid)}</td></tr>
                    <tr><td colSpan={3} className="r py-1 text-right text-slate-500">Balance due</td><td className="r py-1 text-right font-semibold tabular-nums">{fmt(invoiceFor.row.balance)}</td></tr>
                  </tbody>
                </table>
              )}
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setInvoiceFor(null)}>Close</Button>
            <Button onClick={printInvoice} disabled={invoiceLines === null} className={cn("gap-2", p.accent.button)}><Printer className="h-4 w-4" /> Print</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

"use client"

// Generic Cash Flow — shows cash in/out by account for a date range.
// Design matches the Poultry Cash Flow page for standardization.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { useIsMobile } from "@/hooks/use-mobile"
import { ListFilters } from "@/components/ui/list-filters"
import {
  Wallet, TrendingUp, TrendingDown, DollarSign, Info, ChevronDown, ExternalLink,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { getCashSummaryReport, type GenericCashSummaryReport } from "@/lib/api/generic"

const DEFAULT = defaultReportRange()

export default function GenericCashFlowPage() {
  const isMobile = useIsMobile()
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [loading, setLoading] = useState(true)
  const [report, setReport] = useState<GenericCashSummaryReport | null>(null)
  const [dateFrom, setDateFrom] = useState(DEFAULT.from)
  const [dateTo, setDateTo] = useState(DEFAULT.to)
  const [search, setSearch] = useState("")

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getCashSummaryReport(dateFrom, dateTo)
      setReport(data)
    } catch (e: any) {
      toast({ title: "Could not load cash flow", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }, [dateFrom, dateTo, toast])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, load])

  const totals = useMemo(() => {
    if (!report) return { cashIn: 0, cashOut: 0, net: 0 }
    const cashIn = report.accounts.reduce((s, a) => s + a.periodCashIn, 0)
    const cashOut = report.accounts.reduce((s, a) => s + a.periodCashOut, 0)
    return { cashIn, cashOut, net: cashIn - cashOut }
  }, [report])

  const filteredAccounts = useMemo(() => {
    if (!report) return []
    if (!search.trim()) return report.accounts
    const q = search.trim().toLowerCase()
    return report.accounts.filter(
      (a) => a.accountName.toLowerCase().includes(q) || a.accountType.toLowerCase().includes(q)
    )
  }, [report, search])

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">

          <div className="mb-3">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-5 w-5 text-emerald-600" />
                Cash Flow
              </h1>
              <p className="mt-1 text-xs text-slate-500">Money in and out across all cash accounts.</p>
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button asChild size="sm" variant="outline" className="whitespace-nowrap">
                <Link href="/generic-cash">
                  <ExternalLink className="h-4 w-4 mr-1" /> View Cash Accounts
                </Link>
              </Button>
            </div>
          </div>

          {/* Collapsible explanation panel */}
          <Collapsible defaultOpen={!isMobile} className="group mb-3 rounded-lg border border-slate-200 bg-white">
            <CollapsibleTrigger asChild>
              <button
                type="button"
                className="flex w-full items-start justify-between gap-2 p-3 text-left"
              >
                <span className="text-sm font-medium text-slate-900">
                  Where your money came from and went.
                </span>
                <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-slate-400 transition-transform group-data-[state=open]:rotate-180" />
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <p className="px-3 pb-3 text-xs leading-snug text-slate-600">
                This report shows cash movement across all your cash accounts for the selected period.
                Each account&apos;s cash in, cash out, and net change are displayed alongside its current balance.
                Transfers between your own accounts are managed in{" "}
                <Link href="/generic-cash-transfers" className="underline">Cash Transfers</Link>.
              </p>
            </CollapsibleContent>
          </Collapsible>

          <ListFilters
            search={search} setSearch={setSearch}
            searchPlaceholder="Search account name…"
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
          />

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading cash flow…</CardContent></Card>
          ) : report && (
            <div className="space-y-3">

              {/* Top row: KPI tiles with tooltips */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                <Tile label="Cash at Hand" value={gh(report.totalCashAtHand)}
                      icon={<Wallet className="h-3.5 w-3.5" />}
                      tip="Sum of all active cash account balances — what you currently hold across all accounts." />
                <Tile label="Cash In" value={gh(totals.cashIn)}
                      tone="text-emerald-700"
                      icon={<TrendingUp className="h-3.5 w-3.5" />}
                      tip="Total money received across all cash accounts during the selected period." />
                <Tile label="Cash Out" value={gh(totals.cashOut)}
                      tone="text-red-700"
                      icon={<TrendingDown className="h-3.5 w-3.5" />}
                      tip="Total money paid out across all cash accounts during the selected period." />
                <Tile label="Net Cash Flow" value={gh(totals.net)}
                      tone={totals.net >= 0 ? "text-emerald-700" : "text-red-700"}
                      icon={<DollarSign className="h-3.5 w-3.5" />}
                      tip="Cash In minus Cash Out. Positive means you received more than you spent in this period." />
              </div>

              {/* Identity line */}
              <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs tabular-nums text-slate-600">
                  <span className="text-emerald-700">Cash in <b>{gh(totals.cashIn)}</b></span>
                  <span className="text-red-700">− Cash out <b>{gh(totals.cashOut)}</b></span>
                  <span>= Net <b className={totals.net >= 0 ? "text-emerald-700" : "text-red-700"}>{gh(totals.net)}</b></span>
                </div>
              </div>

              {/* Accounts table */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Cash Accounts</CardTitle>
                  <CardDescription className="text-xs">
                    Movement by account for the selected period.
                  </CardDescription>
                </CardHeader>
                <CardContent className="p-0 md:p-2">
                  {filteredAccounts.length === 0 ? (
                    <p className="px-4 py-8 text-center text-sm text-slate-500">
                      No cash accounts found. Set up accounts in Cash &amp; Accounts.
                    </p>
                  ) : (
                    <MobileCardList
                      defaultOpen
                      striped
                      stripeAccent="blue"
                      items={filteredAccounts}
                      getKey={(a: any) => a.genericCashAccountId}
                      primary={(a: any) => a.accountName}
                      secondary={(a: any) => a.accountType}
                      highlights={(a: any) => [
                        { label: "Cash in", value: gh(a.periodCashIn), accent: "emerald" },
                        { label: "Cash out", value: gh(a.periodCashOut), accent: "rose" },
                        { label: "Balance", value: gh(a.currentBalance), accent: "blue" },
                      ]}
                      details={(a: any) => [
                        { label: "Type", value: a.accountType },
                        { label: "Net", value: gh(a.periodCashIn - a.periodCashOut) },
                        { label: "Status", value: a.isActive ? "Active" : "Inactive" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Account</TableHead>
                                <TableHead>Type</TableHead>
                                <TableHead className="text-right">Cash in</TableHead>
                                <TableHead className="text-right">Cash out</TableHead>
                                <TableHead className="text-right">Net</TableHead>
                                <TableHead className="text-right">Balance</TableHead>
                                <TableHead>Status</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {filteredAccounts.map((a) => (
                                <TableRow key={a.genericCashAccountId}>
                                  <TableCell className="font-medium">{a.accountName}</TableCell>
                                  <TableCell className="text-sm text-slate-500">{a.accountType}</TableCell>
                                  <TableCell className="text-right tabular-nums text-emerald-700">{gh(a.periodCashIn)}</TableCell>
                                  <TableCell className="text-right tabular-nums text-red-600">{gh(a.periodCashOut)}</TableCell>
                                  <TableCell className={cn("text-right tabular-nums font-medium", a.periodCashIn - a.periodCashOut >= 0 ? "text-emerald-700" : "text-red-600")}>
                                    {gh(a.periodCashIn - a.periodCashOut)}
                                  </TableCell>
                                  <TableCell className="text-right tabular-nums font-semibold">{gh(a.currentBalance)}</TableCell>
                                  <TableCell>
                                    <Badge className={a.isActive ? "bg-emerald-100 text-emerald-800" : "bg-slate-100 text-slate-600"}>
                                      {a.isActive ? "Active" : "Inactive"}
                                    </Badge>
                                  </TableCell>
                                </TableRow>
                              ))}
                              {filteredAccounts.length > 0 && (
                                <TableRow className="bg-slate-50 font-semibold">
                                  <TableCell colSpan={2}>Total</TableCell>
                                  <TableCell className="text-right tabular-nums text-emerald-700">{gh(totals.cashIn)}</TableCell>
                                  <TableCell className="text-right tabular-nums text-red-600">{gh(totals.cashOut)}</TableCell>
                                  <TableCell className={cn("text-right tabular-nums", totals.net >= 0 ? "text-emerald-700" : "text-red-600")}>{gh(totals.net)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{gh(report.totalCashAtHand)}</TableCell>
                                  <TableCell></TableCell>
                                </TableRow>
                              )}
                            </TableBody>
                          </Table>
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </div>
          )}
        </main>
      </div>
    </div>
    </TooltipProvider>
  )
}

/** Compact KPI card with a tooltip on every figure — matches poultry Tile. */
function Tile({
  label, value, tone, tip, icon,
}: {
  label: string; value: string; tone?: string; tip: string
  icon?: React.ReactNode
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
          {icon}
          <span className="truncate">{label}</span>
          <Tooltip>
            <TooltipTrigger asChild>
              <button type="button" className="ml-auto shrink-0 text-slate-400 hover:text-slate-600">
                <Info className="h-3.5 w-3.5" />
              </button>
            </TooltipTrigger>
            <TooltipContent className="max-w-xs text-xs leading-snug">{tip}</TooltipContent>
          </Tooltip>
        </div>
        <div className={cn("mt-1 text-lg font-semibold tabular-nums", tone ?? "text-slate-900")}>
          {value}
        </div>
      </CardContent>
    </Card>
  )
}

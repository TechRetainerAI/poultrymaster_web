"use client"

// Billing Runs — the button that raises this period's invoices.
//
// There is no scheduler anywhere in this codebase. Billing is therefore an
// explicit three-step state machine, modelled on the payroll run: preview what
// is due, generate it, then read the history. That is a feature, not a
// shortcoming — an owner sees exactly what they are about to charge before
// anyone is charged.
//
// Two guarantees worth knowing while reading this page:
//   - Preview and generate share the same selection in SQL, so what is listed
//     here is exactly what will be raised.
//   - Generating twice raises nothing twice. A partial unique index on the
//     subscription and its billing period makes double-billing impossible even
//     if two people press the button at the same moment.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Loader2, Play, Receipt, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  previewBilling, generateBilling, getBillingRuns, getBusinessTemplate, getModuleSettings,
  type BillingPreviewRow, type BillingRun,
} from "@/lib/api/generic-subscriptions"
import { templateLabels } from "@/lib/generic/template-labels"

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericBillingRunsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [asOf, setAsOf] = useState(today())
  const [preview, setPreview] = useState<BillingPreviewRow[]>([])
  const [runs, setRuns] = useState<BillingRun[]>([])
  const [industry, setIndustry] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [previewing, setPreviewing] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [confirmOpen, setConfirmOpen] = useState(false)

  const labels = templateLabels(industry)

  const loadPreview = async (date: string) => {
    setPreviewing(true)
    try {
      setPreview(await previewBilling(date))
    } catch (e: any) {
      toast({
        title: "Could not work out what is due",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setPreviewing(false)
    }
  }

  const load = async () => {
    setLoading(true)
    try {
      const [runRows, template] = await Promise.all([
        getBillingRuns(),
        getBusinessTemplate().catch(() => null),
      ])
      setRuns(runRows)
      setIndustry(template?.genericIndustryTemplate ?? null)
      await loadPreview(asOf)
    } catch (e: any) {
      toast({
        title: "Could not load billing runs",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    getModuleSettings()
      .then((s) => {
        if (!s.enableSubscriptions) router.replace("/generic-dashboard")
      })
      .catch(() => {})
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  // A period already invoiced is shown, greyed, rather than hidden: "why is
  // this customer not in the list" is a worse question than seeing them marked
  // as already billed.
  const toRaise = useMemo(() => preview.filter((p) => !p.alreadyBilled), [preview])
  const totalToRaise = useMemo(
    () => toRaise.reduce((sum, p) => sum + p.invoiceAmount, 0),
    [toRaise],
  )
  const pg = usePagination(runs)

  const onGenerate = async () => {
    setConfirmOpen(false)
    setGenerating(true)
    try {
      const run = await generateBilling(asOf)
      const n = run?.totalInvoicesGenerated ?? 0
      toast({
        title:
          n === 0
            ? "Nothing new to raise."
            : `${n} ${n === 1 ? labels.invoice.toLowerCase() : labels.invoicePlural.toLowerCase()} raised as drafts.`,
        description:
          n > 0
            ? `Approve them on ${labels.invoicePlural} to make them owed.`
            : undefined,
      })
      await load()
    } catch (e: any) {
      toast({
        title: "Billing run failed",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setGenerating(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Receipt className="h-6 w-6 text-indigo-600" /> Billing runs
              </h1>
              <p className="text-sm text-slate-500">
                Raise the {labels.invoicePlural.toLowerCase()} that are due. Nothing happens
                automatically.
              </p>
            </div>
            <div className="flex gap-2">
              <Link href="/generic-subscriptions">
                <Button variant="outline" className="h-11 sm:h-10">
                  {labels.subscriptionPlural}
                </Button>
              </Link>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : (
            <>
              {/* ---------- what is due ---------- */}
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-base">What is due</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="flex flex-wrap items-end gap-3">
                    <div>
                      <Label>Bill everything due up to</Label>
                      <Input
                        type="date"
                        className="w-[180px]"
                        value={asOf}
                        onChange={(e) => {
                          setAsOf(e.target.value)
                          if (e.target.value) loadPreview(e.target.value)
                        }}
                      />
                    </div>
                    <Button
                      variant="outline"
                      className="h-10"
                      onClick={() => loadPreview(asOf)}
                      disabled={previewing}
                    >
                      {previewing ? (
                        <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                      ) : (
                        <RefreshCw className="h-4 w-4 mr-1" />
                      )}
                      Refresh
                    </Button>
                    <div className="flex-1" />
                    <Button
                      className="h-11 sm:h-10"
                      disabled={generating || toRaise.length === 0}
                      onClick={() => setConfirmOpen(true)}
                    >
                      {generating ? (
                        <>
                          <Loader2 className="h-4 w-4 mr-1 animate-spin" /> Raising…
                        </>
                      ) : (
                        <>
                          <Play className="h-4 w-4 mr-1" /> Raise {toRaise.length}{" "}
                          {toRaise.length === 1
                            ? labels.invoice.toLowerCase()
                            : labels.invoicePlural.toLowerCase()}
                        </>
                      )}
                    </Button>
                  </div>

                  {preview.length === 0 ? (
                    <p className="text-sm text-slate-500 py-4">
                      Nothing is due on or before {asOf}.
                    </p>
                  ) : (
                    <>
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>{labels.customer}</TableHead>
                              <TableHead>{labels.plan}</TableHead>
                              <TableHead>Period</TableHead>
                              <TableHead>Due</TableHead>
                              <TableHead className="text-right">Amount</TableHead>
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {preview.map((p) => (
                              <TableRow
                                key={`${p.genericSubscriptionId}-${p.billingPeriodStart}`}
                                className={p.alreadyBilled ? "opacity-50" : ""}
                              >
                                <TableCell className="font-medium">
                                  {p.customerName ?? `#${p.genericCustomerId}`}
                                </TableCell>
                                <TableCell>{p.serviceName ?? "—"}</TableCell>
                                <TableCell className="whitespace-nowrap">
                                  {p.billingPeriodStart} → {p.billingPeriodEnd}
                                </TableCell>
                                <TableCell>{p.dueDate}</TableCell>
                                <TableCell className="text-right">{fmt(p.invoiceAmount)}</TableCell>
                                <TableCell className="text-right">
                                  {p.alreadyBilled ? (
                                    <Badge variant="outline">Already billed</Badge>
                                  ) : (
                                    <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">
                                      Will be raised
                                    </Badge>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                      <p className="text-sm text-slate-600">
                        {toRaise.length} to raise, {fmt(totalToRaise)} in total. They are created as{" "}
                        <strong>drafts</strong> — approving them is what makes them owed.
                      </p>
                    </>
                  )}
                </CardContent>
              </Card>

              {/* ---------- history ---------- */}
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-base">Past runs</CardTitle>
                </CardHeader>
                <CardContent className="p-0">
                  {runs.length === 0 ? (
                    <p className="text-sm text-slate-500 px-6 pb-6">No billing run yet.</p>
                  ) : (
                    <MobileCardList
                      items={pg.pageItems}
                      getKey={(r) => r.genericBillingRunId}
                      primary={(r) => new Date(r.billingRunDate).toLocaleString()}
                      secondary={(r) => (
                        <span>
                          {r.totalInvoicesGenerated} raised · {r.totalSkipped} skipped
                        </span>
                      )}
                      trailing={(r) => <Badge variant="outline">{r.status}</Badge>}
                      details={(r) => [
                        { label: "As of", value: r.asOfDate },
                        { label: "Checked", value: r.totalSubscriptionsChecked },
                        { label: "Raised", value: r.totalInvoicesGenerated },
                        { label: "Skipped", value: r.totalSkipped },
                        { label: "By", value: r.createdBy ?? "—" },
                      ]}
                      pagination={pg.paginationProps}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Run</TableHead>
                                <TableHead>As of</TableHead>
                                <TableHead className="text-right">Checked</TableHead>
                                <TableHead className="text-right">Raised</TableHead>
                                <TableHead className="text-right">Skipped</TableHead>
                                <TableHead>By</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pg.pageItems.map((r) => (
                                <TableRow key={r.genericBillingRunId}>
                                  <TableCell>{new Date(r.billingRunDate).toLocaleString()}</TableCell>
                                  <TableCell>{r.asOfDate}</TableCell>
                                  <TableCell className="text-right">
                                    {r.totalSubscriptionsChecked}
                                  </TableCell>
                                  <TableCell className="text-right font-semibold">
                                    {r.totalInvoicesGenerated}
                                  </TableCell>
                                  <TableCell className="text-right">{r.totalSkipped}</TableCell>
                                  <TableCell>{r.createdBy ?? "—"}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                          <DataPagination {...pg.paginationProps} />
                        </div>
                      }
                    />
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>
              Raise {toRaise.length}{" "}
              {toRaise.length === 1
                ? labels.invoice.toLowerCase()
                : labels.invoicePlural.toLowerCase()}
              ?
            </DialogTitle>
            <DialogDescription>
              {fmt(totalToRaise)} in total, everything due on or before {asOf}. They are created as
              drafts, so nobody is owed anything until you approve them. Running this again later
              will not bill the same period twice.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setConfirmOpen(false)}>
              Not now
            </Button>
            <Button onClick={onGenerate}>
              <Play className="h-4 w-4 mr-1" /> Raise them
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

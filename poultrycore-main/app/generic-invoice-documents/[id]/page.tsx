"use client"

// Invoice Document Detail — view, print, download, issue, and void an invoice.
//
// The invoice renders using GenericInvoiceDocument (the professional PDF-ready
// component). Actions depend on the document's status:
//   Draft  → Issue, Edit, Void
//   Issued → Void, Print, Download
//   Voided → View only (read-only history)

import { useEffect, useRef, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  ArrowLeft, Check, Download, Loader2, Printer, FileText, Ban, Clock, ExternalLink, Wallet, Mail,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getProfile, getCashAccounts, type GenericCompanyProfile, type GenericCashAccount } from "@/lib/api/generic"
import {
  getInvoiceDocument, issueInvoice, voidInvoice,
  type InvoiceDocumentDetail,
} from "@/lib/api/generic-invoice-documents"
import {
  listPayments, type PaymentHistoryRow, type OpenDocumentRow, type PartyBalanceRow,
} from "@/lib/api/balances"
import { RecordPaymentDialog, type CashAccountOption } from "@/components/balances/record-payment-dialog"
import {
  GenericInvoiceDocument, GENERIC_INVOICE_PRINT_STYLES,
  type InvoiceCompanyInfo,
} from "@/components/generic/generic-invoice-document"
import { useFmt } from "@/lib/currency"
import { fmtDateTime } from "@/lib/utils/company-datetime"

function statusColor(s: string): string {
  switch (s) {
    case "Draft":   return "bg-slate-100 text-slate-700"
    case "Issued":  return "bg-emerald-100 text-emerald-800"
    case "Voided":  return "bg-rose-100 text-rose-800"
    default:        return "bg-slate-100 text-slate-700"
  }
}

export default function InvoiceDocumentDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const docId = Number(params.id)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()
  const printRef = useRef<HTMLDivElement>(null)

  const [invoice, setInvoice] = useState<InvoiceDocumentDetail | null>(null)
  const [company, setCompany] = useState<InvoiceCompanyInfo | null>(null)
  const [loading, setLoading] = useState(true)
  const [acting, setActing] = useState(false)

  // Void dialog
  const [showVoid, setShowVoid] = useState(false)
  const [voidReason, setVoidReason] = useState("")
  // Payment
  const [showPayment, setShowPayment] = useState(false)
  const [cashAccounts, setCashAccounts] = useState<CashAccountOption[]>([])
  const [payments, setPayments] = useState<PaymentHistoryRow[]>([])

  const load = async () => {
    setLoading(true)
    try {
      const [inv, profile, accounts] = await Promise.all([
        getInvoiceDocument(docId),
        getProfile().catch(() => null),
        getCashAccounts().catch(() => []),
      ])
      setInvoice(inv)
      setCompany({
        name: activeFarmName || "Company",
        address: profile?.mainLocation,
        phone: profile?.phoneNumber,
        email: null,
      })
      setCashAccounts(accounts.map((a) => ({
        id: a.genericCashAccountId,
        name: a.accountName,
        currentBalance: a.currentBalance,
        allowNegativeBalance: a.allowNegativeBalance,
      })))
      // Load payment history for this sale
      if (inv?.genericSaleId) {
        const payHist = await listPayments("generic", "customer", {
          documentId: inv.genericSaleId,
        }).catch(() => [])
        setPayments(payHist)
      }
    } catch (e: any) {
      toast({ title: "Could not load invoice", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, docId, router])

  const onIssue = async () => {
    setActing(true)
    try {
      await issueInvoice(docId)
      toast({ title: `Invoice ${invoice?.invoiceNumber} issued`, description: "It is now a formal billing document." })
      await load()
    } catch (e: any) {
      toast({ title: "Could not issue invoice", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  const onVoid = async () => {
    if (!voidReason.trim()) return
    setActing(true)
    try {
      await voidInvoice(docId, voidReason.trim())
      setShowVoid(false)
      toast({ title: `Invoice ${invoice?.invoiceNumber} voided` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not void invoice", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  const onPrint = () => {
    if (!printRef.current) return
    const w = window.open("", "_blank", "width=900,height=1100")
    if (!w) return
    w.document.write(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${invoice?.invoiceNumber ?? "Invoice"}</title><style>${GENERIC_INVOICE_PRINT_STYLES}</style></head><body>${printRef.current.innerHTML}</body></html>`)
    w.document.close()
    // Let styles render before triggering print
    setTimeout(() => { w.print() }, 300)
  }

  const onDownload = () => {
    // Same approach as print but triggers save-as-PDF via print dialog
    onPrint()
  }

  // Build the party and singleDocument objects for the payment dialog
  const paymentParty: PartyBalanceRow | null = invoice ? {
    partyId: 0, // We'll look up from customer — the dialog loads open docs itself
    partyName: invoice.customerBillingName || "Customer",
    totalBalance: invoice.balance,
    openDocumentCount: 1,
    overdueAmount: invoice.isOverdue ? invoice.balance : 0,
    paymentTermsDays: 0,
    totalInvoiced: invoice.totalAmount,
    totalPaid: invoice.amountPaid,
  } : null

  const paymentDocument: OpenDocumentRow | null = invoice ? {
    documentType: "Sale",
    documentId: invoice.genericSaleId,
    reference: invoice.saleReceiptNumber || invoice.invoiceNumber,
    documentDate: invoice.saleDate || invoice.issueDate,
    label: invoice.invoiceNumber,
    totalAmount: invoice.totalAmount,
    amountPaid: invoice.amountPaid,
    balance: invoice.balance,
    dueDate: invoice.dueDate,
    ageDays: invoice.daysUntilDue ? Math.abs(invoice.daysUntilDue) : 0,
    status: invoice.balance <= 0 ? "Paid" : invoice.amountPaid > 0 ? "Partial" : "Unpaid",
    isOverdue: invoice.isOverdue,
  } : null

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-invoices" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to invoices
          </Link>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !invoice ? (
            <Card><CardContent className="py-8 text-center text-slate-500">Invoice not found.</CardContent></Card>
          ) : (
            <>
              {/* Action bar */}
              <div className="mb-4 flex items-start justify-between flex-wrap gap-2">
                <div>
                  <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                    <FileText className="h-6 w-6 text-indigo-600" />
                    {invoice.invoiceNumber}
                    <Badge className={statusColor(invoice.documentStatus)}>{invoice.documentStatus}</Badge>
                  </h1>
                  <p className="text-sm text-slate-500">
                    {invoice.customerBillingName || "—"} · {fmt(invoice.totalAmount)}
                    {invoice.balance > 0 && <span className="text-rose-700"> · {fmt(invoice.balance)} outstanding</span>}
                  </p>
                </div>
                <div className="flex gap-2 flex-wrap">
                  {invoice.documentStatus === "Draft" && (
                    <Button onClick={onIssue} disabled={acting} className="bg-emerald-600 hover:bg-emerald-700">
                      {acting ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Check className="h-4 w-4 mr-1" />}
                      Issue Invoice
                    </Button>
                  )}
                  {invoice.documentStatus === "Issued" && invoice.balance > 0 && (
                    <Button onClick={() => setShowPayment(true)} className="bg-indigo-600 hover:bg-indigo-700">
                      <Wallet className="h-4 w-4 mr-1" /> Receive Payment
                    </Button>
                  )}
                  {invoice.documentStatus !== "Voided" && (
                    <Button variant="outline" className="text-rose-600 hover:text-rose-700" onClick={() => setShowVoid(true)} disabled={acting}>
                      <Ban className="h-4 w-4 mr-1" /> Void
                    </Button>
                  )}
                  <Button variant="outline" onClick={onPrint}>
                    <Printer className="h-4 w-4 mr-1" /> Print
                  </Button>
                  <Button variant="outline" onClick={onDownload}>
                    <Download className="h-4 w-4 mr-1" /> Download
                  </Button>
                  {invoice.documentStatus === "Issued" && (
                    <Button variant="outline" onClick={() => {
                      const customer = invoice.customerBillingName || "Customer"
                      const companyName = company?.name || "Our Company"
                      const subject = encodeURIComponent(`Invoice ${invoice.invoiceNumber} — ${fmt(invoice.totalAmount)}`)
                      const lines = invoice.lines?.map((l) =>
                        `  - ${l.description || l.productName || l.serviceName || "Item"} x${l.quantity} @ ${fmt(l.unitPrice)} = ${fmt(l.lineTotal)}`
                      ).join("\n") || ""
                      const body = encodeURIComponent(
                        `Dear ${customer},\n\n` +
                        `Please find your invoice details below:\n\n` +
                        `Invoice: ${invoice.invoiceNumber}\n` +
                        `Date: ${invoice.issueDate}\n` +
                        `Due: ${invoice.dueDate ?? "Immediately"}\n` +
                        `Total: ${fmt(invoice.totalAmount)}\n` +
                        `Paid: ${fmt(invoice.amountPaid)}\n` +
                        `Balance due: ${fmt(invoice.balance)}\n\n` +
                        (lines ? `Items:\n${lines}\n\n` : "") +
                        (invoice.paymentInstructions ? `Payment instructions:\n${invoice.paymentInstructions}\n\n` : "") +
                        `Thank you for your business.\n\n` +
                        `${companyName}`
                      )
                      const to = invoice.customerBillingEmail ? encodeURIComponent(invoice.customerBillingEmail) : ""
                      window.open(`mailto:${to}?subject=${subject}&body=${body}`, "_blank")
                    }}>
                      <Mail className="h-4 w-4 mr-1" /> Send
                    </Button>
                  )}
                  <Button variant="outline" asChild>
                    <Link href={`/generic-sales/${invoice.genericSaleId}`}>
                      <ExternalLink className="h-4 w-4 mr-1" /> View Sale
                    </Link>
                  </Button>
                </div>
              </div>

              {/* Voided banner */}
              {invoice.documentStatus === "Voided" && (
                <div className="mb-4 rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800">
                  <strong>Voided</strong> by {invoice.voidedBy || "—"} on{" "}
                  {invoice.voidedAt ? new Date(invoice.voidedAt).toLocaleString() : "—"}:
                  {" "}{invoice.voidReason}
                </div>
              )}

              {/* Invoice document preview */}
              <div ref={printRef} className="mb-6">
                {company && (
                  <GenericInvoiceDocument
                    invoice={invoice}
                    lines={invoice.lines ?? []}
                    company={company}
                    formatMoney={(n) => fmt(n)}
                  />
                )}
              </div>

              {/* Payment history */}
              {payments.length > 0 && (
                <Card className="mb-4">
                  <CardHeader className="pb-1">
                    <CardTitle className="text-xs uppercase tracking-wide text-slate-500 flex items-center gap-1">
                      <Wallet className="h-3.5 w-3.5" /> Payments Received
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="p-0">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Payment #</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Method</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Reference</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {payments.map((p) => (
                          <TableRow key={p.paymentId}>
                            <TableCell className="font-mono text-xs">{p.paymentNumber || p.paymentId}</TableCell>
                            <TableCell>{fmtDateTime(p.paymentDate, p)}</TableCell>
                            <TableCell>{p.paymentMethod || "—"}</TableCell>
                            <TableCell className="text-right font-semibold">{fmt(p.totalAmount)}</TableCell>
                            <TableCell className="text-xs text-slate-500">{p.reference || "—"}</TableCell>
                            <TableCell>
                              <Badge className={p.status === "Reversed"
                                ? "bg-rose-100 text-rose-700"
                                : "bg-emerald-100 text-emerald-700"}>
                                {p.status || "Posted"}
                              </Badge>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>
              )}

              {/* Document history */}
              {invoice.history && invoice.history.length > 0 && (
                <Card>
                  <CardHeader className="pb-1">
                    <CardTitle className="text-xs uppercase tracking-wide text-slate-500 flex items-center gap-1">
                      <Clock className="h-3.5 w-3.5" /> Document History
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="space-y-2">
                      {invoice.history.map((h) => (
                        <div key={h.genericInvoiceHistoryId} className="flex items-start gap-3 text-sm">
                          <div className="text-xs text-slate-400 whitespace-nowrap min-w-[140px]">
                            {h.createdAt ? new Date(h.createdAt).toLocaleString() : "—"}
                          </div>
                          <div>
                            <span className="font-medium text-slate-700">{h.action}</span>
                            {h.newValue && <span className="text-slate-500"> — {h.newValue}</span>}
                            {h.userId && <span className="text-xs text-slate-400 ml-2">by {h.userId}</span>}
                          </div>
                        </div>
                      ))}
                    </div>
                  </CardContent>
                </Card>
              )}
            </>
          )}

          {/* Void dialog */}
          <Dialog open={showVoid} onOpenChange={setShowVoid}>
            <DialogContent className="max-w-md">
              <DialogHeader>
                <DialogTitle>Void Invoice</DialogTitle>
                <DialogDescription>
                  Voiding {invoice?.invoiceNumber} marks it as cancelled. The underlying sale
                  and any payments are not affected.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>Reason for voiding <span className="text-rose-500">*</span></Label>
                  <Textarea
                    value={voidReason}
                    onChange={(e) => setVoidReason(e.target.value)}
                    placeholder="e.g. Duplicate invoice, incorrect customer..."
                    rows={3}
                  />
                </div>
                <div className="flex justify-end gap-2">
                  <Button variant="ghost" onClick={() => setShowVoid(false)} disabled={acting}>Cancel</Button>
                  <Button variant="destructive" onClick={onVoid} disabled={acting || !voidReason.trim()}>
                    {acting ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Ban className="h-4 w-4 mr-1" />}
                    Void Invoice
                  </Button>
                </div>
              </div>
            </DialogContent>
          </Dialog>

          {/* Receive Payment dialog — reuses the existing payment engine */}
          {paymentParty && paymentDocument && (
            <RecordPaymentDialog
              open={showPayment}
              onOpenChange={setShowPayment}
              module="generic"
              side="customer"
              party={paymentParty}
              singleDocument={paymentDocument}
              cashAccounts={cashAccounts}
              sourceType="InvoiceDocument"
              onPosted={() => {
                setShowPayment(false)
                toast({ title: "Payment recorded", description: `Invoice ${invoice?.invoiceNumber} updated.` })
                load() // Reload to reflect new balance and payment history
              }}
            />
          )}
        </main>
      </div>
    </div>
  )
}

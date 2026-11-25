"use client"

import { ProjectAssignmentCard } from "@/components/generic/projects/project-assignment-card"
import { useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { ArrowLeft, Check, Loader2, Trash2, Printer, Mail, Undo2, RotateCcw, FileText, ExternalLink } from "lucide-react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { approveSale, cancelSale, getSale, type GenericSale } from "@/lib/api/generic"
// 483: a sale is reversed (Poultry / Water model), no longer refunded in one click.
import { ReverseSaleDialog } from "@/components/sales/reverse-sale-dialog"
import { getGenericSaleReversal } from "@/lib/api/generic-sale-reversal"
import type { SaleReversalRecord } from "@/lib/api/sale"
import { getUserContext } from "@/lib/api/config"
import { getSelectedCurrency } from "@/lib/utils/currency"
import { useGenericModules } from "@/hooks/use-generic-modules"
import {
  generateInvoice, getInvoiceForSale, getInvoiceSettings,
  PAYMENT_TERMS_OPTIONS,
  type InvoiceSaleLookup, type InvoiceDocumentDetail,
} from "@/lib/api/generic-invoice-documents"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

/** Extract walk-in customer name stored in notes as "Customer: Name". */
function displayCustomer(sale: GenericSale): string {
  if (sale.customerName) return sale.customerName
  if (sale.notes?.startsWith("Customer: ")) {
    const pipe = sale.notes.indexOf(" | ")
    return pipe > 0 ? sale.notes.slice(10, pipe) : sale.notes.slice(10)
  }
  return "Walk-in"
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Refunded":  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    case "Reversed":  return "bg-slate-200 text-slate-800 hover:bg-slate-200"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

export default function GenericSaleDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params.id)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [sale, setSale] = useState<GenericSale | null>(null)
  const [loading, setLoading] = useState(true)
  const [acting, setActing] = useState(false)
  const [reverseOpen, setReverseOpen] = useState(false)
  // 485: Correct = reverse, then New sale filled in from it (Edit & repost).
  const [reverseMode, setReverseMode] = useState<"reverse" | "correct">("reverse")
  const [reversal, setReversal] = useState<SaleReversalRecord | null>(null)
  // Invoice document state
  const { showNew } = useGenericModules()
  const invoicingEnabled = showNew("enableInvoices")
  const [invoiceLookup, setInvoiceLookup] = useState<InvoiceSaleLookup | null>(null)
  const [showInvoiceDialog, setShowInvoiceDialog] = useState(false)
  const [invoiceTerms, setInvoiceTerms] = useState("DueImmediately")
  const [invoiceDueDate, setInvoiceDueDate] = useState("")
  const [invoicePO, setInvoicePO] = useState("")
  const [generating, setGenerating] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const s = await getSale(id)
      setSale(s)
      // A reversed sale is 'Cancelled' + a reversal record (483); a cancelled draft has none.
      const [r, inv] = await Promise.all([
        s?.status === "Cancelled" ? getGenericSaleReversal(id) : Promise.resolve(null),
        s?.status === "Approved" ? getInvoiceForSale(id) : Promise.resolve(null),
      ])
      setReversal(r?.success && r.data ? r.data : null)
      setInvoiceLookup(inv)
    } catch (e: any) {
      toast({ title: "Could not load sale", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id, router])

  const onApprove = async () => {
    setActing(true)
    try {
      await approveSale(id)

      // Auto-generate invoice document if the setting is on
      let autoDoc: InvoiceDocumentDetail | null = null
      if (invoicingEnabled) {
        try {
          const invSettings = await getInvoiceSettings()
          if (invSettings.autoGenerateInvoiceAfterSale) {
            autoDoc = await generateInvoice({ saleId: id })
          }
        } catch {
          // Non-fatal — the sale is approved regardless
        }
      }

      if (autoDoc) {
        toast({
          title: `Sale #${id} approved · Invoice ${autoDoc.invoiceNumber} generated`,
          description: "Inventory, cash and customer ledger updated.",
        })
        setInvoiceLookup({
          genericInvoiceDocumentId: autoDoc.genericInvoiceDocumentId,
          invoiceNumber: autoDoc.invoiceNumber,
          documentStatus: autoDoc.documentStatus,
          issueDate: autoDoc.issueDate,
          dueDate: autoDoc.dueDate,
        })
      } else {
        toast({
          title: `Sale #${id} approved`,
          description: invoicingEnabled
            ? "Inventory, cash and customer ledger updated. You can now generate an invoice."
            : "Inventory, cash and customer ledger updated.",
        })
      }
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  const onGenerateInvoice = async () => {
    setGenerating(true)
    try {
      const doc = await generateInvoice({
        saleId: id,
        paymentTerms: invoiceTerms !== "Custom" ? invoiceTerms : undefined,
        dueDate: invoiceTerms === "Custom" && invoiceDueDate ? invoiceDueDate : undefined,
        purchaseOrderReference: invoicePO || undefined,
      })
      setShowInvoiceDialog(false)
      if (doc) {
        setInvoiceLookup({
          genericInvoiceDocumentId: doc.genericInvoiceDocumentId,
          invoiceNumber: doc.invoiceNumber,
          documentStatus: doc.documentStatus,
          issueDate: doc.issueDate,
          dueDate: doc.dueDate,
        })
        toast({
          title: `Invoice ${doc.invoiceNumber} generated`,
          description: `Due ${doc.dueDate ?? "immediately"}.`,
        })
        router.push(`/generic-invoice-documents/${doc.genericInvoiceDocumentId}`)
      }
    } catch (e: any) {
      toast({ title: "Could not generate invoice", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setGenerating(false) }
  }

  const onCancel = async () => {
    setActing(true)
    try {
      await cancelSale(id)
      toast({ title: `Sale #${id} cancelled.` })
      await load()
    } catch (e: any) {
      toast({ title: "Cancel failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-sales" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to sales
          </Link>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !sale ? (
            <Card><CardContent className="py-8 text-center text-slate-500">Sale not found.</CardContent></Card>
          ) : (
            <>
              {reversal && (
                <div className="mb-4 rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-700">
                  <strong>Reversed</strong> ({reversal.reversalNumber}) on {new Date(reversal.occurredAt).toLocaleString()}
                  {reversal.reversedBy ? ` by ${reversal.reversedBy}` : ""}: {reversal.reason}.
                  {reversal.cashReversed > 0 && ` ${fmt(reversal.cashReversed)} paid back.`}
                  {reversal.creditCreated > 0 && ` ${fmt(reversal.creditCreated)} kept as customer credit.`}
                  {" "}Stock was put back and the sale no longer counts in sales or Profit &amp; Loss.
                  {reversal.correctionSaleId
                    ? <> Corrected by <Link href={`/generic-sales/${reversal.correctionSaleId}`} className="font-medium text-blue-700 underline">sale #{reversal.correctionSaleId}</Link>.</>
                    : " Was it entered wrongly? Use \"Edit & repost\" to enter it again, corrected."}
                </div>
              )}
              <div className="mb-4 flex items-start justify-between flex-wrap gap-2">
                <div>
                  <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                    Sale #{sale.genericSaleId}
                    <Badge className={statusBadgeClass(reversal ? "Reversed" : sale.status)}>{reversal ? "Reversed" : sale.status}</Badge>
                  </h1>
                  <p className="text-sm text-slate-500">{new Date(sale.saleDate).toLocaleString()}</p>
                </div>
                <div className="flex gap-2">
                  {sale.status === "Draft" && (
                    <>
                      <Button onClick={onApprove} disabled={acting} className="bg-emerald-600 hover:bg-emerald-700">
                        {acting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Check className="h-4 w-4 mr-1" />}
                        Approve
                      </Button>
                      <AlertDialog>
                        <AlertDialogTrigger asChild>
                          <Button variant="outline" disabled={acting}><Trash2 className="h-4 w-4 mr-1" />Cancel</Button>
                        </AlertDialogTrigger>
                        <AlertDialogContent>
                          <AlertDialogHeader>
                            <AlertDialogTitle>Cancel this draft sale?</AlertDialogTitle>
                            <AlertDialogDescription>This marks the sale as Cancelled. It has no inventory or cash impact (the sale was never approved).</AlertDialogDescription>
                          </AlertDialogHeader>
                          <AlertDialogFooter>
                            <AlertDialogCancel>Keep it</AlertDialogCancel>
                            <AlertDialogAction onClick={onCancel}>Yes, cancel</AlertDialogAction>
                          </AlertDialogFooter>
                        </AlertDialogContent>
                      </AlertDialog>
                    </>
                  )}
                  {sale.status === "Approved" && (
                    <>
                      <Button variant="outline" disabled={acting} onClick={() => { setReverseMode("correct"); setReverseOpen(true) }}>
                        <RotateCcw className="h-4 w-4 mr-1" /> Correct sale
                      </Button>
                      <Button variant="outline" disabled={acting} onClick={() => { setReverseMode("reverse"); setReverseOpen(true) }}>
                        <Undo2 className="h-4 w-4 mr-1" /> Reverse
                      </Button>
                    </>
                  )}
                  {reversal && !reversal.correctionSaleId && (
                    <Button variant="outline" onClick={() => router.push(`/generic-sales/new?corrects=${sale.genericSaleId}`)}>
                      <RotateCcw className="h-4 w-4 mr-1" /> Edit &amp; repost
                    </Button>
                  )}
                  {/* Invoice actions — only when invoicing is enabled and sale is approved */}
                  {invoicingEnabled && sale.status === "Approved" && !reversal && (
                    invoiceLookup ? (
                      <Button variant="outline" asChild>
                        <Link href={`/generic-invoice-documents/${invoiceLookup.genericInvoiceDocumentId}`}>
                          <FileText className="h-4 w-4 mr-1" /> {invoiceLookup.invoiceNumber}
                        </Link>
                      </Button>
                    ) : (
                      <Button variant="outline" onClick={() => setShowInvoiceDialog(true)} disabled={generating}>
                        {generating ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <FileText className="h-4 w-4 mr-1" />}
                        Generate Invoice
                      </Button>
                    )
                  )}
                  {/* Print & Email — always visible */}
                  <Button variant="outline" onClick={() => window.print()}>
                    <Printer className="h-4 w-4 mr-1" /> Print
                  </Button>
                  <Button variant="outline" onClick={() => {
                    const customer = displayCustomer(sale)
                    const subject = encodeURIComponent(`Invoice #${sale.genericSaleId} — ${fmt(sale.totalAmount)}`)
                    const body = encodeURIComponent(
                      `Dear ${customer},\n\n` +
                      `Please find your invoice details below:\n\n` +
                      `Invoice: #${sale.genericSaleId}\n` +
                      `Receipt: ${sale.receiptNumber ?? "—"}\n` +
                      `Date: ${new Date(sale.saleDate).toLocaleDateString()}\n` +
                      `Total: ${fmt(sale.totalAmount)}\n` +
                      `Paid: ${fmt(sale.amountPaid)}\n` +
                      `Balance: ${fmt(sale.balance)}\n\n` +
                      `Items:\n` +
                      sale.items.map((it) => `  - ${it.description ?? "Item"} x${it.quantity} @ ${fmt(it.unitPrice)} = ${fmt(it.lineTotal ?? it.quantity * it.unitPrice)}`).join("\n") +
                      `\n\nThank you for your business!`
                    )
                    window.open(`mailto:?subject=${subject}&body=${body}`, "_blank")
                  }}>
                    <Mail className="h-4 w-4 mr-1" /> Email
                  </Button>
                </div>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-7 gap-4">
                <Card className="lg:col-span-4">
                  <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Items</CardTitle></CardHeader>
                  <CardContent className="p-0">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Type</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead className="text-right">Qty</TableHead>
                          <TableHead className="text-right">Unit price</TableHead>
                          <TableHead className="text-right">Discount</TableHead>
                          <TableHead className="text-right">Line total</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {sale.items.map((i) => (
                          <TableRow key={i.genericSaleItemId}>
                            <TableCell className="text-xs text-slate-500">{i.itemType}</TableCell>
                            <TableCell>{i.description ?? (i.genericProductId ? `Product #${i.genericProductId}` : `Service #${i.genericServiceId}`)}</TableCell>
                            <TableCell className="text-right">{i.quantity}</TableCell>
                            <TableCell className="text-right">{fmt(i.unitPrice)}</TableCell>
                            <TableCell className="text-right">{fmt(i.discountAmount)}</TableCell>
                            <TableCell className="text-right font-semibold">{fmt(i.lineTotal ?? 0)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                <div className="lg:col-span-3 space-y-4">
                  <Card>
                    <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Totals</CardTitle></CardHeader>
                    <CardContent>
                      <dl className="space-y-1 text-sm">
                        <Row label="Subtotal" value={fmt(sale.subtotalAmount)} />
                        <Row label="Discount" value={fmt(sale.discountAmount)} />
                        <Row label="Tax"      value={fmt(sale.taxAmount)} />
                        <Row label="Total"    value={fmt(sale.totalAmount)} bold />
                        <Row label={`Paid (${sale.paymentMethod ?? "—"})`} value={fmt(sale.amountPaid)} valueClass="text-emerald-700" />
                        <Row label="Balance"  value={fmt(sale.balance)} valueClass={sale.balance > 0 ? "text-rose-700 font-bold" : ""} />
                      </dl>
                    </CardContent>
                  </Card>

                  <Card>
                    <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Header</CardTitle></CardHeader>
                    <CardContent className="text-sm space-y-1">
                      <div>Customer: <strong>{displayCustomer(sale)}</strong></div>
                      <div>Type: {sale.salesType}{sale.salesChannel ? ` / ${sale.salesChannel}` : ""}</div>
                      <div>Receipt: {sale.receiptNumber ?? "—"}</div>
                      <div>Payment status: <strong>{sale.paymentStatus}</strong></div>
                      {sale.notes && <><hr className="my-2" /><div>{sale.notes}</div></>}
                    </CardContent>
                  </Card>

                  {/* 483: which project / contract each line belongs to; change or split it here. */}
                  <ProjectAssignmentCard documentType="Sale" documentId={sale.genericSaleId}
                    note="Payments on this sale follow its project automatically."
                    lines={sale.items.filter((i) => i.genericSaleItemId).map((i) => ({
                      lineId: i.genericSaleItemId!, description: i.description ?? `Line ${i.genericSaleItemId}`,
                      quantity: i.quantity, amount: i.lineTotal ?? i.quantity * i.unitPrice, unit: i.saleUnit,
                    }))} />
                </div>
              </div>
            </>
          )}
          {/* Generate Invoice dialog */}
          <Dialog open={showInvoiceDialog} onOpenChange={setShowInvoiceDialog}>
            <DialogContent className="max-w-md">
              <DialogHeader>
                <DialogTitle>Generate Invoice</DialogTitle>
                <DialogDescription>
                  Create a formal invoice document for Sale #{id}.
                  This does not create any additional financial transactions.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <div>
                  <Label>Payment terms</Label>
                  <Select value={invoiceTerms} onValueChange={(v) => { setInvoiceTerms(v); if (v !== "Custom") setInvoiceDueDate("") }}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {PAYMENT_TERMS_OPTIONS.map((o) => (
                        <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                {invoiceTerms === "Custom" && (
                  <div>
                    <Label>Due date</Label>
                    <Input type="date" value={invoiceDueDate} onChange={(e) => setInvoiceDueDate(e.target.value)} />
                  </div>
                )}

                <div>
                  <Label>Purchase order reference <span className="text-xs text-slate-400">(optional)</span></Label>
                  <Input value={invoicePO} onChange={(e) => setInvoicePO(e.target.value)} placeholder="PO-12345" />
                </div>

                <div className="flex justify-end gap-2 pt-2">
                  <Button variant="ghost" onClick={() => setShowInvoiceDialog(false)} disabled={generating}>
                    Cancel
                  </Button>
                  <Button onClick={onGenerateInvoice} disabled={generating || (invoiceTerms === "Custom" && !invoiceDueDate)}>
                    {generating ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <FileText className="h-4 w-4 mr-1" />}
                    Generate Invoice
                  </Button>
                </div>
              </div>
            </DialogContent>
          </Dialog>

          <ReverseSaleDialog
            open={reverseOpen}
            module="generic"
            mode={reverseMode}
            saleId={sale ? sale.genericSaleId : null}
            saleLabel={sale ? `#${sale.genericSaleId}` : ""}
            farmId={getUserContext().farmId}
            userId={getUserContext().userId}
            currencyCode={getSelectedCurrency()}
            onOpenChange={setReverseOpen}
            onReversed={async ({ reversal: r }) => {
              setReverseOpen(false)
              // Correct: reversed; now enter it again, filled in from it.
              if (reverseMode === "correct") { router.push(`/generic-sales/new?corrects=${id}`); return }
              toast({
                title: `Sale #${id} reversed${r?.reversalNumber ? ` (${r.reversalNumber})` : ""}`,
                description: r
                  ? [r.cashReversed > 0 ? `${fmt(r.cashReversed)} paid back` : "", r.creditCreated > 0 ? `${fmt(r.creditCreated)} kept as credit` : ""]
                      .filter(Boolean).join(" · ") || "Stock put back; nothing had been paid."
                  : undefined,
              })
              await load()
            }}
          />
        </main>
      </div>
    </div>
  )
}

function Row({ label, value, bold = false, valueClass = "" }: { label: string; value: string; bold?: boolean; valueClass?: string }) {
  return (
    <div className="flex justify-between">
      <dt className={bold ? "font-semibold" : "text-slate-600"}>{label}</dt>
      <dd className={`${bold ? "font-semibold" : ""} ${valueClass}`}>{value}</dd>
    </div>
  )
}

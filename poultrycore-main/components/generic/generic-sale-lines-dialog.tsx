"use client"

// Generic Sale Lines Dialog — shows what items are on a generic sale.
// The generic equivalent of the poultry SaleLinesDialog, but simpler:
// no egg classes, no byproducts, no packaging — just product lines.

import { useEffect, useState } from "react"
import { ExternalLink, Loader2, ShoppingCart } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getSale, type GenericSale } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

interface Props {
  saleIds: number[] | null
  onOpenChange: (open: boolean) => void
  onOpenSale?: (id: number) => void
}

export function GenericSaleLinesDialog({ saleIds, onOpenChange, onOpenSale }: Props) {
  const gh = useFmt()
  const [sales, setSales] = useState<GenericSale[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!saleIds || saleIds.length === 0) { setSales([]); return }
    let cancelled = false
    setLoading(true)
    Promise.all(saleIds.map((id) => getSale(id).catch(() => null)))
      .then((results) => {
        if (!cancelled) setSales(results.filter(Boolean) as GenericSale[])
      })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [saleIds])

  const open = !!saleIds && saleIds.length > 0

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={ShoppingCart} color="blue">
            {sales.length === 1 ? `Sale #${sales[0].genericSaleId}` : `${saleIds?.length ?? 0} sale(s)`}
          </FormDialogTitle>
          <DialogDescription>
            {sales.length === 1 && sales[0].customerName
              ? `${sales[0].customerName} · ${fmtDateTime(sales[0].saleDate, sales[0])}`
              : "What was sold on this invoice."}
          </DialogDescription>
        </DialogHeader>

        {loading ? (
          <div className="flex items-center gap-2 py-8 justify-center text-sm text-slate-500">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading sale lines…
          </div>
        ) : sales.length === 0 ? (
          <p className="py-6 text-center text-sm text-slate-500">No sale data found.</p>
        ) : (
          sales.map((sale) => (
            <div key={sale.genericSaleId} className="space-y-2">
              {sales.length > 1 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="font-medium">Sale #{sale.genericSaleId}</span>
                  <span className="text-slate-500">{fmtDateTime(sale.saleDate, sale)}</span>
                </div>
              )}
              <div className="overflow-x-auto rounded-lg border">
                <Table>
                  <TableHeader>
                    <TableRow className="bg-slate-50">
                      <TableHead>Item</TableHead>
                      <TableHead className="text-right">Qty</TableHead>
                      <TableHead className="text-right">Unit price</TableHead>
                      <TableHead className="text-right">Discount</TableHead>
                      <TableHead className="text-right">Line total</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(sale.items ?? []).map((item, i) => (
                      <TableRow key={item.genericSaleItemId ?? i}>
                        <TableCell>
                          <div className="font-medium">{item.description || "Item"}</div>
                          {item.itemType === "Service" && (
                            <Badge variant="outline" className="text-[10px] mt-0.5">Service</Badge>
                          )}
                        </TableCell>
                        <TableCell className="text-right tabular-nums">{item.quantity}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(item.unitPrice)}</TableCell>
                        <TableCell className="text-right tabular-nums">{item.discountAmount > 0 ? gh(item.discountAmount) : "—"}</TableCell>
                        <TableCell className="text-right tabular-nums font-medium">{gh(item.lineTotal ?? (item.quantity * item.unitPrice - item.discountAmount))}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                  <TableFooter>
                    <TableRow>
                      <TableCell colSpan={4} className="text-right font-semibold">Total</TableCell>
                      <TableCell className="text-right font-semibold tabular-nums">{gh(sale.totalAmount)}</TableCell>
                    </TableRow>
                    {sale.amountPaid > 0 && (
                      <TableRow>
                        <TableCell colSpan={4} className="text-right text-emerald-700">Paid</TableCell>
                        <TableCell className="text-right tabular-nums text-emerald-700">{gh(sale.amountPaid)}</TableCell>
                      </TableRow>
                    )}
                    {sale.balance > 0 && (
                      <TableRow>
                        <TableCell colSpan={4} className="text-right text-amber-700">Balance</TableCell>
                        <TableCell className="text-right tabular-nums text-amber-700">{gh(sale.balance)}</TableCell>
                      </TableRow>
                    )}
                  </TableFooter>
                </Table>
              </div>
              {onOpenSale && (
                <Button variant="outline" size="sm" className="gap-1" onClick={() => onOpenSale(sale.genericSaleId)}>
                  <ExternalLink className="h-3.5 w-3.5" /> Open sale
                </Button>
              )}
            </div>
          ))
        )}

        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelLabel="Close" />
      </DialogContent>
    </Dialog>
  )
}

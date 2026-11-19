"use client"

// Generic Customer Credit Panel — shows credit held for customers below the
// balances table, matching the poultry CustomerCreditPanel. Uses the generic
// customer credits API.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { HandCoins, Loader2, PiggyBank } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useFmt } from "@/lib/currency"
import { getCustomerCredits, type GenericCustomerCredit } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

export function GenericCustomerCreditPanel({ refreshKey = 0 }: { refreshKey?: number }) {
  const gh = useFmt()
  const [rows, setRows] = useState<GenericCustomerCredit[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    getCustomerCredits()
      .then((r) => { if (!cancelled) setRows(r) })
      .catch(() => {})
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [refreshKey])

  const activeRows = useMemo(() => rows.filter((r) => r.status === "Active" && r.remainingBalance > 0), [rows])
  const totalCredit = activeRows.reduce((sum, r) => sum + r.remainingBalance, 0)

  if (loading) return null
  if (activeRows.length === 0) return null

  return (
    <Card className="mt-4 border-blue-200">
      <CardContent className="p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <PiggyBank className="h-5 w-5 text-blue-600" />
            <div>
              <div className="text-sm font-semibold text-slate-900">Customer Credits</div>
              <div className="text-xs text-slate-500">
                Money held for customers — not netted into what they owe.
              </div>
            </div>
          </div>
          <div className="text-right">
            <div className="text-lg font-semibold tabular-nums text-blue-700">{gh(totalCredit)}</div>
            <div className="text-xs text-slate-500">{activeRows.length} customer(s)</div>
          </div>
        </div>

        <div className="overflow-x-auto rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow className="bg-blue-50/50">
                <TableHead>Customer</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Date</TableHead>
                <TableHead className="text-right">Amount</TableHead>
                <TableHead className="text-right">Remaining</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {activeRows.slice(0, 10).map((r) => (
                <TableRow key={r.genericCustomerCreditId}>
                  <TableCell className="font-medium">{r.customerName ?? "—"}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className="text-[10px]">{r.creditType}</Badge>
                  </TableCell>
                  <TableCell className="text-xs">{fmtDateTime(r.creditDate, r)}</TableCell>
                  <TableCell className="text-right tabular-nums">{gh(r.amount)}</TableCell>
                  <TableCell className="text-right tabular-nums font-semibold text-blue-700">{gh(r.remainingBalance)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>

        {activeRows.length > 10 && (
          <p className="text-xs text-slate-500">Showing 10 of {activeRows.length} credits.</p>
        )}

        <Button asChild variant="outline" size="sm" className="gap-1">
          <Link href="/generic-customer-credits">
            <HandCoins className="h-3.5 w-3.5" /> View all customer credits
          </Link>
        </Button>
      </CardContent>
    </Card>
  )
}

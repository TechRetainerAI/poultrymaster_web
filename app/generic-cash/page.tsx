"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getCashAccounts, type GenericCashAccount } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function GenericCashPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericCashAccount[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const data = await getCashAccounts()
        if (!cancelled) setRows(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load cash accounts", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const totalActive = useMemo(() => rows.filter((a) => a.isActive).reduce((s, a) => s + a.currentBalance, 0), [rows])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Wallet className="h-6 w-6 text-sky-600" /> Cash &amp; accounts
            </h1>
            <p className="text-sm text-slate-500">Live balances. Transfers + adjustments come in Part 2.</p>
          </div>

          <Card className="mb-4 max-w-md">
            <CardHeader className="pb-1"><CardTitle className="text-xs uppercase text-slate-500">Total cash at hand</CardTitle></CardHeader>
            <CardContent>
              <div className="text-3xl font-semibold text-slate-900">{fmt(totalActive)}</div>
              <div className="text-xs text-slate-500 mt-1">across {rows.filter((a) => a.isActive).length} active account(s)</div>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No cash accounts. Run setup to seed defaults.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Account</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead className="text-right">Opening</TableHead>
                      <TableHead className="text-right">Current</TableHead>
                      <TableHead>Allows negative</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((a) => (
                      <TableRow key={a.genericCashAccountId}>
                        <TableCell className="font-medium">{a.accountName}</TableCell>
                        <TableCell className="text-xs text-slate-500">{a.accountType}</TableCell>
                        <TableCell className="text-right">{fmt(a.openingBalance)}</TableCell>
                        <TableCell className={`text-right font-semibold ${a.currentBalance < 0 ? "text-rose-700" : ""}`}>{fmt(a.currentBalance)}</TableCell>
                        <TableCell>{a.allowNegativeBalance ? "Yes" : "No"}</TableCell>
                        <TableCell>{a.isActive ? <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Active</Badge> : <Badge variant="secondary">Inactive</Badge>}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

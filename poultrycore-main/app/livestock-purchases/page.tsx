"use client"

// Purchases -- stock and animals bought, what each came to, what was paid and
// what is still owed. The poultry Supply Purchases page for livestock.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Plus, ShoppingCart } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { listPurchases, type Purchase } from "@/lib/api/livestock"
import { PurchaseTotals, PurchasesTable } from "@/components/livestock/purchases-table"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, todayIso } from "@/components/livestock/livestock-page"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function LivestockPurchasesPage() {
  const [rows, setRows] = useState<Purchase[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [unpaidOnly, setUnpaidOnly] = useState(false)
  const [from, setFrom] = useState(daysAgo(60))
  const [to, setTo] = useState(todayIso())

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listPurchases(unpaidOnly ? { status: "Unpaid" } : { from, to })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [unpaidOnly, from, to])
  useEffect(() => { load() }, [load])


  return (
    <LivestockPage
      title="Purchases"
      description="Feed, medicine, supplies and animals bought, and what is still owed."
      icon={ShoppingCart}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-supplier-balances">Supplier balances</Link></Button>
          <Button asChild className={AMBER_BUTTON}><Link href="/livestock-purchases/new"><Plus className="h-4 w-4 mr-1" /> New purchase</Link></Button>
        </>
      }
    >
      <PurchaseTotals rows={rows ?? []} boughtLabel={unpaidOnly ? "Unpaid purchases" : "Bought in these dates"} />
      <div className="flex items-center gap-3 flex-wrap">
        <label className="flex items-center gap-2 text-sm text-stone-600"><Switch checked={unpaidOnly} onCheckedChange={setUnpaidOnly} /> Only what is still owed</label>
        {!unpaidOnly && (
          <>
            <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
            <span className="text-sm text-stone-500">to</span>
            <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
          </>
        )}
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title={unpaidOnly ? "Nothing is owed" : "No purchases in these dates"} />
      ) : (
        <PurchasesTable rows={rows} />
      )}
    </LivestockPage>
  )
}

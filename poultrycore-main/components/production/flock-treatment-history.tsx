"use client"

// One flock's treatments from Treatment Campaigns (migration 339), newest
// first — live and reversed, each linked to its campaign and to the production
// record that carries the dose. The flock keeps its own history whatever
// campaign the treatment came from. Fails quietly (renders nothing) when the
// API is unavailable, e.g. before 339 is applied.

import { useEffect, useState } from "react"
import Link from "next/link"
import { Pill } from "lucide-react"
import { cn } from "@/lib/utils"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { getFlockTreatmentHistory, type FlockTreatmentHistoryRow } from "@/lib/api/treatment-campaigns"
import { fmtQty } from "@/lib/production/treatment-campaigns"

export function FlockTreatmentHistory({ flockId }: { flockId: number }) {
  const [rows, setRows] = useState<FlockTreatmentHistoryRow[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!Number.isFinite(flockId)) return
    getFlockTreatmentHistory(flockId).then(setRows).catch(() => setFailed(true))
  }, [flockId])

  if (failed || rows === null) return null

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="mb-2 flex items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-slate-900">
          <Pill className="h-4 w-4 text-violet-600" /> Treatment history
        </h2>
        <Link href="/poultry-treatment-campaigns" className="text-xs text-violet-700 hover:underline">Treatment campaigns →</Link>
      </div>
      {rows.length === 0 ? (
        <p className="text-sm text-slate-500">No treatments recorded for this flock through a campaign yet.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[36rem] text-sm">
            <thead className="text-left text-xs uppercase tracking-wider text-slate-500">
              <tr>
                <th className="py-1.5 pr-3 font-medium">Date</th>
                <th className="py-1.5 pr-3 font-medium">Campaign</th>
                <th className="py-1.5 pr-3 font-medium">Product</th>
                <th className="py-1.5 pr-3 text-right font-medium">Given</th>
                <th className="py-1.5 font-medium">Withdrawal</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {rows.map((r) => {
                const reversed = r.postStatus === "Reversed"
                return (
                  <tr key={r.poultryTreatmentCampaignPostLineId} className={cn(reversed && "text-slate-400 line-through")}>
                    <td className="py-1.5 pr-3 whitespace-nowrap">
                      <Link href={`/production-records/${r.productionRecordId}`} className="hover:underline">
                        {formatLongDate(r.businessDate.slice(0, 10))}
                      </Link>
                    </td>
                    <td className="py-1.5 pr-3">
                      <Link href={`/poultry-treatment-campaigns?id=${r.poultryTreatmentCampaignId}`} className="text-violet-700 hover:underline">
                        {r.campaignName}
                      </Link>
                      {reversed && <span className="ml-1 text-xs no-underline">(reversed)</span>}
                    </td>
                    <td className="py-1.5 pr-3">{r.itemName ?? "—"}</td>
                    <td className="py-1.5 pr-3 text-right tabular-nums">{fmtQty(r.actualQuantity, r.unitOfMeasure)}</td>
                    <td className="py-1.5 text-xs">
                      {r.eggWithdrawalUntil && `Eggs until ${formatLongDate(r.eggWithdrawalUntil.slice(0, 10))}`}
                      {r.eggWithdrawalUntil && r.meatWithdrawalUntil && " · "}
                      {r.meatWithdrawalUntil && `Meat until ${formatLongDate(r.meatWithdrawalUntil.slice(0, 10))}`}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

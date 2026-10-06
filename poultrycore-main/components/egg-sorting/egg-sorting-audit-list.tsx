"use client"

// The egg sorting audit trail (migration 344): append-only, written by the
// database itself, so it records what happened however it was done.

import { useEffect, useState } from "react"
import { Loader2 } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { getEggSortingAudit, type EggSortingAuditRow } from "@/lib/api/egg-sorting"
import { fmtCount } from "@/lib/production/egg-sorting"

const ACTION_LABEL: Record<string, string> = {
  DraftCreated: "Sorting draft created",
  DraftEdited: "Sorting draft edited",
  DraftDiscarded: "Sorting draft discarded",
  Posted: "Sorting posted",
  Reversed: "Sorting reversed",
  SizeAdded: "Egg size added",
  SizeChanged: "Egg size changed",
  SettingsChanged: "Sorting settings changed",
  SaleEggClassSet: "Sale egg class set",
  EggClassAdjusted: "Egg stock adjusted",
}

function parse(d: string | null): Record<string, any> {
  try { return d ? JSON.parse(d) : {} } catch { return {} }
}

/** One plain sentence per entry, from its details. */
export function describeAudit(a: EggSortingAuditRow): string {
  const d = parse(a.details)
  switch (a.action) {
    case "Posted":
    case "Reversed":
    case "DraftCreated":
    case "DraftEdited":
    case "DraftDiscarded": {
      const base = `${d.sessionNo ?? `#${a.entityId}`}: ${fmtCount(Number(d.input) || 0)} eggs`
        + (d.sized != null ? ` (${fmtCount(Number(d.sized) || 0)} into sizes, ${fmtCount(Number(d.loss) || 0)} lost)` : "")
      const lines = Array.isArray(d.lines) ? ` — ${d.lines.map((l: any) => `${l.size ?? l.type} ${fmtCount(l.qty)}`).join(", ")}` : ""
      const from = Array.isArray(d.sources) ? `; from ${d.sources.map((s: any) => `${s.productionDate} pick ${s.pick} (${fmtCount(s.qty)})`).join(", ")}` : ""
      const why = d.reason ? `; reason: ${d.reason}` : ""
      return base + lines + from + why
    }
    case "SizeAdded":
      return `${d.name}${d.price != null ? ` at ${d.price} per crate` : ""}`
    case "SizeChanged": {
      const parts: string[] = []
      if (d.name && Array.isArray(d.name)) parts.push(`renamed ${d.name[0]} → ${d.name[1]}`)
      if (Array.isArray(d.pricePerCrate)) parts.push(`price ${d.pricePerCrate[0] ?? "none"} → ${d.pricePerCrate[1] ?? "none"}`)
      if (Array.isArray(d.active)) parts.push(d.active[1] ? "switched on" : "switched off")
      if (Array.isArray(d.order)) parts.push("reordered")
      return `${typeof d.name === "string" ? d.name : ""} ${parts.join(", ")}`.trim()
    }
    case "SettingsChanged":
      return `sorting ${d.enableEggSorting ? "on" : "off"}, Daily Closing ${d.closingPolicy}, ${d.eggsPerCrate} eggs per crate`
        + (d.unsortedPricePerCrate != null ? `, unsorted ${d.unsortedPricePerCrate} per crate` : "")
    case "SaleEggClassSet":
      return `Sale #${a.entityId}: ${d.from} → ${d.to}, ${fmtCount(Number(d.quantity) || 0)} eggs${d.customer ? ` (${d.customer})` : ""}${d.saleGroupNo ? `, ${d.saleGroupNo}` : ""}`
    case "EggClassAdjusted":
      return `${d.class}: ${d.kind} ${Number(d.quantity) > 0 ? "+" : ""}${fmtCount(Number(d.quantity) || 0)} (${fmtCount(Number(d.onHandBefore) || 0)} → ${fmtCount(Number(d.onHandAfter) || 0)}); ${d.reason ?? ""}`
    default:
      return a.details ?? ""
  }
}

export function EggSortingAuditList({
  title, description, entity, entityId, limit = 100, bare,
}: {
  title?: string
  description?: string
  entity?: string
  entityId?: number
  limit?: number
  /** No card chrome (for use inside an expanded row). */
  bare?: boolean
}) {
  const { fmtInstant } = useCompanyDateTime()
  const [rows, setRows] = useState<EggSortingAuditRow[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let cancelled = false
    getEggSortingAudit({ entity, entityId, limit })
      .then((r) => { if (!cancelled) setRows(r) })
      .catch(() => { if (!cancelled) { setRows([]); setFailed(true) } })
    return () => { cancelled = true }
  }, [entity, entityId, limit])

  const body = !rows ? (
    <p className="flex items-center gap-2 px-4 py-3 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading history…</p>
  ) : rows.length === 0 ? (
    <p className="px-4 py-3 text-sm text-slate-500">{failed ? "The change history is not available yet." : "No changes recorded yet."}</p>
  ) : (
    <ul className="divide-y divide-slate-100">
      {rows.map((a) => (
        <li key={a.auditId} className="px-4 py-2 text-sm">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <span className="font-medium text-slate-900">{ACTION_LABEL[a.action] ?? a.action}</span>
            <span className="text-xs text-slate-500">{fmtInstant(a.atUtc)}{a.actor ? ` · ${a.actor}` : ""}</span>
          </div>
          <div className="text-xs text-slate-600">{describeAudit(a)}</div>
        </li>
      ))}
    </ul>
  )

  if (bare) return <div className="rounded-md border border-slate-200 bg-white">{body}</div>
  return (
    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
      <CardContent className="p-0">
        {(title || description) && (
          <div className="border-b border-slate-100 px-4 py-3">
            {title && <div className="font-semibold text-slate-900">{title}</div>}
            {description && <p className="text-sm text-slate-600">{description}</p>}
          </div>
        )}
        <div className="max-h-[28rem] overflow-y-auto">{body}</div>
      </CardContent>
    </Card>
  )
}

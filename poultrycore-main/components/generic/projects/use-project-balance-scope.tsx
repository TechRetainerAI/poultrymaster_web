"use client"

// 493: the Project / Contract filter for Generic Customer / Supplier Balances.
//
// The database returns every open document behind the balances (the same rows
// the page lists) with its project shares. A party's balance for a project is
// the sum of its documents' project parts, split the way the engine splits
// (projectPart), so the projects + General always add back to the company
// balance. Undefined while the module is off: the page is then unchanged.

import { useCallback, useEffect, useMemo, useState } from "react"
import { Label } from "@/components/ui/label"
import { ProjectFilter } from "@/components/generic/projects/project-filter"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { getProjectOpenBalances, type ProjectOpenBalance } from "@/lib/api/generic-projects"
import { ALL_PROJECTS, projectPart, round, type ProjectFilterValue } from "@/lib/generic/project-math"
import type { BalanceStatusFilter, OpenDocumentRow, PartyBalanceRow } from "@/lib/api/balances"

const docKey = (type: string, id: number) => `${type}:${id}`

export function useProjectBalanceScope(side: "customer" | "supplier") {
  const { enabled } = useProjectsEnabled()
  const [filter, setFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const [docs, setDocs] = useState<ProjectOpenBalance[]>([])
  const [version, setVersion] = useState(0)
  const active = enabled && filter.kind !== "all"

  // Read only while a project is picked; again after every reload of the page.
  useEffect(() => {
    if (!active) return
    let cancelled = false
    getProjectOpenBalances(side)
      .then((rows) => { if (!cancelled) setDocs(rows) })
      .catch(() => { if (!cancelled) setDocs([]) })
    return () => { cancelled = true }
  }, [active, side, version])

  const byParty = useMemo(() => {
    const m = new Map<number, ProjectOpenBalance[]>()
    for (const d of docs) {
      const list = m.get(d.partyId) ?? []
      list.push(d)
      m.set(d.partyId, list)
    }
    return m
  }, [docs])
  const byDoc = useMemo(() => new Map(docs.map((d) => [docKey(d.documentType, d.documentId), d])), [docs])

  const onReload = useCallback(() => setVersion((v) => v + 1), [])

  return useMemo(() => {
    if (!enabled) return undefined
    return {
      control: (
        <div className="w-full space-y-1.5 sm:w-auto">
          <Label>Project / contract</Label>
          <ProjectFilter value={filter} onChange={setFilter} className="w-full sm:w-72" />
        </div>
      ),
      active,
      onReload,
      party: (row: PartyBalanceRow, f: { from: string; to: string; status: BalanceStatusFilter }) => {
        const parts = (byParty.get(row.partyId) ?? [])
          .filter((d) => {
            const day = (d.documentDate ?? "").slice(0, 10)
            if (f.from && day < f.from) return false
            if (f.to && day > f.to) return false
            if (f.status === "Partial") return d.amountPaid > 0
            if (f.status === "Unpaid") return d.amountPaid <= 0
            if (f.status === "Overdue") return d.isOverdue
            return true
          })
          .map((d) => ({ d, amount: projectPart(d.balance, d.projects, filter) }))
          .filter((x) => x.amount !== 0)
        if (parts.length === 0) return null
        const days = parts.map((x) => (x.d.documentDate ?? "").slice(0, 10)).sort()
        return {
          ...row,
          totalBalance: round(parts.reduce((t, x) => t + x.amount, 0)),
          openDocumentCount: parts.length,
          overdueAmount: round(parts.filter((x) => x.d.isOverdue).reduce((t, x) => t + x.amount, 0)),
          oldestDocumentDate: days[0] ?? row.oldestDocumentDate,
          latestDocumentDate: days[days.length - 1] ?? row.latestDocumentDate,
        }
      },
      document: (doc: OpenDocumentRow) => {
        const d = byDoc.get(docKey(doc.documentType, doc.documentId))
        const amount = projectPart(doc.balance, d?.projects, filter)
        return amount === 0 ? null : { ...doc, balance: amount }
      },
    }
  }, [enabled, active, filter, byParty, byDoc, onReload])
}

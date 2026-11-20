"use client"

// Herd make-up: the animals on the farm now, per kind, with the tagged ones
// split by sex and age.

import { useCallback, useEffect, useState } from "react"
import { PawPrint } from "lucide-react"
import { getHerdReport, type HerdRow } from "@/lib/api/livestock"
import { ReportTable, REPORTS_BACK } from "@/components/livestock/report-bits"
import { LivestockPage, LoadError, Loading, StatCard, fmtNum } from "@/components/livestock/livestock-page"

export default function LivestockHerdReportPage() {
  const [rows, setRows] = useState<HerdRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null); setRows(null)
    try { setRows(await getHerdReport()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage title="Herd make-up" description="Animals of each kind now. Sex and age come from tagged animals." icon={PawPrint} back={REPORTS_BACK}>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Animals" value={fmtNum(rows.reduce((s, r) => s + r.head, 0))} tone="amber" />
            <StatCard label="Tagged" value={fmtNum(rows.reduce((s, r) => s + r.tagged, 0))} />
          </div>
          <ReportTable rows={rows} rowKey={(r) => r.speciesCode} empty="No kinds of animal chosen yet." cols={[
            { label: "Kind", cell: (r) => r.name },
            { label: "Animals", right: true, cell: (r) => fmtNum(r.head) },
            { label: "Groups", right: true, cell: (r) => fmtNum(r.groups) },
            { label: "Tagged", right: true, cell: (r) => fmtNum(r.tagged) },
            { label: "Female", right: true, cell: (r) => fmtNum(r.females) },
            { label: "Male", right: true, cell: (r) => fmtNum(r.males) },
            { label: "Under 6 months", right: true, cell: (r) => fmtNum(r.ageBands.under6Months) },
            { label: "6–12 months", right: true, cell: (r) => fmtNum(r.ageBands.sixTo12Months) },
            { label: "1–2 years", right: true, cell: (r) => fmtNum(r.ageBands.oneTo2Years) },
            { label: "Over 2 years", right: true, cell: (r) => fmtNum(r.ageBands.over2Years) },
            { label: "Age not known", right: true, cell: (r) => fmtNum(r.ageBands.unknown) },
          ]} />
        </>
      )}
    </LivestockPage>
  )
}

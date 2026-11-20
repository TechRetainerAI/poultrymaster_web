"use client"

// One daily record: what was recorded and what it cost. Edit re-posts the
// whole record; delete puts its animals and stock back.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { ClipboardList, Pencil, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { deleteProductionRecord, getProductionRecord, type ProductionRecord } from "@/lib/api/livestock"
import {
  AMBER_BUTTON, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum,
} from "@/components/livestock/livestock-page"

export default function LivestockProductionRecordPage() {
  const { id } = useParams<{ id: string }>()
  const recordId = Number(id)
  const router = useRouter()
  const [r, setR] = useState<ProductionRecord | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setR(await getProductionRecord(recordId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [recordId])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-production-records", label: "Daily records" }
  if (error) return <LivestockPage title="Daily record" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!r) return <LivestockPage title="Daily record" back={back}><Loading /></LivestockPage>

  return (
    <LivestockPage
      title={`${r.groupName} · ${fmtDate(r.date)}`}
      description={<>{r.speciesName} · <Link className="text-amber-800 hover:underline" href={`/livestock-groups/${r.groupId}`}>open group</Link>{r.createdBy && ` · recorded by ${r.createdBy}`}</>}
      icon={ClipboardList}
      back={back}
      actions={
        <>
          <Button asChild className={AMBER_BUTTON}><Link href={`/livestock-production-records/${recordId}/edit`}><Pencil className="h-4 w-4 mr-1" />Edit</Link></Button>
          <Button variant="outline" onClick={() => setDeleting(true)}><Trash2 className="h-4 w-4 text-rose-600" /></Button>
        </>
      }
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <StatCard label="Animals end of day" value={fmtNum(r.headEndOfDay)} tone="amber" />
        <StatCard label="Died" value={fmtNum(r.deaths)} tone={r.deaths ? "rose" : "stone"} hint={r.deathCause ?? undefined} />
        <StatCard label="Culled" value={fmtNum(r.culls)} />
        <StatCard label="Feed & medicine cost" value={fmtMoney(r.feedCost + r.medicationCost)} />
      </div>

      {(r.eggsCollected != null || r.milkLitres != null || r.waterLitres != null) && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
          {r.eggsCollected != null && <StatCard label="Eggs collected" value={fmtNum(r.eggsCollected)} hint={r.eggsBroken ? `${r.eggsBroken} broken` : undefined} />}
          {r.milkLitres != null && <StatCard label="Milk" value={`${fmtNum(r.milkLitres)} L`} />}
          {r.waterLitres != null && <StatCard label="Water" value={`${fmtNum(r.waterLitres)} L`} />}
        </div>
      )}

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Feed and medicine used</CardTitle></CardHeader>
        <CardContent>
          {r.lines.length === 0 ? <p className="text-sm text-stone-500">None recorded.</p> : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Item</TableHead><TableHead>Kind</TableHead>
                  <TableHead className="text-right">Quantity</TableHead><TableHead className="text-right">Cost each</TableHead>
                  <TableHead className="text-right">Cost</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {r.lines.map((l) => (
                  <TableRow key={l.lineId}>
                    <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-items/${l.itemId}`}>{l.itemName}</Link></TableCell>
                    <TableCell>{l.lineType === "Feed" ? "Feed" : "Medicine"}</TableCell>
                    <TableCell className="text-right">{fmtNum(l.quantity)} {l.unit}</TableCell>
                    <TableCell className="text-right">{fmtMoney(l.unitCost)}</TableCell>
                    <TableCell className="text-right">{fmtMoney(l.totalCost)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {r.notes && <Card><CardContent className="p-4 text-sm text-stone-700 whitespace-pre-wrap">{r.notes}</CardContent></Card>}

      <ConfirmDeleteDialog
        open={deleting}
        onOpenChange={setDeleting}
        title="Delete this daily record?"
        description="Its deaths and culls go back into the group's count, and its feed and medicine go back into stock."
        onConfirm={() => deleteProductionRecord(recordId)}
        onSuccess={() => router.push("/livestock-production-records")}
      />
    </LivestockPage>
  )
}

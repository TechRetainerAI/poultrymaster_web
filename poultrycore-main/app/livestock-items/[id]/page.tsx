"use client"

// One stock item: its stock, value and every movement -- opening, stock in,
// what each daily record used, corrections. A manual movement can be
// reversed here; usage is changed on the daily record that made it.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { Boxes, Pencil, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { deleteItem, getItem, reverseStockChange, type LivestockItemDetail, type StockMovement, type StockMovementType } from "@/lib/api/livestock"
import { ItemFormDialog, StockChangeDialog, CATEGORY_LABEL } from "@/components/livestock/stock-dialogs"
import {
  AMBER_BUTTON, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum,
} from "@/components/livestock/livestock-page"

const TYPE_LABEL: Record<StockMovementType, string> = {
  Opening: "Opening stock", StockIn: "Stock in", Purchase: "Purchase", Usage: "Used", Adjustment: "Count correction",
  Produced: "Mixed", Loss: "Lost"
}

export default function LivestockItemPage() {
  const { id } = useParams<{ id: string }>()
  const itemId = Number(id)
  const router = useRouter()
  const [item, setItem] = useState<LivestockItemDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [dialog, setDialog] = useState<null | "edit" | "change" | "delete">(null)
  const [reversing, setReversing] = useState<StockMovement | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setItem(await getItem(itemId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [itemId])
  useEffect(() => { load() }, [load])

  const back = { href: "/livestock-items", label: "Feed & stock" }
  if (error) return <LivestockPage title="Stock item" back={back}><LoadError message={error} onRetry={load} /></LivestockPage>
  if (!item) return <LivestockPage title="Stock item" back={back}><Loading /></LivestockPage>

  return (
    <LivestockPage
      title={<>{item.name}{!item.isActive && <Badge variant="outline" className="ml-2 align-middle">Unused</Badge>}</>}
      description={[CATEGORY_LABEL[item.category], item.speciesName ? `for ${item.speciesName.toLowerCase()}` : null,
        `counted in ${item.unit}`, item.kgPerUnit && item.unit !== "kg" ? `${item.kgPerUnit} kg each` : null].filter(Boolean).join(" · ")}
      icon={Boxes}
      back={back}
      actions={
        <>
          {item.isActive && <Button className={AMBER_BUTTON} onClick={() => setDialog("change")}>Add / correct stock</Button>}
          <Button variant="outline" onClick={() => setDialog("edit")}><Pencil className="h-4 w-4 mr-1" />Edit</Button>
          {!item.hasMovements && (
            <Button variant="outline" onClick={() => setDialog("delete")}><Trash2 className="h-4 w-4 text-rose-600" /></Button>
          )}
        </>
      }
    >
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="In stock" value={`${fmtNum(item.stock)} ${item.unit}`} tone={item.isLow ? "rose" : "amber"}
          hint={item.minimumStock != null ? `Warning at ${fmtNum(item.minimumStock)}` : undefined} />
        <StatCard label="Average cost" value={item.avgCost == null ? "—" : fmtMoney(item.avgCost)} hint={`per ${item.unit}`} />
        <StatCard label="Value" value={fmtMoney(item.value)} />
      </div>

      <div className="rounded-md border bg-white overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>What</TableHead>
              <TableHead className="text-right">Quantity</TableHead>
              <TableHead className="text-right">Cost each</TableHead>
              <TableHead className="text-right">Value</TableHead>
              <TableHead>Details</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {item.movements.length === 0 && (
              <TableRow><TableCell colSpan={7} className="text-center text-stone-500 py-6">No stock recorded yet.</TableCell></TableRow>
            )}
            {item.movements.map((m) => (
              <TableRow key={m.movementId} className={m.reversedAt ? "opacity-50" : undefined}>
                <TableCell className="whitespace-nowrap">{fmtDate(m.date)}</TableCell>
                <TableCell>{TYPE_LABEL[m.type]}{m.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                <TableCell className={`text-right font-medium ${m.quantity < 0 ? "text-rose-700" : "text-emerald-700"}`}>
                  {m.quantity > 0 ? "+" : ""}{fmtNum(m.quantity)}
                </TableCell>
                <TableCell className="text-right">{m.unitCost == null ? "—" : fmtMoney(m.unitCost)}</TableCell>
                <TableCell className="text-right">{fmtMoney(m.totalCost)}</TableCell>
                <TableCell className="text-sm text-stone-600">
                  {m.sourceType === "ProductionRecord" && m.sourceId
                    ? <Link className="text-amber-800 hover:underline" href={`/livestock-production-records/${m.sourceId}`}>{m.groupName ?? "Daily record"}</Link>
                    : m.sourceType === "FeedRun"
                    ? <Link className="text-amber-800 hover:underline" href="/livestock-feed-production">{m.notes}</Link>
                    : m.sourceType === "TreatmentDay" || m.sourceType === "HealthRecord"
                    ? <>{m.notes}{m.groupName && m.notes?.indexOf(m.groupName) === -1 ? ` · ${m.groupName}` : ""}</>
                    : m.notes}
                  {m.reverseReason && <div className="text-xs">Reversed: {m.reverseReason}</div>}
                </TableCell>
                <TableCell className="text-right">
                  {!m.sourceType && !m.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(m)}>Reverse</Button>}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <ItemFormDialog open={dialog === "edit"} onOpenChange={(o) => !o && setDialog(null)} item={item} onSaved={load} />
      {dialog === "change" && <StockChangeDialog item={item} onClose={() => setDialog(null)} onDone={() => { setDialog(null); load() }} />}
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this stock change?"
        description={reversing ? `${TYPE_LABEL[reversing.type]} of ${fmtNum(Math.abs(reversing.quantity))} ${item.unit} on ${fmtDate(reversing.date)}.` : undefined}
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseStockChange(reversing!.movementId, reason); setReversing(null); load() }}
      />
      <ConfirmDeleteDialog
        open={dialog === "delete"}
        onOpenChange={(o) => !o && setDialog(null)}
        title={`Delete ${item.name}?`}
        onConfirm={() => deleteItem(itemId)}
        onSuccess={() => router.push("/livestock-items")}
      />
    </LivestockPage>
  )
}

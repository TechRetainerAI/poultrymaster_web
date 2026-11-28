"use client"

// Pharmacy -> Prescriptions (migration 511): every prescription a Class A (prescription-only)
// sale was dispensed against, recorded at the Pharmacy till with the sale.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, ShoppingCart } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { PharmacyShell } from "@/components/generic/pharmacy/pharmacy-shell"
import { getPrescriptions, type Prescription } from "@/lib/api/generic-pharmacy"

const iso = (d: Date) => d.toISOString().slice(0, 10)
const fmtQty = (n: number) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 3 }).format(n)

export default function GenericPrescriptionsPage() {
  const { toast } = useToast()
  const [from, setFrom] = useState(() => iso(new Date(Date.now() - 30 * 86_400_000)))
  const [to, setTo] = useState(() => iso(new Date()))
  const [rows, setRows] = useState<Prescription[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  const load = async () => {
    setLoading(true)
    try { setRows(await getPrescriptions(from || null, to || null)) }
    catch (e: any) { toast({ title: "Could not load prescriptions", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { load() }, [from, to]) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((r) => [r.patientName, r.patientPhone, r.prescriberName, r.prescriberFacility, r.prescriptionRef, r.receiptNumber,
      ...r.items.map((i) => i.medicineName)].some((v) => (v ?? "").toLowerCase().includes(q)))
  }, [rows, search])

  return (
    <PharmacyShell
      title="Prescriptions"
      subtitle="Prescriptions recorded with prescription-only (Class A) sales"
      wide
      actions={<Button asChild><Link href="/generic-pharmacy-pos"><ShoppingCart className="h-4 w-4 mr-1" /> Open the till</Link></Button>}
    >
      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap items-end gap-2">
            <div><Label className="text-xs">From</Label><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
            <div><Label className="text-xs">To</Label><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
            <Input className="max-w-xs" placeholder="Search patient, doctor, medicine, receipt" value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
          ) : filtered.length === 0 ? (
            <p className="py-10 text-center text-sm text-slate-500">No prescriptions in this period.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Patient</TableHead>
                    <TableHead>Prescriber</TableHead>
                    <TableHead>Medicines dispensed</TableHead>
                    <TableHead>Sale</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((r) => (
                    <TableRow key={r.genericPrescriptionId}>
                      <TableCell className="whitespace-nowrap">{String(r.prescriptionDate).slice(0, 10)}</TableCell>
                      <TableCell>
                        <div className="font-medium">{r.patientName}</div>
                        {r.patientPhone && <div className="text-xs text-slate-500">{r.patientPhone}</div>}
                      </TableCell>
                      <TableCell>
                        <div>{r.prescriberName}</div>
                        <div className="text-xs text-slate-500">{[r.prescriberFacility, r.prescriptionRef && `No. ${r.prescriptionRef}`].filter(Boolean).join(" · ")}</div>
                      </TableCell>
                      <TableCell className="text-sm">
                        {r.items.map((i, k) => (
                          <div key={k}>
                            {fmtQty(i.quantity)} {i.unit ?? ""} {i.medicineName}
                            {i.directions && <span className="text-xs text-slate-500"> · {i.directions}</span>}
                          </div>
                        ))}
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-sm">
                        {r.genericSaleId ? (
                          <Link className="text-emerald-700 underline" href={`/generic-sales/${r.genericSaleId}`}>{r.receiptNumber ?? `#${r.genericSaleId}`}</Link>
                        ) : "—"}
                        {r.saleStatus && r.saleStatus !== "Approved" && <Badge variant="secondary" className="ml-1">{r.saleStatus}</Badge>}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </PharmacyShell>
  )
}

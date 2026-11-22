"use client"

// Customers -- the shared customer list, with what each owes this farm.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Pencil, Plus, Users } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listCustomerBalances, type CustomerBalance, type LsCustomer } from "@/lib/api/livestock"
import { CustomerDialog, useCustomers } from "@/components/livestock/customer-select"
import { AMBER_BUTTON, EmptyState, LivestockPage, fmtMoney } from "@/components/livestock/livestock-page"

export default function LivestockCustomersPage() {
  const { customers, reload } = useCustomers()
  const [balances, setBalances] = useState<CustomerBalance[]>([])
  const [search, setSearch] = useState("")
  const [editing, setEditing] = useState<{ customer?: LsCustomer } | null>(null)
  useEffect(() => { listCustomerBalances().then(setBalances).catch(() => setBalances([])) }, [customers])
  const owes = useMemo(() => new Map(balances.map((b) => [b.customerId, b.owes])), [balances])
  const shown = customers.filter((c) => !search.trim() || `${c.name} ${c.contactPhone}`.toLowerCase().includes(search.trim().toLowerCase()))
  const pg = usePagination(shown, 10)

  return (
    <LivestockPage title="Customers" description="Who you sell animals, eggs and milk to." icon={Users}
      actions={<Button className={AMBER_BUTTON} onClick={() => setEditing({})}><Plus className="h-4 w-4 mr-1" /> Add customer</Button>}>
      <Input className="w-64" placeholder="Name or phone" value={search} onChange={(e) => setSearch(e.target.value)} />
      {shown.length === 0 ? <EmptyState title={search ? "No customer matches" : "No customers yet"} /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Name</TableHead><TableHead>Phone</TableHead><TableHead>Address</TableHead><TableHead className="text-right">Owes</TableHead><TableHead /></TableRow></TableHeader>
            <TableBody>
              {pg.pageItems.map((c) => (
                <TableRow key={c.customerId}>
                  <TableCell className="font-medium">{c.name}</TableCell>
                  <TableCell>{c.contactPhone || "—"}</TableCell>
                  <TableCell>{[c.address, c.city].filter(Boolean).join(", ") || "—"}</TableCell>
                  <TableCell className="text-right">{owes.get(c.customerId) ? <Link className="text-amber-800 hover:underline" href={`/livestock-customer-balances?customerId=${c.customerId}`}>{fmtMoney(owes.get(c.customerId))}</Link> : "—"}</TableCell>
                  <TableCell className="text-right"><Button variant="ghost" size="icon" aria-label={`Edit ${c.name}`} onClick={() => setEditing({ customer: c })}><Pencil className="h-4 w-4" /></Button></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
      {editing && <CustomerDialog customer={editing.customer} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); reload() }} />}
    </LivestockPage>
  )
}

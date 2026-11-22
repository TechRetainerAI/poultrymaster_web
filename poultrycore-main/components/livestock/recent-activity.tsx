"use client"

// Recent Activity for the livestock dashboard -- the poultry dashboard's
// Recent Activity card for livestock. The last 30 days of daily records,
// sales, payments received, purchases, expenses, health records and breeding,
// newest first; each row opens the page it came from. Built in the browser
// from the module's own list endpoints, as the poultry card is.

import { useEffect, useState, type ComponentType } from "react"
import Link from "next/link"
import { Baby, ClipboardList, HandCoins, HeartPulse, Receipt, ShoppingBag, ShoppingCart } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import {
  listBreeding, listCustomerPayments, listExpenses, listHealth, listProductionRecords, listPurchases, listSales,
} from "@/lib/api/livestock"
import { daysAgo } from "@/components/livestock/money-bits"
import { fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

type Kind = "record" | "sale" | "payment" | "purchase" | "expense" | "health" | "breeding"
interface Activity { id: string; kind: Kind; date: string; at: string | null; text: string; detail?: string; href: string }

const STYLE: Record<Kind, { icon: ComponentType<{ className?: string }>; tone: string }> = {
  record:   { icon: ClipboardList, tone: "bg-amber-50 border-amber-200 text-amber-700" },
  sale:     { icon: ShoppingBag,   tone: "bg-emerald-50 border-emerald-200 text-emerald-700" },
  payment:  { icon: HandCoins,     tone: "bg-emerald-50 border-emerald-200 text-emerald-700" },
  purchase: { icon: ShoppingCart,  tone: "bg-stone-50 border-stone-200 text-stone-600" },
  expense:  { icon: Receipt,       tone: "bg-rose-50 border-rose-200 text-rose-700" },
  health:   { icon: HeartPulse,    tone: "bg-sky-50 border-sky-200 text-sky-700" },
  breeding: { icon: Baby,          tone: "bg-violet-50 border-violet-200 text-violet-700" },
}

const SHOW = 12

function when(date: string) {
  const d = date.slice(0, 10)
  const diff = Math.round((new Date(todayIso() + "T00:00:00").getTime() - new Date(d + "T00:00:00").getTime()) / 86400000)
  if (diff <= 0) return "Today"
  if (diff === 1) return "Yesterday"
  if (diff < 7) return `${diff} days ago`
  return new Date(d + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short" })
}

export function RecentActivity({ showBreeding = true }: { showBreeding?: boolean }) {
  const [items, setItems] = useState<Activity[] | null>(null)

  useEffect(() => {
    const from = daysAgo(30)
    const to = todayIso()
    const safe = <T,>(p: Promise<T[]>) => p.catch(() => [] as T[])
    Promise.all([
      safe(listProductionRecords({ from, to })),
      safe(listSales({ from, to })),
      safe(listCustomerPayments()),
      safe(listPurchases({ status: "All", from, to })),
      safe(listExpenses({ from, to })),
      safe(listHealth({ from, to })),
      showBreeding ? safe(listBreeding({ from, to })) : Promise.resolve([]),
    ]).then(([records, sales, payments, purchases, expenses, health, breeding]) => {
      const out: Activity[] = []
      for (const r of records) {
        const bits = [
          r.eggsCollected != null && `${fmtNum(r.eggsCollected)} eggs`,
          r.milkLitres != null && `${fmtNum(r.milkLitres)} L milk`,
          r.deaths > 0 && `${r.deaths} died`,
          r.feedKg ? `${fmtNum(r.feedKg)} kg feed` : null,
        ].filter(Boolean)
        out.push({ id: `r${r.recordId}`, kind: "record", date: r.date, at: r.createdAt, href: `/livestock-production-records/${r.recordId}`,
          text: `Daily record · ${r.groupName}`, detail: bits.join(" · ") || undefined })
      }
      for (const s of sales) {
        if (s.reversedAt) continue
        out.push({ id: `s${s.saleId}`, kind: "sale", date: s.date, at: null, href: `/livestock-sales/${s.saleId}`,
          text: `Sale to ${s.customerName ?? "walk-in customer"}`, detail: `${fmtMoney(s.total)}${s.owed > 0 ? ` · ${fmtMoney(s.owed)} owed` : ""}` })
      }
      for (const p of payments) {
        // Money taken with a sale already shows on the sale.
        if (p.reversedAt || p.isUpfront || p.date.slice(0, 10) < from) continue
        out.push({ id: `p${p.paymentId}`, kind: "payment", date: p.date, at: null,
          href: p.customerId ? `/livestock-customer-balances?customerId=${p.customerId}` : "/livestock-customer-balances",
          text: `Payment from ${p.customerName ?? "customer"}`, detail: `${fmtMoney(p.amount)} into ${p.accountName}` })
      }
      for (const p of purchases) {
        if (p.reversedAt) continue
        out.push({ id: `u${p.purchaseId}`, kind: "purchase", date: p.date, at: null, href: `/livestock-purchases/${p.purchaseId}`,
          text: `Purchase from ${p.supplierName ?? "supplier"}`, detail: `${fmtMoney(p.total)}${p.owed > 0 ? ` · ${fmtMoney(p.owed)} owed` : ""}` })
      }
      for (const e of expenses) {
        // Bills come from purchases, which are listed already.
        if (e.reversedAt || e.source !== "Paid") continue
        out.push({ id: `e${e.id}`, kind: "expense", date: e.date, at: null, href: "/livestock-expenses",
          text: `${e.category}${e.description ? `: ${e.description}` : ""}`, detail: fmtMoney(e.amount) })
      }
      for (const h of health) {
        out.push({ id: `h${h.healthId}`, kind: "health", date: h.date, at: null, href: "/livestock-health",
          text: `${h.stepName ?? (h.kind === "VetVisit" ? "Vet visit" : h.kind)} · ${h.tagNumber ?? h.groupName}`,
          detail: [h.diagnosis, h.itemName && `${h.itemName}${h.quantity != null ? ` ${fmtNum(h.quantity)} ${h.unit ?? ""}` : ""}`].filter(Boolean).join(" · ") || undefined })
      }
      for (const b of breeding) {
        const who = b.damTag ?? b.groupName ?? b.speciesName
        const text = b.eventType === "Birth"
          ? `${b.birthTerm ?? "Birth"} · ${who}`
          : `${b.eventType === "PregnancyCheck" ? "Pregnancy check" : b.eventType} · ${who}`
        const detail = b.eventType === "Birth" ? `${b.bornAlive ?? 0} born alive${b.bornDead ? `, ${b.bornDead} dead` : ""}`
          : b.eventType === "PregnancyCheck" && b.result ? (b.result === "Pregnant" ? "Pregnant" : "Not pregnant")
          : b.eventType === "Weaning" && b.weanedCount != null ? `${b.weanedCount} weaned` : undefined
        out.push({ id: `b${b.eventId}`, kind: "breeding", date: b.date, at: null, href: "/livestock-breeding", text, detail })
      }
      out.sort((a, b) => (b.date.slice(0, 10).localeCompare(a.date.slice(0, 10))) || (b.at ?? "").localeCompare(a.at ?? ""))
      setItems(out.slice(0, SHOW))
    })
  }, [showBreeding])

  return (
    <Card>
      <CardHeader className="pb-2"><CardTitle className="text-base text-stone-900">Recent activity</CardTitle></CardHeader>
      <CardContent>
        {items === null ? (
          <p className="text-sm text-stone-500 py-6 text-center">Loading activity…</p>
        ) : items.length === 0 ? (
          <p className="text-sm text-stone-500 py-6 text-center">Nothing recorded in the last 30 days.</p>
        ) : (
          <ul className="space-y-2">
            {items.map((a) => {
              const { icon: Icon, tone } = STYLE[a.kind]
              return (
                <li key={a.id}>
                  <Link href={a.href} className={`flex items-start gap-3 rounded-lg border p-2.5 hover:brightness-95 ${tone}`}>
                    <Icon className="h-4 w-4 mt-0.5 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-stone-800 leading-snug truncate">{a.text}</p>
                      {a.detail && <p className="text-xs text-stone-500 mt-0.5 truncate">{a.detail}</p>}
                    </div>
                    <span className="text-xs text-stone-400 whitespace-nowrap">{when(a.date)}</span>
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}

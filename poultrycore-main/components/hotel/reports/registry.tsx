"use client"

/**
 * The ten server-side Hotel reports added in migration 299, defined as data.
 *
 * Same shape as the Restaurant registry and rendered by the same shared shell
 * and table primitive under components/reports/, so a hotel report cannot ship
 * without a date range or without PDF and CSV — it never implements them.
 *
 * These are the STANDARD lodging reports the module was missing, not novel
 * ones: source of business, booking pace, room type performance, the ADR /
 * RevPAR / TRevPAR / GOPPAR set, guest ledger, ancillary revenue,
 * cancellations, length of stay, housekeeping productivity and loyalty.
 *
 * The 17 pre-existing hotel reports are untouched and still live in their own
 * directories under app/hotel-reports/; Next resolves those before the [slug]
 * router that reads this registry.
 */

import type { ReactNode } from "react"
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  PieChart, Pie, Cell,
} from "recharts"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { ToneBadge } from "@/components/reports/report-table"
import type { ColumnDef, ReportDefinition } from "@/components/reports/report-table"
import {
  getSourceOfBusiness, getBookingPace, getRoomTypePerformance,
  getHotelPerformanceKpis, getGuestLedger, getAncillaryRevenue,
  getHotelCancellations, getLengthOfStay, getHousekeepingProductivity,
  getHotelLoyaltyReport,
} from "@/lib/api/hotel"
import type { HotelPerformanceKpis } from "@/lib/api/hotel"

const VIOLET = "#6d28d9"
const VIOLET_LIGHT = "#c4b5fd"
const PIE_COLORS = ["#6d28d9", "#7c3aed", "#8b5cf6", "#a78bfa", "#c4b5fd", "#4c1d95", "#5b21b6", "#ddd6fe"]

/** A label/value pair, for the report whose answer is a set of figures. */
interface MetricRow { metric: string; value: string }

const METRIC_COLUMNS: ColumnDef<MetricRow>[] = [
  { key: "metric", label: "Metric", value: (r) => r.metric },
  { key: "value", label: "Value", value: (r) => r.value, numeric: true },
]

function chartCard(title: string, hint: string, body: ReactNode) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{title}</CardTitle>
        <CardDescription>{hint}</CardDescription>
      </CardHeader>
      <CardContent>{body}</CardContent>
    </Card>
  )
}

// ===========================================================================
// REVENUE MANAGEMENT
// ===========================================================================

const performanceKpis: ReportDefinition<MetricRow, HotelPerformanceKpis> = {
  load: async (r) => ({ rows: [], meta: await getHotelPerformanceKpis(r.from, r.to) }),
  summary: (r, f) => {
    const k = r.meta
    if (!k) return []
    return [
      { label: "Occupancy", value: f.pct(k.occupancyPct) },
      { label: "ADR", value: f.money(k.adr) },
      { label: "RevPAR", value: f.money(k.revpar) },
      { label: "GOPPAR", value: f.money(k.goppar) },
    ]
  },
  panel: (r, f) => {
    const k = r.meta
    if (!k) return null
    // The one caveat worth surfacing rather than hiding: ADR and RevPAR are
    // room revenue over rooms, so if the daily closing recorded a total but
    // never split out room revenue, both read zero. That is honest output from
    // incomplete input, and saying so beats a number invented from bookings.
    const splitMissing = k.roomRevenue === 0 && k.totalRevenue > 0
    return (
      <div className="space-y-4">
        {splitMissing && (
          <Card className="border-amber-200 bg-amber-50">
            <CardContent className="py-3 text-sm text-amber-900">
              ADR and RevPAR read zero because the daily closings in this period recorded a total
              revenue figure but no <strong>room revenue</strong> split. TRevPAR and GOPPAR below are
              unaffected, since they use total revenue. Fill in the room / F&amp;B / other split on
              daily closing and these will populate.
            </CardContent>
          </Card>
        )}
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Revenue</CardTitle></CardHeader>
            <CardContent>
              {[
                ["Rooms", f.money(k.roomRevenue)],
                ["Food & beverage", f.money(k.fnbRevenue)],
                ["Other", f.money(k.otherRevenue)],
                ["Total revenue", f.money(k.totalRevenue)],
                ["Less operating expenses", `- ${f.money(k.totalExpenses)}`],
                ["Gross operating profit", f.money(k.grossOperatingProfit)],
              ].map(([l, v], i, arr) => (
                <div
                  key={String(l)}
                  className={`flex justify-between gap-3 py-2 border-b last:border-0 ${
                    i === arr.length - 1 || i === 3 ? "font-semibold" : ""
                  }`}
                >
                  <span className="text-sm">{l}</span>
                  <span className="text-sm tabular-nums">{v}</span>
                </div>
              ))}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Per available room</CardTitle>
              <CardDescription>All four divide by the same {f.int(k.availableRoomNights)} available room nights.</CardDescription>
            </CardHeader>
            <CardContent>
              {[
                ["RevPAR — rooms revenue", f.money(k.revpar), "muted"],
                ["TRevPAR — total revenue", f.money(k.trevpar), "muted"],
                ["GOPPAR — operating profit", f.money(k.goppar), k.goppar > 0 ? "good" : "bad"],
                ["Occupancy", f.pct(k.occupancyPct), k.occupancyPct >= 70 ? "good" : k.occupancyPct >= 50 ? "warn" : "bad"],
                ["No-shows (night audit)", f.int(k.noshowCount), "muted"],
              ].map(([l, v, tone]) => (
                <div key={String(l)} className="flex justify-between items-center gap-3 py-2 border-b last:border-0">
                  <span className="text-sm">{l}</span>
                  <ToneBadge text={String(v)} tone={tone as "good" | "warn" | "bad" | "muted"} />
                </div>
              ))}
            </CardContent>
          </Card>
        </div>
      </div>
    )
  },
  columns: METRIC_COLUMNS,
  tableTitle: "Every figure for this period",
  emptyText: "No daily closings in this period. These figures come from daily closing, so close a day to populate them.",
}

const sourceOfBusiness: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getSourceOfBusiness(r.from, r.to) }),
  summary: (r, f) => {
    const rev = r.rows.reduce((s: number, x: any) => s + x.revenueTotal, 0)
    const nights = r.rows.reduce((s: number, x: any) => s + x.roomNights, 0)
    return [
      { label: "Revenue", value: f.money(rev) },
      { label: "Room nights", value: f.int(nights) },
      { label: "Blended ADR", value: nights > 0 ? f.money(rev / nights) : f.money(0) },
      { label: "Top channel", value: r.rows[0]?.sourceLabel ?? "—" },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Revenue by channel", "Where the business actually comes from",
      <ResponsiveContainer width="100%" height={280}>
        <PieChart>
          <Pie data={r.rows} dataKey="revenueTotal" nameKey="sourceLabel" cx="50%" cy="50%" outerRadius={95}
               label={({ sourceLabel, percent }: any) => `${sourceLabel} ${(percent * 100).toFixed(0)}%`} labelLine={false}>
            {r.rows.map((_: any, i: number) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
          </Pie>
          <Tooltip formatter={(v: number) => v.toFixed(2)} />
        </PieChart>
      </ResponsiveContainer>),
  columns: [
    { key: "s", label: "Channel", value: (r) => r.sourceLabel },
    { key: "b", label: "Bookings", value: (r, f) => f.int(r.bookingCount), numeric: true },
    { key: "n", label: "Room nights", value: (r, f) => f.int(r.roomNights), numeric: true },
    { key: "g", label: "Guests", value: (r, f) => f.int(r.guestCount), numeric: true, secondary: true },
    { key: "adr", label: "ADR", value: (r, f) => f.money(r.adr), numeric: true },
    { key: "lead", label: "Avg lead", value: (r, f) => `${f.num(r.avgLeadDays, 1)} d`, numeric: true, secondary: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
    { key: "sh", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Channels",
  tableHint: "ADR is revenue over room nights, so a long stay and a short one are not weighted the same.",
  emptyText: "No bookings starting in this period.",
}

const bookingPace: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getBookingPace(r.from, r.to) }),
  summary: (r, f) => {
    const total = r.rows.reduce((s: number, x: any) => s + x.bookingCount, 0)
    const sameDay = r.rows.find((x: any) => x.leadBucket === "Same day")?.bookingCount ?? 0
    const far = r.rows.filter((x: any) => x.bucketOrder >= 4).reduce((s: number, x: any) => s + x.bookingCount, 0)
    return [
      { label: "Bookings made", value: f.int(total) },
      { label: "Revenue booked", value: f.money(r.rows.reduce((s: number, x: any) => s + x.revenueTotal, 0)) },
      { label: "Same-day share", value: total > 0 ? f.pct((sameDay / total) * 100) : f.pct(0) },
      { label: "31+ days ahead", value: total > 0 ? f.pct((far / total) * 100) : f.pct(0) },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("How far ahead people book",
      "Counted by the date the booking was MADE, not the date of the stay",
      <ResponsiveContainer width="100%" height={280}>
        <BarChart data={r.rows}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis dataKey="leadBucket" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="l" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11 }} />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Legend />
          <Bar yAxisId="l" dataKey="revenueTotal" name="Revenue" fill={VIOLET} radius={[4, 4, 0, 0]} />
          <Bar yAxisId="r" dataKey="bookingCount" name="Bookings" fill={VIOLET_LIGHT} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>),
  columns: [
    { key: "b", label: "Booked ahead", value: (r) => r.leadBucket },
    { key: "n", label: "Bookings", value: (r, f) => f.int(r.bookingCount), numeric: true },
    { key: "rn", label: "Room nights", value: (r, f) => f.int(r.roomNights), numeric: true },
    { key: "adr", label: "ADR", value: (r, f) => f.money(r.adr), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
    { key: "sh", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Lead time",
  emptyText: "No bookings were made in this period.",
}

const roomTypePerformance: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getRoomTypePerformance(r.from, r.to) }),
  summary: (r, f) => {
    const rev = r.rows.reduce((s: number, x: any) => s + x.revenueTotal, 0)
    const best = r.rows.reduce((b: any, x: any) => (!b || x.revpar > b.revpar ? x : b), null as any)
    const idle = r.rows.filter((x: any) => x.roomNights === 0).length
    return [
      { label: "Revenue", value: f.money(rev) },
      { label: "Room types", value: f.int(r.rows.length) },
      { label: "Best RevPAR", value: best ? `${best.typeLabel} — ${f.money(best.revpar)}` : "—" },
      { label: "Types with no sales", value: f.int(idle) },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("RevPAR and ADR by room type",
      "RevPAR is measured against that type's own room count, not the whole property",
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={r.rows}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis dataKey="typeLabel" tick={{ fontSize: 11 }} />
          <YAxis tick={{ fontSize: 11 }} />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Legend />
          <Bar dataKey="adr" name="ADR" fill={VIOLET_LIGHT} radius={[4, 4, 0, 0]} />
          <Bar dataKey="revpar" name="RevPAR" fill={VIOLET} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>),
  columns: [
    { key: "t", label: "Room type", value: (r) => r.typeLabel },
    { key: "rooms", label: "Rooms", value: (r, f) => f.int(r.roomsInType), numeric: true, secondary: true },
    { key: "b", label: "Bookings", value: (r, f) => f.int(r.bookingCount), numeric: true, secondary: true },
    { key: "n", label: "Room nights", value: (r, f) => f.int(r.roomNights), numeric: true },
    {
      key: "occ", label: "Occupancy", value: (r, f) => f.pct(r.occupancyPct), numeric: true,
      render: (r, f) => (
        <span className={r.occupancyPct >= 70 ? "text-emerald-700 font-semibold" : r.occupancyPct < 30 ? "text-red-700" : ""}>
          {f.pct(r.occupancyPct)}
        </span>
      ),
    },
    { key: "adr", label: "ADR", value: (r, f) => f.money(r.adr), numeric: true },
    { key: "rp", label: "RevPAR", value: (r, f) => f.money(r.revpar), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
  ],
  tableTitle: "Room types",
  emptyText: "No room types configured, or no bookings in this period.",
}

const lengthOfStay: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getLengthOfStay(r.from, r.to) }),
  summary: (r, f) => {
    const nights = r.rows.reduce((s: number, x: any) => s + x.roomNights, 0)
    const bookings = r.rows.reduce((s: number, x: any) => s + x.bookingCount, 0)
    const best = r.rows.reduce((b: any, x: any) => (!b || x.revenueTotal > b.revenueTotal ? x : b), null as any)
    return [
      { label: "Bookings", value: f.int(bookings) },
      { label: "Room nights", value: f.int(nights) },
      { label: "Average stay", value: bookings > 0 ? `${f.num(nights / bookings, 1)} nights` : "—" },
      { label: "Most valuable length", value: best ? best.losBucket : "—" },
    ]
  },
  panel: (r) =>
    r.rows.length === 0 ? null : chartCard("Stay length distribution", "Bookings and revenue by how many nights",
      <ResponsiveContainer width="100%" height={280}>
        <BarChart data={r.rows}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
          <XAxis dataKey="losBucket" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="l" tick={{ fontSize: 11 }} />
          <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11 }} />
          <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid #e2e8f0" }} />
          <Legend />
          <Bar yAxisId="l" dataKey="revenueTotal" name="Revenue" fill={VIOLET} radius={[4, 4, 0, 0]} />
          <Bar yAxisId="r" dataKey="bookingCount" name="Bookings" fill={VIOLET_LIGHT} radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>),
  columns: [
    { key: "l", label: "Stay length", value: (r) => r.losBucket },
    { key: "n", label: "Bookings", value: (r, f) => f.int(r.bookingCount), numeric: true },
    { key: "rn", label: "Room nights", value: (r, f) => f.int(r.roomNights), numeric: true },
    { key: "adr", label: "ADR", value: (r, f) => f.money(r.adr), numeric: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
    { key: "sh", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Length of stay",
  emptyText: "No bookings starting in this period.",
}

const cancellations: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getHotelCancellations(r.from, r.to) }),
  summary: (r, f) => {
    const lost = r.rows.reduce((s: number, x: any) => s + x.valueLost, 0)
    const n = r.rows.reduce((s: number, x: any) => s + x.cancelledCount, 0)
    const booked = r.rows.reduce((s: number, x: any) => s + x.bookedCount, 0)
    const worst = r.rows.reduce((b: any, x: any) => (!b || x.cancelRatePct > b.cancelRatePct ? x : b), null as any)
    return [
      { label: "Value lost", value: f.money(lost) },
      { label: "Bookings cancelled", value: f.int(n) },
      { label: "Overall cancel rate", value: booked > 0 ? f.pct((n / booked) * 100) : f.pct(0) },
      { label: "Worst channel", value: worst ? `${worst.sourceLabel} — ${f.pct(worst.cancelRatePct)}` : "—" },
    ]
  },
  panel: () => (
    <Card>
      <CardContent className="py-3 text-sm text-slate-600">
        This covers <strong>cancellations only</strong>. No-shows are not a booking status in this
        system — the only no-show figure recorded is the nightly count on the night audit, and it is
        shown in the <strong>Performance &amp; KPIs</strong> report where it actually lives.
      </CardContent>
    </Card>
  ),
  columns: [
    { key: "s", label: "Channel", value: (r) => r.sourceLabel },
    { key: "n", label: "Cancelled", value: (r, f) => f.int(r.cancelledCount), numeric: true },
    { key: "bk", label: "Of bookings", value: (r, f) => f.int(r.bookedCount), numeric: true, secondary: true },
    {
      key: "rate", label: "Cancel rate", value: (r, f) => f.pct(r.cancelRatePct), numeric: true,
      render: (r, f) => (
        <span className={r.cancelRatePct >= 30 ? "text-red-700 font-semibold" : r.cancelRatePct >= 15 ? "text-amber-700" : ""}>
          {f.pct(r.cancelRatePct)}
        </span>
      ),
    },
    { key: "rn", label: "Nights lost", value: (r, f) => f.int(r.nightsLost), numeric: true, secondary: true },
    { key: "lead", label: "Avg lead", value: (r, f) => `${f.num(r.avgLeadDays, 1)} d`, numeric: true, secondary: true },
    { key: "v", label: "Value lost", value: (r, f) => f.money(r.valueLost), numeric: true },
    { key: "sh", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Cancellations by channel",
  emptyText: "No bookings were cancelled in this period.",
}

// ===========================================================================
// FINANCIAL
// ===========================================================================

function ageTone(b: string): "good" | "warn" | "bad" | "muted" {
  if (b === "Current") return "good"
  if (b === "1-30 days") return "warn"
  return "bad"
}

const guestLedger: ReportDefinition<any> = {
  load: async () => ({ rows: await getGuestLedger() }),
  summary: (r, f) => {
    const owed = r.rows.reduce((s: number, x: any) => s + x.balanceDue, 0)
    const over = r.rows.filter((x: any) => x.ageBucket !== "Current")
    const over90 = r.rows.filter((x: any) => x.ageBucket === "Over 90 days")
    return [
      { label: "Total owed", value: f.money(owed) },
      { label: "Open invoices", value: f.int(r.rows.length) },
      { label: "Overdue", value: f.money(over.reduce((s: number, x: any) => s + x.balanceDue, 0)) },
      { label: "Over 90 days", value: f.money(over90.reduce((s: number, x: any) => s + x.balanceDue, 0)) },
    ]
  },
  panel: (r, f) => {
    if (r.rows.length === 0) return null
    const buckets = ["Current", "1-30 days", "31-60 days", "61-90 days", "Over 90 days"]
    const totals = buckets.map((b) => ({
      bucket: b,
      amount: r.rows.filter((x: any) => x.ageBucket === b).reduce((s: number, x: any) => s + x.balanceDue, 0),
      count: r.rows.filter((x: any) => x.ageBucket === b).length,
    })).filter((x) => x.count > 0)
    return (
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Ageing</CardTitle>
          <CardDescription>Aged from the due date, or the issue date where no due date was set.</CardDescription>
        </CardHeader>
        <CardContent>
          {totals.map((t) => (
            <div key={t.bucket} className="flex justify-between items-center gap-3 py-2 border-b last:border-0">
              <span className="text-sm">{t.bucket} <span className="text-slate-400">({t.count})</span></span>
              <ToneBadge text={f.money(t.amount)} tone={ageTone(t.bucket)} />
            </div>
          ))}
        </CardContent>
      </Card>
    )
  },
  columns: [
    { key: "i", label: "Invoice", value: (r) => r.invoiceRef },
    { key: "g", label: "Guest", value: (r) => r.guestLabel },
    { key: "d", label: "Issued", value: (r) => String(r.issuedOn).slice(0, 10), secondary: true },
    { key: "du", label: "Due", value: (r) => (r.dueOn ? String(r.dueOn).slice(0, 10) : "—"), secondary: true },
    { key: "t", label: "Invoice total", value: (r, f) => f.money(r.totalAmount), numeric: true, secondary: true },
    { key: "p", label: "Paid", value: (r, f) => f.money(r.paidAmount), numeric: true, secondary: true },
    { key: "b", label: "Balance", value: (r, f) => f.money(r.balanceDue), numeric: true },
    { key: "days", label: "Days out", value: (r, f) => f.int(r.daysOutstanding), numeric: true },
    {
      key: "age", label: "Age", value: (r) => r.ageBucket,
      render: (r) => <ToneBadge text={r.ageBucket} tone={ageTone(r.ageBucket)} />,
    },
  ],
  tableTitle: "Unpaid invoices, oldest first",
  emptyText: "Nothing outstanding — every invoice is settled.",
}

const ancillaryRevenue: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getAncillaryRevenue(r.from, r.to) }),
  summary: (r, f) => {
    const rev = r.rows.reduce((s: number, x: any) => s + x.revenueTotal, 0)
    const stays = Math.max(...r.rows.map((x: any) => x.staysTouched), 0)
    const top = r.rows[0]
    return [
      { label: "Ancillary revenue", value: f.money(rev) },
      { label: "Charges posted", value: f.int(r.rows.reduce((s: number, x: any) => s + x.chargeCount, 0)) },
      { label: "Charge types", value: f.int(r.rows.length) },
      { label: "Biggest earner", value: top ? `${top.chargeLabel} — ${f.money(top.revenueTotal)}` : "—" },
    ]
  },
  columns: [
    { key: "c", label: "Charge type", value: (r) => r.chargeLabel },
    { key: "n", label: "Charges", value: (r, f) => f.int(r.chargeCount), numeric: true },
    { key: "q", label: "Quantity", value: (r, f) => f.int(r.qtyTotal), numeric: true, secondary: true },
    { key: "s", label: "Stays touched", value: (r, f) => f.int(r.staysTouched), numeric: true, secondary: true },
    { key: "a", label: "Average", value: (r, f) => f.money(r.avgCharge), numeric: true, secondary: true },
    { key: "rev", label: "Revenue", value: (r, f) => f.money(r.revenueTotal), numeric: true },
    { key: "sh", label: "Share", value: (r, f) => f.pct(r.sharePct), numeric: true },
  ],
  tableTitle: "Charges beyond the room",
  emptyText: "No stay charges posted in this period.",
}

// ===========================================================================
// OPERATIONS
// ===========================================================================

const housekeepingProductivity: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getHousekeepingProductivity(r.from, r.to) }),
  summary: (r, f) => {
    const tasks = r.rows.reduce((s: number, x: any) => s + x.tasksTotal, 0)
    const timed = r.rows.reduce((s: number, x: any) => s + x.timedCount, 0)
    const weighted = timed > 0
      ? r.rows.reduce((s: number, x: any) => s + x.avgMinutes * x.timedCount, 0) / timed
      : 0
    const best = r.rows.reduce((b: any, x: any) => (!b || (x.timedCount > 0 && x.roomsPerShift > b.roomsPerShift) ? x : b), null as any)
    return [
      { label: "Tasks", value: f.int(tasks) },
      { label: "Timed tasks", value: `${f.int(timed)} of ${f.int(tasks)}` },
      { label: "Average per room", value: timed > 0 ? f.mins(weighted) : "not measured" },
      { label: "Fastest attendant", value: best && best.roomsPerShift > 0 ? `${best.attendantLabel} — ${f.num(best.roomsPerShift, 1)}/shift` : "—" },
    ]
  },
  panel: () => (
    <Card>
      <CardContent className="py-3 text-sm text-slate-600">
        Rooms per shift projects each attendant&apos;s average onto an eight-hour shift. The industry
        benchmark for a full clean is roughly <strong>12–16 rooms per attendant per shift</strong>.
        Only tasks carrying both a start and a completion time are counted, so a task still open does
        not drag an average down.
      </CardContent>
    </Card>
  ),
  columns: [
    { key: "a", label: "Attendant", value: (r) => r.attendantLabel },
    { key: "t", label: "Tasks", value: (r, f) => f.int(r.tasksTotal), numeric: true },
    { key: "c", label: "Completed", value: (r, f) => f.int(r.tasksCompleted), numeric: true, secondary: true },
    { key: "tc", label: "Timed", value: (r, f) => f.int(r.timedCount), numeric: true, secondary: true },
    { key: "avg", label: "Avg per room", value: (r, f) => (r.timedCount > 0 ? f.mins(r.avgMinutes) : "—"), numeric: true },
    { key: "fast", label: "Fastest", value: (r, f) => (r.timedCount > 0 ? f.mins(r.fastestMinutes) : "—"), numeric: true, secondary: true },
    { key: "slow", label: "Slowest", value: (r, f) => (r.timedCount > 0 ? f.mins(r.slowestMinutes) : "—"), numeric: true, secondary: true },
    {
      key: "rps", label: "Rooms / shift", value: (r, f) => (r.timedCount > 0 ? f.num(r.roomsPerShift, 1) : "—"), numeric: true,
      render: (r, f) =>
        r.timedCount === 0 ? <span className="text-slate-400">—</span> : (
          <span className={r.roomsPerShift >= 12 ? "text-emerald-700 font-semibold" : "text-amber-700"}>
            {f.num(r.roomsPerShift, 1)}
          </span>
        ),
    },
    { key: "insp", label: "Inspected", value: (r, f) => f.int(r.inspectedCount), numeric: true, secondary: true },
  ],
  tableTitle: "Attendants",
  emptyText: "No housekeeping tasks scheduled in this period.",
}

const loyalty: ReportDefinition<any> = {
  load: async (r) => ({ rows: await getHotelLoyaltyReport(r.from, r.to) }),
  summary: (r, f) => [
    { label: "Members", value: f.int(r.rows.reduce((s: number, x: any) => s + x.memberCount, 0)) },
    { label: "Active", value: f.int(r.rows.reduce((s: number, x: any) => s + x.activeMembers, 0)) },
    { label: "Points earned", value: f.int(r.rows.reduce((s: number, x: any) => s + x.earnedInPeriod, 0)) },
    { label: "Points redeemed", value: f.int(r.rows.reduce((s: number, x: any) => s + x.redeemedInPeriod, 0)) },
  ],
  columns: [
    { key: "t", label: "Tier", value: (r) => r.tierLabel },
    { key: "m", label: "Members", value: (r, f) => f.int(r.memberCount), numeric: true },
    { key: "a", label: "Active", value: (r, f) => f.int(r.activeMembers), numeric: true, secondary: true },
    { key: "bal", label: "Points balance", value: (r, f) => f.int(r.pointsBalance), numeric: true },
    { key: "lt", label: "Lifetime points", value: (r, f) => f.int(r.lifetimePoints), numeric: true, secondary: true },
    { key: "e", label: "Earned", value: (r, f) => f.int(r.earnedInPeriod), numeric: true },
    { key: "rd", label: "Redeemed", value: (r, f) => f.int(r.redeemedInPeriod), numeric: true },
    { key: "sh", label: "Share of members", value: (r, f) => f.pct(r.sharePct), numeric: true, secondary: true },
  ],
  tableTitle: "Tiers",
  tableHint: "Member counts and balances are all-time; earned and redeemed are movements inside the selected period.",
  emptyText: "No loyalty members yet.",
}

// ===========================================================================
// The registry the hotel report router reads.
// ===========================================================================

export const HOTEL_REPORT_REGISTRY: Record<string, ReportDefinition<any, any>> = {
  "performance-kpis": performanceKpis,
  "source-of-business": sourceOfBusiness,
  "booking-pace": bookingPace,
  "room-type-performance": roomTypePerformance,
  "length-of-stay": lengthOfStay,
  "cancellations": cancellations,
  "guest-ledger": guestLedger,
  "ancillary-revenue": ancillaryRevenue,
  "housekeeping-productivity": housekeepingProductivity,
  "loyalty-report": loyalty,
}

/**
 * Performance & KPIs answers with a single object rather than a list, so its
 * table rows are derived here — after the fetch, because formatting needs the
 * currency, which arrives from the hotel profile on its own schedule.
 */
export function deriveHotelMetricRows(slug: string, meta: any, fmt: any): MetricRow[] {
  if (slug !== "performance-kpis" || !meta) return []
  const k = meta as HotelPerformanceKpis
  if (k.daysCounted === 0) return []
  return [
    { metric: "Days closed in period", value: fmt.int(k.daysCounted) },
    { metric: "Available room nights", value: fmt.int(k.availableRoomNights) },
    { metric: "Occupied room nights", value: fmt.int(k.occupiedRoomNights) },
    { metric: "Occupancy", value: fmt.pct(k.occupancyPct) },
    { metric: "Rooms revenue", value: fmt.money(k.roomRevenue) },
    { metric: "Food & beverage revenue", value: fmt.money(k.fnbRevenue) },
    { metric: "Other revenue", value: fmt.money(k.otherRevenue) },
    { metric: "Total revenue", value: fmt.money(k.totalRevenue) },
    { metric: "Operating expenses", value: fmt.money(k.totalExpenses) },
    { metric: "Gross operating profit", value: fmt.money(k.grossOperatingProfit) },
    { metric: "ADR — rooms revenue / occupied rooms", value: fmt.money(k.adr) },
    { metric: "RevPAR — rooms revenue / available rooms", value: fmt.money(k.revpar) },
    { metric: "TRevPAR — total revenue / available rooms", value: fmt.money(k.trevpar) },
    { metric: "GOPPAR — operating profit / available rooms", value: fmt.money(k.goppar) },
    { metric: "No-shows recorded on night audit", value: fmt.int(k.noshowCount) },
  ]
}

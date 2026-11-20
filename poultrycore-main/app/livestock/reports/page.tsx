"use client"

// Reports -- every livestock report in one place, the poultry Reports
// catalogue for livestock. Egg, milk and breeding reports only show when the
// farm keeps an animal that gives them.

import Link from "next/link"
import {
  Baby, BarChart3, Boxes, CalendarDays, CalendarX, ClipboardList, Hourglass, Layers, PackageMinus, PawPrint, Pill,
  Scale, ShoppingBag, Skull, TrendingUp, Truck, Wallet, Waves, Wheat, type LucideIcon,
} from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import { LivestockPage } from "@/components/livestock/livestock-page"

interface Entry { href: string; title: string; text: string; icon: LucideIcon; needs?: "eggs" | "milk" | "breeding" }

const SECTIONS: { title: string; entries: Entry[] }[] = [
  {
    title: "Animals",
    entries: [
      { href: "/livestock/reports/herd", title: "Herd make-up", text: "Animals of each kind now, by sex and age.", icon: PawPrint },
      { href: "/livestock/reports/mortality", title: "Deaths & culls", text: "Deaths by group and what caused them.", icon: Skull },
      { href: "/livestock/reports/breeding", title: "Births & litters", text: "Births, litter sizes and the best mothers.", icon: Baby, needs: "breeding" },
      { href: "/livestock/reports/group-summary", title: "Group summary", text: "One group's whole life on one page.", icon: Layers },
      { href: "/livestock-weigh-ins", title: "Growth", text: "Weights, daily gain and feed per kg gained.", icon: Scale },
      { href: "/livestock-animal-stock", title: "Animal stock", text: "Animals in and out of each group.", icon: Boxes },
    ],
  },
  {
    title: "Production",
    entries: [
      { href: "/livestock/reports/production", title: "Production", text: "Eggs, milk, deaths and feed per group.", icon: ClipboardList },
      { href: "/livestock-trackers", title: "Monthly trackers", text: "A month at a glance: deaths, eggs, milk, feed, head.", icon: CalendarDays },
      { href: "/livestock-missing-records", title: "Missing records", text: "Days a group has no daily record.", icon: CalendarX },
    ],
  },
  {
    title: "Feed & health",
    entries: [
      { href: "/livestock/reports/feed", title: "Feed used", text: "Feed used by item and by group, kg and cost.", icon: Wheat },
      { href: "/livestock/reports/medicine", title: "Medicine used", text: "Medicine and vaccines used, and illnesses seen.", icon: Pill },
      { href: "/livestock-feed-supply", title: "Days of supply", text: "How long each feed will last.", icon: Hourglass },
      { href: "/livestock-losses", title: "Stock losses", text: "Stock lost, spoiled or damaged.", icon: PackageMinus },
    ],
  },
  {
    title: "Sales & money",
    entries: [
      { href: "/livestock/reports/sales", title: "Sales", text: "What sold, at what price, and to whom.", icon: ShoppingBag },
      { href: "/livestock-profit-loss", title: "Profit & loss", text: "Income and costs for the farm or a group.", icon: TrendingUp },
      { href: "/livestock-cash-flow", title: "Cash flow", text: "Money in and out of every account.", icon: Waves },
      { href: "/livestock-customer-balances", title: "Customer balances", text: "Who owes the farm.", icon: Wallet },
      { href: "/livestock-supplier-balances", title: "Supplier balances", text: "What the farm owes.", icon: Wallet },
      { href: "/livestock-deliveries", title: "Driver report", text: "What each driver collected and what is short.", icon: Truck },
    ],
  },
]

export default function LivestockReportsPage() {
  const features = useLivestockFeatures()
  return (
    <LivestockPage title="Reports" description="Every report for the farm." icon={BarChart3}>
      {SECTIONS.map((s) => (
        <section key={s.title} className="space-y-2">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-stone-500">{s.title}</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {s.entries.filter((e) => !e.needs || features[e.needs]).map((e) => (
              <Link key={e.href} href={e.href}>
                <Card className="h-full hover:border-amber-400 transition-colors">
                  <CardContent className="p-4 flex gap-3">
                    <e.icon className="h-5 w-5 text-amber-700 shrink-0 mt-0.5" />
                    <div><div className="font-medium text-stone-900">{e.title}</div><div className="text-sm text-stone-500">{e.text}</div></div>
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        </section>
      ))}
    </LivestockPage>
  )
}

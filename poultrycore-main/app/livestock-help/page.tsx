"use client"

// Livestock help: how the farm's records fit together, and the order to set
// things up -- the poultry help pages for livestock.

import Link from "next/link"
import { HelpCircle } from "lucide-react"
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion"
import { LivestockPage } from "@/components/livestock/livestock-page"

const L = ({ href, children }: { href: string; children: React.ReactNode }) => <Link className="text-amber-800 underline" href={href}>{children}</Link>

const TOPICS: { q: string; a: React.ReactNode }[] = [
  {
    q: "Getting started: what to set up first",
    a: (
      <ol className="list-decimal pl-5 space-y-1">
        <li>Choose the animals you keep on <L href="/livestock-animals-kept">Animals kept</L>. Pages for eggs, milk and breeding only show when you keep an animal that gives them.</li>
        <li>Add your <L href="/livestock-pens">pens</L> (hutches, sties, paddocks…).</li>
        <li>Add a <L href="/livestock-cash-accounts">cash account</L> for each place money is kept (cash box, bank, mobile money).</li>
        <li>Add your feed, medicine and other stock on <L href="/livestock-items">Feed &amp; stock</L>, with what you have now.</li>
        <li>Put your animals in <L href="/livestock-groups">groups</L>. Tag animals you want to follow one by one on the <L href="/livestock-animals">Animal register</L>.</li>
      </ol>
    ),
  },
  {
    q: "Groups and tagged animals",
    a: <p>Every animal belongs to a group, and the group&apos;s count is what the farm has. Tagging is optional: a tagged animal also has its own record (sex, birth date, mother and father, breeding). A group&apos;s count only changes through births, deaths, culls, sales, purchases and moves, so the count history always explains the number.</p>,
  },
  {
    q: "The daily record",
    a: <p>Fill one <L href="/livestock-production-records">daily record</L> per group per day: deaths and their cause, eggs or milk collected, and the feed and medicine given. Feed and medicine come out of stock when you save, and eggs and milk go into stock so you can sell them. <L href="/livestock-missing-records">Missing records</L> shows the days you skipped.</p>,
  },
  {
    q: "Breeding and births",
    a: <p>Record matings, pregnancy checks, births and weaning on <L href="/livestock-breeding">Breeding &amp; births</L>. A birth adds the young born alive to the group you choose. The due date comes from how long each kind of animal carries its young.</p>,
  },
  {
    q: "Buying, selling and who owes what",
    a: <p>A <L href="/livestock-purchases">purchase</L> adds stock or animals and records what you owe the supplier; pay it now or later. A <L href="/livestock-sales">sale</L> takes animals or produce out and records what the customer owes. Payments are matched to the oldest unpaid sale or bill first. An animal still under a medicine&apos;s withdrawal period cannot be sold without saying why.</p>,
  },
  {
    q: "Money",
    a: <p>Every amount in or out goes through a cash account, so each account&apos;s balance is always the sum of what happened to it. Use <L href="/livestock-cash-reconciliation">Count the money</L> to check the cash box, <L href="/livestock-cash-transfers">Move money</L> between accounts, and <L href="/livestock-profit-loss">Profit &amp; loss</L> to see how the farm, or one group, is doing.</p>,
  },
  {
    q: "Closing the day",
    a: <p>At the end of each day, check it on <L href="/livestock-daily-closing">Daily closing</L> and close it. A closed day cannot be changed. If something has to be fixed, reopen the day and say why; both are kept.</p>,
  },
  {
    q: "Mistakes",
    a: <p>Nothing is deleted. A wrong entry is reversed, which puts the animals, stock and money back as they were and keeps a record of both. Then enter it again correctly.</p>,
  },
]

export default function LivestockHelpPage() {
  return (
    <LivestockPage title="Help" description="How the livestock farm records work." icon={HelpCircle}>
      <Accordion type="single" collapsible className="rounded-md border bg-white px-4">
        {TOPICS.map((t) => (
          <AccordionItem key={t.q} value={t.q}>
            <AccordionTrigger className="text-left">{t.q}</AccordionTrigger>
            <AccordionContent className="text-sm text-stone-700 leading-relaxed">{t.a}</AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
      <p className="text-sm text-stone-500">More help, and the general guides, are in the <L href="/help">Help Center</L>.</p>
    </LivestockPage>
  )
}

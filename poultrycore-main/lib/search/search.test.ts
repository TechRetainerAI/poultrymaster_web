import { describe, expect, it } from "vitest"
import { editDistance, scoreText } from "./fuzzy"
import { flattenNavConfig, parseQuery, rankPages, type SearchPage } from "./page-index"
import { rankRecords, type SearchRecord } from "./records"

const page = (title: string, href: string, group = "Menu", keywords: string[] = []): SearchPage =>
  ({ title, href, group, keywords })

describe("scoreText", () => {
  it("ranks exact over prefix over substring", () => {
    expect(scoreText("sales", "Sales")).toBe(100)
    expect(scoreText("sal", "Sales")).toBe(90)
    expect(scoreText("flow", "Cash Flow")).toBeGreaterThanOrEqual(70)
  })

  it("matches word prefixes in any order", () => {
    expect(scoreText("cust bal", "Customer Balances")).toBe(80)
    expect(scoreText("bal cust", "Customer Balances")).toBe(80)
  })

  it("matches acronyms, skipping & / and", () => {
    expect(scoreText("pl", "Profit & Loss")).toBe(65)
    expect(scoreText("cf", "Cash Flow")).toBe(65)
  })

  it("tolerates typos and transpositions", () => {
    expect(scoreText("expences", "Expenses")).toBe(55)
    expect(scoreText("suplier", "Suppliers")).toBe(55)
    expect(scoreText("slaes", "Sales")).toBe(55)
    expect(editDistance("slaes", "sales")).toBe(1)
  })

  it("does not invent matches", () => {
    expect(scoreText("xyz", "Sales")).toBe(0)
    expect(scoreText("egg", "Cash Flow")).toBe(0)
  })
})

describe("parseQuery", () => {
  it("strips navigation and create verbs", () => {
    expect(parseQuery("go to cash flow")).toEqual({ text: "cash flow", create: false })
    expect(parseQuery("New sale")).toEqual({ text: "sale", create: true })
    expect(parseQuery("record an expense")).toEqual({ text: "expense", create: true })
  })
})

describe("flattenNavConfig", () => {
  const Icon = (() => null) as never
  const config = {
    quickLinks: { label: "Quick Links", items: [{ href: "/sales", label: "Sales", icon: Icon }] },
    salesMoney: [
      { key: "sales", label: "Sales", items: [
        { id: "s", title: "Sales", href: "/sales", icon: Icon },
        { id: "cf", title: "Cash Flow", href: "/cash-flow", icon: Icon, visible: false },
      ] },
    ],
    system: [{ key: "sys", label: "System", items: [{ id: "out", title: "Log out", icon: Icon, onClick: () => {} }] }],
  }

  it("keeps the canonical group, drops hidden and action rows", () => {
    const pages = flattenNavConfig(config)
    expect(pages.map((p) => p.href)).toEqual(["/sales"])
    expect(pages[0].group).toBe("Sales")
  })

  it("adds synonyms to pages that exist, never new pages", () => {
    const pages = flattenNavConfig(config)
    expect(pages[0].keywords).toContain("revenue")
    expect(pages.find((p) => p.href === "/cash-flow")).toBeUndefined()
  })
})

describe("rankPages", () => {
  const pages = flattenNavConfig({
    a: [{ key: "m", label: "Money", items: [
      { id: "1", title: "Customer Balances", href: "/customer-balances", icon: null as never },
      { id: "2", title: "Customer Payments", href: "/poultry-payments", icon: null as never },
      { id: "3", title: "Profit & Loss", href: "/poultry-profit-loss", icon: null as never },
      { id: "4", title: "Sales", href: "/sales", icon: null as never },
      { id: "5", title: "Account", href: "/profile", icon: null as never },
      { id: "6", title: "Cash Account", href: "/poultry-cash-accounts", icon: null as never },
    ] }],
  })

  it("answers questions through synonyms", () => {
    expect(rankPages("who owes", pages)[0].href).toBe("/customer-balances")
    expect(rankPages("debtors", pages)[0].href).toBe("/customer-balances")
    expect(rankPages("income statement", pages)[0].href).toBe("/poultry-profit-loss")
  })

  it("handles intents", () => {
    expect(rankPages("new sale", pages)[0].href).toBe("/sales")
  })

  it("an exact-title synonym does not leak into a longer title", () => {
    const hits = rankPages("password", pages).map((p) => p.href)
    expect(hits).toEqual(["/profile"])
  })

  it("lets a recent page win a tie", () => {
    const tie = [page("Expenses", "/expenses"), page("Expenses", "/water-expenses")]
    expect(rankPages("expenses", tie, ["/water-expenses"])[0].href).toBe("/water-expenses")
  })
})

describe("rankRecords", () => {
  const recs: SearchRecord[] = [
    { kind: "customer", id: "1", title: "Kofi Mensah", phones: ["+233 24 412 3456"], href: "/customers/1" },
    { kind: "customer", id: "2", title: "Ama Boateng", phones: ["0201112222"], href: "/customers/2" },
    { kind: "flock", id: "3", title: "Layers Pen A", href: "/flocks/3", inactive: true },
  ]

  it("finds names, with typos", () => {
    expect(rankRecords("kofi", recs)[0].id).toBe("1")
    expect(rankRecords("mensha", recs)[0].id).toBe("1")
  })

  it("finds phone numbers across a country code", () => {
    expect(rankRecords("0244123", recs).map((r) => r.id)).toEqual(["1"])
    expect(rankRecords("020 111", recs).map((r) => r.id)).toEqual(["2"])
  })

  it("ignores loose noise", () => {
    expect(rankRecords("zz", recs)).toEqual([])
  })
})

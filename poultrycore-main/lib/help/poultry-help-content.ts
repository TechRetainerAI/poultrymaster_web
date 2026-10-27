/**
 * Poultry Help Center content: questions, troubleshooting and glossary.
 *
 * Every answer was checked against the UI on 2026-10-26 -- button labels are
 * quoted as they appear. When a screen changes, change its answer here: a help
 * page that describes a button that no longer exists is worse than none.
 *
 * Ids are the #anchors people share (/help#reverse-sale). Never rename one;
 * add a new entry instead.
 */

import {
  Activity, BarChart3, Bird, CalendarCheck, DollarSign, Egg, FileText, Package, Settings, ShoppingCart, Users,
  type LucideIcon,
} from "lucide-react"
import type { HelpEntry } from "./help-types"

// --------------------------------------------------------------- feature grid

export interface FeatureGuide {
  icon: LucideIcon
  title: string
  description: string
  path: string
  /** The disc behind the icon. Follows the subject's FAQ category colour. */
  tint: string
}

export const FEATURE_GUIDES: FeatureGuide[] = [
  { icon: Bird, title: "Flocks", description: "Flocks, bird purchases and closeout", path: "/flocks", tint: "bg-amber-100 text-amber-700" },
  { icon: Egg, title: "Production", description: "Log daily eggs, deaths and feed", path: "/production-records", tint: "bg-sky-100 text-sky-700" },
  { icon: Package, title: "Feed Usage", description: "Record and monitor feed consumption", path: "/feed-usage", tint: "bg-sky-100 text-sky-700" },
  { icon: ShoppingCart, title: "Sales", description: "Record, reverse and correct sales", path: "/sales", tint: "bg-violet-100 text-violet-700" },
  { icon: Users, title: "Customer Balances", description: "Who owes you, and how much", path: "/customer-balances", tint: "bg-violet-100 text-violet-700" },
  { icon: DollarSign, title: "Expenses", description: "Costs, bills and paying them later", path: "/expenses", tint: "bg-rose-100 text-rose-700" },
  { icon: CalendarCheck, title: "Daily Closing", description: "Check the day, then close it", path: "/poultry-daily-closing", tint: "bg-emerald-100 text-emerald-700" },
  { icon: BarChart3, title: "Profit & Loss", description: "Revenue, costs and net profit", path: "/poultry-profit-loss", tint: "bg-indigo-100 text-indigo-700" },
  { icon: Activity, title: "Health Records", description: "Vaccinations and treatments", path: "/health", tint: "bg-amber-100 text-amber-700" },
  { icon: FileText, title: "Inventory", description: "Stock of feed, medication and supplies", path: "/poultry-inventory", tint: "bg-rose-100 text-rose-700" },
  { icon: Settings, title: "Company Setup", description: "Farm details, currency, time zone", path: "/poultry-company-setup", tint: "bg-slate-200 text-slate-700" },
]

// --------------------------------------------------------------- colours

/**
 * One colour per category, so the same subject is the same colour wherever it
 * appears -- the filter chip, the badge on an answer, and the rail down the
 * left of its card.
 */
const CATEGORY_TONES: Record<string, { chip: string; chipOn: string; rail: string; badge: string }> = {
  "Getting Started":       { chip: "hover:bg-emerald-50", chipOn: "bg-emerald-600 hover:bg-emerald-700", rail: "border-l-emerald-400", badge: "border-emerald-200 bg-emerald-50 text-emerald-700" },
  "Flocks & Birds":        { chip: "hover:bg-amber-50",   chipOn: "bg-amber-600 hover:bg-amber-700",     rail: "border-l-amber-400",   badge: "border-amber-200 bg-amber-50 text-amber-700" },
  "Production & Eggs":     { chip: "hover:bg-sky-50",     chipOn: "bg-sky-600 hover:bg-sky-700",         rail: "border-l-sky-400",     badge: "border-sky-200 bg-sky-50 text-sky-700" },
  "Sales & Customers":     { chip: "hover:bg-violet-50",  chipOn: "bg-violet-600 hover:bg-violet-700",   rail: "border-l-violet-400",  badge: "border-violet-200 bg-violet-50 text-violet-700" },
  "Expenses & Purchases":  { chip: "hover:bg-rose-50",    chipOn: "bg-rose-600 hover:bg-rose-700",       rail: "border-l-rose-400",    badge: "border-rose-200 bg-rose-50 text-rose-700" },
  "Money & Reports":       { chip: "hover:bg-indigo-50",  chipOn: "bg-indigo-600 hover:bg-indigo-700",   rail: "border-l-indigo-400",  badge: "border-indigo-200 bg-indigo-50 text-indigo-700" },
  "Account & Access":      { chip: "hover:bg-slate-100",  chipOn: "bg-slate-700 hover:bg-slate-800",     rail: "border-l-slate-400",   badge: "border-slate-200 bg-slate-100 text-slate-700" },
}

const FALLBACK_TONE = { chip: "hover:bg-slate-100", chipOn: "bg-indigo-600 hover:bg-indigo-700", rail: "border-l-slate-300", badge: "border-slate-200 bg-slate-50 text-slate-600" }

export const toneFor = (category: string) => CATEGORY_TONES[category] ?? FALLBACK_TONE

// --------------------------------------------------------------- entries

const faq = (e: Omit<HelpEntry, "kind">): HelpEntry => ({ ...e, kind: "faq" })
const fix = (e: Omit<HelpEntry, "kind">): HelpEntry => ({ ...e, kind: "fix" })
const term = (e: Omit<HelpEntry, "kind">): HelpEntry => ({ ...e, kind: "term" })

export const HELP_ENTRIES: HelpEntry[] = [
  // ============================================================ Questions
  faq({
    id: "set-up-farm", category: "Getting Started",
    title: "How do I set up my farm?",
    keywords: ["start", "onboarding", "first time", "configure", "settings"],
    body: `Setup is done by the owner or an admin; staff cannot open these pages.

1. Company Setup: farm name, address, currency and time zone.
2. Farm Setup: one page with tabs for Products, Customers, Suppliers, Houses, Drivers, Vehicles, Routes and Employees.
3. Egg Sorting Settings: eggs per crate, egg sizes and their prices.
4. Financial Settings: whether feed and medication are expensed when bought or when used.

If the farm already has birds, run Initial Farm Setup (under Tools) once, so the birds you have today go in as opening positions.`,
    links: [
      { label: "Company Setup", href: "/poultry-company-setup" },
      { label: "Farm Setup", href: "/poultry-setup" },
      { label: "Initial Farm Setup", href: "/poultry-farm-setup" },
    ],
  }),
  faq({
    id: "daily-routine", category: "Getting Started",
    title: "What should I record every day?",
    keywords: ["routine", "workflow", "checklist", "daily work", "order"],
    body: `In the order the day happens:

1. Production Records: eggs per pick, broken eggs, deaths, feed.
2. Egg sorting: sort the day's eggs into sizes.
3. Sales and customer payments.
4. Expenses, and any purchases received.
5. Daily Closing: fix what it flags, then close the day.

Farm Alerts (the bell in the header) tells you what is still missing.`,
    links: [
      { label: "Production Records", href: "/production-records" },
      { label: "Daily Closing", href: "/poultry-daily-closing" },
      { label: "Farm Alerts", href: "/poultry-alerts" },
    ],
  }),
  faq({
    id: "find-anything", category: "Getting Started",
    title: "How do I find a page or a customer quickly?",
    keywords: ["search bar", "shortcut", "ctrl k", "navigate"],
    body: `Use the search bar at the top of every page, or press Ctrl+K. Type a page ("cash flow"), a question ("who owes"), something to do ("new sale"), a customer's name or part of their phone number. It forgives spelling mistakes, and only offers pages you are allowed to open.`,
  }),
  faq({
    id: "add-flock", category: "Flocks & Birds",
    title: "How do I add a flock?",
    keywords: ["new flock", "create flock", "birds", "layers", "broilers"],
    body: `Birds arrive as a batch, then go into flocks.

1. Flock Purchases (Batches): "Add Flock Batch" for the birds you bought, with the supplier, number of birds and cost per chick.
2. Flocks: "Add Flock" (or "Add Multiple Flocks"), assign it to the batch, give it a name, start date, number of birds and house, then "Create Flock".`,
    links: [
      { label: "Flock Purchases", href: "/flock-batch" },
      { label: "Flocks", href: "/flocks" },
    ],
  }),
  faq({
    id: "close-flock", category: "Flocks & Birds",
    title: "How do I end a flock when the birds are sold or culled?",
    keywords: ["closeout", "deactivate", "end of lay", "depopulate", "finish flock"],
    body: `Use Flock Closeout (under Tools). Pick the flock under "Ready to close", say where the birds went (Sold, Culled or Transferred off the farm), and finish with "Close flock & record sales". Sales of the birds are recorded for you.

A closed flock can be reopened from its Lifetime summary if it was closed by mistake.

The "Active Flock" switch on the Flocks page only hides a flock; it records nothing about the birds. Use Closeout to actually end one.`,
    links: [{ label: "Flock Closeout", href: "/flock-closeout" }],
  }),
  faq({
    id: "correct-bird-count", category: "Flocks & Birds",
    title: "My bird count is wrong. How do I correct it?",
    keywords: ["bird adjustment", "fix birds", "birds left", "count", "mortality"],
    body: `Go to Stock movements and choose "New movement", then Birds. Pick the batch, then the flock (or "Not placed in a flock" for birds still in the batch). Enter the change in whole birds, a reason and the date it applies from. The dialog shows the count now and after the change.

For a flock, the change is applied to its latest production record. There is no undo: post the opposite movement.`,
    links: [{ label: "Stock movements", href: "/poultry-stock" }],
  }),
  faq({
    id: "log-production", category: "Production & Eggs",
    title: "How do I log daily production?",
    keywords: ["eggs collected", "picks", "mortality", "deaths", "record production"],
    body: `On Production Records choose "Log Production". Pick the flock and date, then enter crates and loose eggs for each pick, the broken, meaty, soft and lost eggs, the number of birds and deaths, and the feed used. The summary shows net sellable eggs and the day's production cost.

A 4th pick appears only if it is turned on under Egg Pick Times.`,
    links: [{ label: "Production Records", href: "/production-records" }],
  }),
  faq({
    id: "eggs-per-crate", category: "Production & Eggs",
    title: "How are eggs counted in crates?",
    keywords: ["crate size", "30 eggs", "tray", "pieces", "conversion"],
    body: `Total eggs = crates × eggs per crate + loose eggs. Eggs per crate is set by an admin on Egg Sorting Settings (default 30).

Company Setup has its own "eggs per crate" field, but it is used only for vehicle loading and driver returns.`,
    links: [{ label: "Egg Sorting Settings", href: "/poultry-egg-sorting-settings" }],
  }),
  faq({
    id: "sort-eggs", category: "Production & Eggs",
    title: "How does egg sorting work?",
    keywords: ["grading", "sizes", "unsorted eggs", "large medium small"],
    body: `Eggs from production start as Unsorted. On Egg sorting, choose "Sort all available eggs" or sort a single pick, and split them into your sizes. A sorting can be reversed: the eggs go back to Unsorted (reverse any sales of those sized eggs first).

An admin decides on Egg Sorting Settings whether unsorted eggs only warn on Daily Closing, block it, or are ignored.`,
    links: [{ label: "Egg sorting", href: "/poultry-egg-sorting" }],
  }),
  faq({
    id: "record-sale", category: "Sales & Customers",
    title: "How do I record a sale?",
    keywords: ["new sale", "sell eggs", "invoice", "part payment", "credit sale"],
    body: `On Sales choose "Add Sale". Pick the customer, date and products (crates and loose eggs, or a quantity) with their prices. Then choose how it was paid:

- Paid now: the full amount, with the payment method and the cash account it went into.
- Part payment: what was paid now; the rest is owed.
- Pay later: all of it is owed.

"Use customer credit" applies money the customer already has with you.`,
    links: [{ label: "Sales", href: "/sales" }],
  }),
  faq({
    id: "reverse-sale", category: "Sales & Customers",
    title: "I made a mistake on a sale. How do I fix it?",
    keywords: ["edit sale", "delete sale", "undo sale", "cancel sale", "wrong price", "duplicate", "correct sale"],
    body: `A sale cannot be edited or deleted once saved. Open it and choose:

- "Correct sale": reverses it and opens a new sale already filled in, for you to fix and save.
- "Reverse sale": undoes it completely.

Either way you pick a reason (Wrong customer, Wrong quantity, Wrong price, Duplicate sale, Wrong product, Entered by mistake, or Other with a note). The reversed sale stays in the list, struck through, so the history is never lost. Its revenue, debt and stock are undone, and money already received is taken back out of cash or kept as the customer's credit.`,
    links: [{ label: "Sales", href: "/sales" }],
  }),
  faq({
    id: "customer-payment", category: "Sales & Customers",
    title: "A customer paid for several sales at once. How do I record it?",
    keywords: ["receive payment", "collection", "pay debt", "bulk payment", "overpayment", "advance"],
    body: `On Customer Payments choose "Record customer payment". Pick the customer, enter the amount and apply it to their open sales. Anything not applied is kept as their credit, which can be used on a later sale or refunded from Customer Credits.`,
    links: [
      { label: "Customer Payments", href: "/poultry-payments" },
      { label: "Customer Credits", href: "/customer-credits" },
    ],
  }),
  faq({
    id: "old-debt", category: "Sales & Customers",
    title: "How do I enter what customers owed before we started using the app?",
    keywords: ["opening balance", "old debt", "previous debt", "historical", "migration"],
    body: `On Customer Balances, an owner or admin uses "Record customer debt" to enter money owed without a sale. When the customer pays, use "Receive payment" on that row.

Money the customer had with you before (a deposit, an advance) goes in as a credit: Customer Credits, "Add credit".`,
    links: [
      { label: "Customer Balances", href: "/customer-balances" },
      { label: "Customer Credits", href: "/customer-credits" },
    ],
  }),
  faq({
    id: "add-expense", category: "Expenses & Purchases",
    title: "How do I record an expense, or pay it later?",
    keywords: ["new expense", "bill", "cost", "unpaid", "due date"],
    body: `On Expenses choose "Add Expense": category, amount, date, flock, who it was paid to, and whether it is paid. An unpaid expense gets a due date.

To pay it later, use "Record a payment against this expense" on its row. "Repeat previous" copies the last expense so a regular cost takes seconds.

Expenses can be edited or deleted; deleting is permanent.`,
    links: [{ label: "Expenses", href: "/expenses" }],
  }),
  faq({
    id: "recurring-expense", category: "Expenses & Purchases",
    title: "Can rent, salaries or other regular costs be entered automatically?",
    keywords: ["recurring", "monthly", "repeat", "subscription", "standing"],
    body: `Yes. On Recurring Expenses choose "New recurring expense" and set how often it repeats. When one falls due it appears under "To review", where you Post or Skip it. A template can also be set to post automatically.`,
    links: [{ label: "Recurring Expenses", href: "/recurring-expenses" }],
  }),
  faq({
    id: "which-purchase", category: "Expenses & Purchases",
    title: "Supply Purchase, Receive Purchase or Supplier Payment: which do I use?",
    keywords: ["buy feed", "invoice", "supplier", "goods received", "restock"],
    body: `- Supply Purchases ("Record purchase"): buying one item.
- Receive Purchase: one supplier invoice with several items and extra costs (transport, offloading), paid in full, in part or later. A receipt can be reversed but not edited.
- Supplier Payments ("Record supplier payment"): paying a supplier money you already owe them. Supplier Balances shows what is still owed.`,
    links: [
      { label: "Supply Purchases", href: "/poultry-supply-purchases" },
      { label: "Receive Purchase", href: "/poultry-purchase-receipts" },
      { label: "Supplier Balances", href: "/supplier-balances" },
    ],
  }),
  faq({
    id: "internal-use", category: "Expenses & Purchases",
    title: "How do I record eggs or stock the farm used itself?",
    keywords: ["staff eggs", "donation", "own use", "gift", "samples", "consumed"],
    body: `Use Internal Use ("Record internal use") for stock used rather than sold: staff allowance, farm use, donations, testing. It reduces stock and books the cost as an expense, with no sale and no money moving. A posted entry can be reversed with a reason.`,
    links: [{ label: "Internal Use", href: "/poultry-internal-use" }],
  }),
  faq({
    id: "daily-closing", category: "Money & Reports",
    title: "What is Daily Closing and who can close a day?",
    keywords: ["end of day", "close day", "approve", "reopen", "submit"],
    body: `Daily Closing checks one business day: production, sales, expenses, cash, egg sorting and feed, grouped as Must fix, Warnings and Complete.

Someone with the approve right closes it ("Close Business Day"). Anyone else uses "Submit for approval", and the approver closes or rejects it. A closed day keeps a snapshot of its figures; "Reopen Day" needs a reason, and the history shows what changed.`,
    links: [{ label: "Daily Closing", href: "/poultry-daily-closing" }],
  }),
  faq({
    id: "reports-exports", category: "Money & Reports",
    title: "Which reports are there, and can I export them?",
    keywords: ["download", "pdf", "csv", "excel", "email report", "print"],
    body: `Reports holds the money, production, feed, birds and health reports. Most of them, and Profit & Loss, export to CSV or PDF, or email a PDF.

- Sales: Export PDF and Email Report.
- Expenses: PDF and CSV.
- Production Records: CSV and PDF.
- Financial Activity: CSV.`,
    links: [
      { label: "Reports", href: "/reports" },
      { label: "Profit & Loss", href: "/poultry-profit-loss" },
    ],
  }),
  faq({
    id: "switch-company", category: "Account & Access",
    title: "I have more than one farm. How do I switch?",
    keywords: ["company switcher", "another farm", "multiple companies", "business office"],
    body: `Use the company switcher in the header ("Switch company") and pick the company; you land on its dashboard. Only the account owner can create a new company. The briefcase icon opens the Business Office, which sits above all your companies.`,
  }),
  faq({
    id: "add-user", category: "Account & Access",
    title: "How do I give a staff member their own login?",
    keywords: ["employee", "new user", "permissions", "access", "staff login", "admin"],
    body: `On Users & Permissions choose "Add Employee", fill in their name, phone, username, email and a password, and pick the company. Switch on "Create as administrator" only for someone who should manage setup.

Staff start with access to nothing. Use "Staff Page Access" to switch on exactly the pages they need.`,
    links: [{ label: "Users & Permissions", href: "/employees" }],
  }),
  faq({
    id: "password", category: "Account & Access",
    title: "How do I change my password?",
    keywords: ["reset password", "forgot password", "login", "security"],
    body: `There is no change-password screen inside the app yet. Log out, choose "Forgot password" on the login screen, and follow the reset link sent to your email.

Your Profile page (the user icon, top right) has your name, email, phone and two-factor authentication.`,
    links: [{ label: "Profile", href: "/profile" }],
  }),
  faq({
    id: "admin-vs-staff", category: "Account & Access",
    title: "What's the difference between an admin and staff?",
    keywords: ["roles", "owner", "permissions", "rights"],
    body: `The owner and admins can do everything, including Setup: company and financial settings, products, customers, suppliers, houses, drivers, routes, egg sorting settings.

Staff see only the pages switched on for them in Staff Page Access, and can never open Setup pages.`,
  }),

  // ============================================================ Troubleshooting
  fix({
    id: "cant-see-page", category: "Account & Access",
    title: "I can't see a page, or it sends me back to the dashboard",
    keywords: ["missing menu", "no access", "permission denied", "redirect", "hidden"],
    body: `1. Check you are in the right company: the switcher in the header shows which one is active.
2. Setup pages are for the owner and admins only. Staff who open one are sent to their dashboard.
3. For staff, an admin must switch the page on in Users & Permissions, "Staff Page Access".
4. After your access changes, log out and back in.`,
    links: [{ label: "Users & Permissions", href: "/employees" }],
  }),
  fix({
    id: "cash-vs-profit", category: "Money & Reports",
    title: "My cash doesn't match my profit",
    keywords: ["difference", "money", "net profit", "cash flow", "why"],
    body: `That is normal. Cash Flow counts money when it moves; Profit & Loss counts income when it is earned and costs when they are incurred. Common reasons they differ:

- Sales on credit: profit now, cash when the customer pays.
- Loans and owner money: cash, but not profit.
- Capital assets: cash out now, profit reduced slowly through depreciation.
- Feed set to "expense when consumed": cash out when bought, cost when used.

Financial Activity lists every item and shows its effect on each, so the gap is explained line by line.`,
    links: [
      { label: "Financial Activity", href: "/poultry-financial-activity" },
      { label: "Cash Flow", href: "/cash-flow" },
      { label: "Profit & Loss", href: "/poultry-profit-loss" },
    ],
  }),
  fix({
    id: "feed-not-in-expenses", category: "Expenses & Purchases",
    title: "I bought feed but it isn't on Expenses or Profit & Loss",
    keywords: ["deferred", "awaiting", "missing expense", "medication", "purchase not showing"],
    body: `Your farm (or that item) is set to expense feed when it is used, not when it is bought. The purchase waits on Deferred inventory cost as "Awaiting Profit & Loss", and its cost reaches the P&L as production records use it.

This is set before buying, in Financial Settings or on the item, never per purchase, and a change only affects new purchases.`,
    links: [
      { label: "Deferred inventory cost", href: "/poultry-deferred-costs" },
      { label: "Financial Settings", href: "/poultry-financial-settings" },
    ],
  }),
  fix({
    id: "closing-blocked", category: "Money & Reports",
    title: "Daily Closing won't let me close the day",
    keywords: ["blocked", "must fix", "cannot close", "unsorted eggs"],
    body: `1. Look at the "Must fix" group: each item says what is missing and links to where to fix it.
2. Unsorted eggs block the close when an admin set egg sorting to "Blocking". Sort them on Egg sorting.
3. If you don't have the approve right, you can only "Submit for approval".
4. A day that is already closed must be reopened (with a reason) before it can change.`,
    links: [
      { label: "Daily Closing", href: "/poultry-daily-closing" },
      { label: "Egg sorting", href: "/poultry-egg-sorting" },
    ],
  }),
  fix({
    id: "balance-wrong", category: "Sales & Customers",
    title: "A customer's balance looks wrong",
    keywords: ["owes", "debt", "credit", "statement", "outstanding"],
    body: `1. Open their statement on Customer Balances: every sale, payment and reversal that makes up the balance is listed.
2. Credit they hold is shown beside the balance, not subtracted from it. Apply it to a sale ("Use customer credit") to reduce what they owe.
3. A payment recorded without applying it to sales stays as credit until applied.
4. Reversed sales are struck through and no longer count.`,
    links: [{ label: "Customer Balances", href: "/customer-balances" }],
  }),
  fix({
    id: "eggs-dont-add-up", category: "Production & Eggs",
    title: "Egg totals don't add up",
    keywords: ["egg count", "crates wrong", "egg tracker", "stock eggs"],
    body: `1. Check eggs per crate on Egg Sorting Settings. It drives every crate figure, and the field in Company Setup does not.
2. Broken, meaty, soft and lost eggs are taken off before net sellable.
3. Egg tracker shows every egg movement (production, sorting, sales, internal use) to find where the difference came in.`,
    links: [
      { label: "Egg tracker", href: "/egg-tracker" },
      { label: "Egg Sorting Settings", href: "/poultry-egg-sorting-settings" },
    ],
  }),
  fix({
    id: "logged-out", category: "Account & Access",
    title: "I keep getting logged out",
    keywords: ["session expired", "login again", "signed out"],
    body: `Your session expired, so the app sends you back to log in. Log in again; nothing saved is lost, but a form you had not saved yet must be re-entered. If it happens within minutes every time, contact support and say roughly how long you were logged in.`,
  }),
  fix({
    id: "page-wont-load", category: "Account & Access",
    title: "A page won't load or shows an error",
    keywords: ["error", "blank", "not loading", "stuck", "crash"],
    body: `1. Refresh the page (Ctrl+R).
2. Check your internet connection.
3. Log out and back in.
4. Still broken: contact support, and say which page it was and what you clicked just before.`,
  }),

  // ============================================================ Glossary
  term({
    id: "term-reversal", category: "Sales & Customers", title: "Reversal",
    body: "Undoing a saved record without deleting it. The original stays in the history, marked Reversed, and its effect on stock, money and balances is cancelled.",
    keywords: ["reverse", "undo"],
  }),
  term({
    id: "term-credit", category: "Sales & Customers", title: "Customer credit",
    body: "Money a customer has with you that is not yet used on a sale: an overpayment, an advance or a credit note. It can be applied to a later sale or refunded.",
    links: [{ label: "Customer Credits", href: "/customer-credits" }],
  }),
  term({
    id: "term-balance", category: "Sales & Customers", title: "Customer balance",
    body: "What a customer still owes on their sales and recorded debts. Credit they hold is shown beside it, not subtracted.",
    links: [{ label: "Customer Balances", href: "/customer-balances" }],
  }),
  term({
    id: "term-deferred", category: "Money & Reports", title: "Deferred inventory cost",
    body: "The cost of feed or medication you have bought but not yet used. It is held back (\"Awaiting Profit & Loss\") and becomes an expense as it is used.",
    keywords: ["awaiting profit and loss", "expense when consumed"],
    links: [{ label: "Deferred inventory cost", href: "/poultry-deferred-costs" }],
  }),
  term({
    id: "term-eggs-per-crate", category: "Production & Eggs", title: "Eggs per crate",
    body: "How many eggs make one crate on this farm (default 30). Set on Egg Sorting Settings; it converts crates to eggs everywhere.",
    links: [{ label: "Egg Sorting Settings", href: "/poultry-egg-sorting-settings" }],
  }),
  term({
    id: "term-net-sellable", category: "Production & Eggs", title: "Net sellable eggs",
    body: "Eggs collected minus broken, meaty, soft and lost eggs.",
  }),
  term({
    id: "term-unsorted", category: "Production & Eggs", title: "Unsorted eggs",
    body: "Eggs collected but not yet sorted into sizes. They can be sold at the unsorted price, or sorted on Egg sorting.",
  }),
  term({
    id: "term-pick", category: "Production & Eggs", title: "Pick",
    body: "One egg collection round in the day (1st pick at 9:00 AM, and so on). The times are set on Egg Pick Times.",
  }),
  term({
    id: "term-batch", category: "Flocks & Birds", title: "Flock batch",
    body: "One purchase of birds, with its supplier and cost. A batch's birds are placed into one or more flocks.",
    links: [{ label: "Flock Purchases", href: "/flock-batch" }],
  }),
  term({
    id: "term-closeout", category: "Flocks & Birds", title: "Flock closeout",
    body: "Ending a flock: recording where its birds went (sold, culled or transferred) and closing it. It can be reopened.",
    links: [{ label: "Flock Closeout", href: "/flock-closeout" }],
  }),
  term({
    id: "term-mortality", category: "Flocks & Birds", title: "Mortality",
    body: "Birds that died, entered as Deaths on a production record. Birds left = number of birds minus deaths.",
  }),
  term({
    id: "term-internal-use", category: "Expenses & Purchases", title: "Internal use",
    body: "Stock the farm uses itself rather than sells. It reduces stock and is booked as a non-cash expense.",
  }),
  term({
    id: "term-non-cash", category: "Money & Reports", title: "Non-cash expense",
    body: "A cost that reduces profit without money leaving an account at that moment, such as internal use, depreciation or deferred feed being used.",
  }),
  term({
    id: "term-depreciation", category: "Money & Reports", title: "Depreciation",
    body: "Spreading the cost of a capital asset (a pen, a vehicle, equipment) over its useful life, so profit is reduced a little each period instead of all at once.",
    links: [{ label: "Capital Investments", href: "/poultry-assets" }],
  }),
  term({
    id: "term-gross-profit", category: "Money & Reports", title: "Gross profit",
    body: "Revenue minus direct production costs. Operating expenses come off next to give operating profit, then depreciation and financing to give net profit.",
  }),
  term({
    id: "term-owner-money", category: "Money & Reports", title: "Owner money",
    body: "Money the owner puts into or takes out of the business. It moves cash but is never profit or expense.",
    links: [{ label: "Owner Money", href: "/poultry-owner-money" }],
  }),
  term({
    id: "term-reconciliation", category: "Money & Reports", title: "Reconciliation",
    body: "Comparing what the app says is in a cash account with what is actually there, and recording the difference.",
    links: [{ label: "Reconciliation", href: "/poultry-cash-reconciliation" }],
  }),
  term({
    id: "term-business-date", category: "Money & Reports", title: "Business date",
    body: "The day a record belongs to, which can be earlier than the day it was entered. Reports and Daily Closing use the business date; the entry time is shown beside it.",
  }),
  term({
    id: "term-staff-access", category: "Account & Access", title: "Staff Page Access",
    body: "The list of switches an admin uses to choose which pages a staff member can open. Staff start with none.",
    links: [{ label: "Users & Permissions", href: "/employees" }],
  }),
]

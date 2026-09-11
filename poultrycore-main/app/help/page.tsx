"use client"

import { useState, useEffect } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import {
  HelpCircle,
  Search,
  Bird,
  Egg,
  Package,
  DollarSign,
  Users,
  BarChart3,
  Settings,
  ShoppingCart,
  FileText,
  Activity,
  ChevronDown,
  ChevronUp,
  BookOpen,
  Mail,
  Phone,
} from "lucide-react"

interface FAQItem {
  question: string
  answer: string
  category: string
}

const faqData: FAQItem[] = [
  {
    category: "Getting Started",
    question: "How do I set up my farm?",
    answer:
      "Go to Settings from the sidebar menu. Enter your farm name, location, and preferred currency. Click 'Edit Settings' to modify and 'Save Changes' to confirm.",
  },
  {
    category: "Getting Started",
    question: "How do I add employees/staff?",
    answer:
      "Navigate to the Employees page from the sidebar. Click 'Add Employee' and fill in their details including name, email, phone, and role. Staff members can be given limited access compared to admins.",
  },
  {
    category: "Flocks",
    question: "How do I create a new flock?",
    answer:
      "Go to Flocks from the sidebar and click 'Add Flock'. Enter the flock name, breed, quantity, start date, and assign it to a house. Flocks can be marked as active or inactive.",
  },
  {
    category: "Flocks",
    question: "What are flock batches?",
    answer:
      "Flock batches allow you to group birds within a flock by arrival date or source. Navigate to Flock Batches to manage batches. Each batch tracks its own quantity and metadata.",
  },
  {
    category: "Flocks",
    question: "How do I deactivate a flock?",
    answer:
      "On the Flocks page, edit the flock you want to deactivate. Set the 'Active' toggle to off and provide a reason for inactivation. The flock will remain in your records for reporting purposes.",
  },
  {
    category: "Production",
    question: "How do I log daily production?",
    answer:
      "Go to Production Records and click 'Log Production'. Select the flock, date, and enter egg counts for 9 AM, 12 PM, and 4 PM collections. You can also record broken eggs, feed usage, and medication.",
  },
  {
    category: "Production",
    question: "How are egg totals calculated?",
    answer:
      "Egg totals are displayed in both raw counts and crates. One crate equals 30 eggs. For example, 95 eggs = 3 crates + 5 pieces (3c + 5p).",
  },
  {
    category: "Production",
    question: "Where can I see egg production trends?",
    answer:
      "Use Egg sorting for daily collection by flock and totals by size. Use Egg tracker (under Analytics) for the egg inventory ledger from production and sales. The Reports page provides charts for production trends over time.",
  },
  {
    category: "Feed & Inventory",
    question: "How do I record feed usage?",
    answer:
      "Navigate to Feed Usage and click 'Add Usage'. Select the flock, date, feed type, and quantity in kg. Feed records are automatically linked to production records for the same flock and date.",
  },
  {
    category: "Feed & Inventory",
    question: "How do I manage inventory?",
    answer:
      "The Inventory page lets you track all farm supplies including feed, medication, equipment, and eggs. Add items with quantities, unit prices, suppliers, and expiry dates. Use filters to search and categorize.",
  },
  {
    category: "Sales & Expenses",
    question: "How do I record a sale?",
    answer:
      "Go to Sales and click 'Record Sale'. Select the customer, items sold (eggs in crates/pieces, or other products), quantity, unit price, and payment method. The system calculates totals automatically.",
  },
  {
    category: "Sales & Expenses",
    question: "How do I track expenses?",
    answer:
      "Navigate to Expenses and click 'Add Expense'. Select the flock, category (Feed, Veterinary, Equipment, Labor, Utilities, Other), enter the amount, payment method, and description.",
  },
  {
    category: "Sales & Expenses",
    question: "Can I export sales or expense data?",
    answer:
      "Yes! On both the Sales and Expenses pages, you'll find PDF and CSV export buttons in the filter bar. Exports include all currently filtered records.",
  },
  {
    category: "Customers",
    question: "How do I manage customers?",
    answer:
      "The Customers page lets you add, edit, and delete customer records. Each customer has a name, email, phone, city, and address. Customers can be linked to sales for tracking.",
  },
  {
    category: "Reports",
    question: "What reports are available?",
    answer:
      "The Reports page provides production summaries, financial overviews, flock performance metrics, and trend analysis. Data can be filtered by date range and flock for detailed insights.",
  },
  {
    category: "Health",
    question: "How do I log health records?",
    answer:
      "Navigate to Health Records from the sidebar. Record vaccinations, treatments, and health observations for each flock. Track medication usage and health trends over time.",
  },
  {
    category: "Account",
    question: "How do I change my password?",
    answer:
      "Go to your Profile page by clicking the user icon in the top-right corner of the header. You'll find the option to update your password and other account settings.",
  },
  {
    category: "Account",
    question: "What's the difference between Admin and Staff roles?",
    answer:
      "Admins have full access to all features including settings, employee management, and delete operations. Staff members have limited access — they can view and create records but may not be able to delete or access certain admin-only features.",
  },
]

// `tint` is the disc behind the icon. It follows the subject, and where a
// subject also appears as an FAQ category the two use the same colour.
const featureGuides = [
  { icon: Bird, title: "Flocks", description: "Manage your flocks, batches, and bird tracking", path: "/flocks", tint: "bg-amber-100 text-amber-700" },
  { icon: Egg, title: "Production", description: "Log daily egg production and track metrics", path: "/production-records", tint: "bg-sky-100 text-sky-700" },
  { icon: Package, title: "Feed Usage", description: "Record and monitor feed consumption", path: "/feed-usage", tint: "bg-lime-100 text-lime-700" },
  { icon: ShoppingCart, title: "Sales", description: "Record sales and track revenue", path: "/sales", tint: "bg-violet-100 text-violet-700" },
  { icon: DollarSign, title: "Expenses", description: "Track costs and financial records", path: "/expenses", tint: "bg-rose-100 text-rose-700" },
  { icon: Users, title: "Customers", description: "Manage your customer database", path: "/customers", tint: "bg-teal-100 text-teal-700" },
  { icon: BarChart3, title: "Reports", description: "View analytics and generate reports", path: "/reports", tint: "bg-indigo-100 text-indigo-700" },
  { icon: Activity, title: "Health Records", description: "Track vaccinations and treatments", path: "/health", tint: "bg-red-100 text-red-700" },
  { icon: FileText, title: "Inventory", description: "Manage farm supplies and stock", path: "/inventory", tint: "bg-emerald-100 text-emerald-700" },
  { icon: Settings, title: "Company Setup", description: "Configure farm preferences", path: "/poultry-company-setup", tint: "bg-slate-200 text-slate-700" },
]

/**
 * A colour per FAQ category, so the same subject is the same colour wherever
 * it appears — the filter chip, the badge on an answer, and the rail down the
 * left of its card. A long list of questions in one grey is a wall; colour is
 * what lets someone scanning for "Flocks" find the block of them.
 */
const CATEGORY_TONES: Record<string, { chip: string; chipOn: string; rail: string; badge: string }> = {
  "Getting Started":  { chip: "hover:bg-emerald-50", chipOn: "bg-emerald-600 hover:bg-emerald-700", rail: "border-l-emerald-400", badge: "border-emerald-200 bg-emerald-50 text-emerald-700" },
  "Flocks":           { chip: "hover:bg-amber-50",   chipOn: "bg-amber-600 hover:bg-amber-700",     rail: "border-l-amber-400",   badge: "border-amber-200 bg-amber-50 text-amber-700" },
  "Production":       { chip: "hover:bg-sky-50",     chipOn: "bg-sky-600 hover:bg-sky-700",         rail: "border-l-sky-400",     badge: "border-sky-200 bg-sky-50 text-sky-700" },
  "Feed & Inventory": { chip: "hover:bg-lime-50",    chipOn: "bg-lime-600 hover:bg-lime-700",       rail: "border-l-lime-400",    badge: "border-lime-200 bg-lime-50 text-lime-700" },
  "Sales & Expenses": { chip: "hover:bg-violet-50",  chipOn: "bg-violet-600 hover:bg-violet-700",   rail: "border-l-violet-400",  badge: "border-violet-200 bg-violet-50 text-violet-700" },
  "Customers":        { chip: "hover:bg-teal-50",    chipOn: "bg-teal-600 hover:bg-teal-700",       rail: "border-l-teal-400",    badge: "border-teal-200 bg-teal-50 text-teal-700" },
  "Health":           { chip: "hover:bg-rose-50",    chipOn: "bg-rose-600 hover:bg-rose-700",       rail: "border-l-rose-400",    badge: "border-rose-200 bg-rose-50 text-rose-700" },
  "Reports":          { chip: "hover:bg-indigo-50",  chipOn: "bg-indigo-600 hover:bg-indigo-700",   rail: "border-l-indigo-400",  badge: "border-indigo-200 bg-indigo-50 text-indigo-700" },
  "Account":          { chip: "hover:bg-slate-100",  chipOn: "bg-slate-700 hover:bg-slate-800",     rail: "border-l-slate-400",   badge: "border-slate-200 bg-slate-100 text-slate-700" },
}

const FALLBACK_TONE = { chip: "hover:bg-slate-100", chipOn: "bg-indigo-600 hover:bg-indigo-700", rail: "border-l-slate-300", badge: "border-slate-200 bg-slate-50 text-slate-600" }
const toneFor = (category: string) => CATEGORY_TONES[category] ?? FALLBACK_TONE

export default function HelpPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  // /help is poultry-specific (flocks, eggs, birds, vaccinations). Send
  // Water/Generic users to their dashboard until type-specific help pages
  // exist. Wait for Zustand to hydrate before deciding.
  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType === "Water")        router.replace("/water-dashboard")
    else if (activeFarmType === "Generic") router.replace("/generic-dashboard")
  }, [activeFarmType, router])

  const [searchQuery, setSearchQuery] = useState("")
  // Open by default, and several at once: someone on a help page is reading,
  // not navigating, and a wall of closed questions makes them click to find out
  // whether each one was even the right question. `closedFAQs` holds the few
  // they have chosen to fold away rather than the many they have opened.
  const [closedFAQs, setClosedFAQs] = useState<Set<string>>(new Set())
  const [selectedCategory, setSelectedCategory] = useState<string>("All")

  const toggleFAQ = (key: string) => setClosedFAQs((prev) => {
    const next = new Set(prev)
    if (!next.delete(key)) next.add(key)
    return next
  })

  const categories = ["All", ...Array.from(new Set(faqData.map((f) => f.category)))]

  const filteredFAQs = faqData.filter((faq) => {
    const matchesSearch =
      !searchQuery ||
      faq.question.toLowerCase().includes(searchQuery.toLowerCase()) ||
      faq.answer.toLowerCase().includes(searchQuery.toLowerCase())
    const matchesCategory = selectedCategory === "All" || faq.category === selectedCategory
    return matchesSearch && matchesCategory
  })

  const allOpen = filteredFAQs.every((f) => !closedFAQs.has(f.question))

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-5xl mx-auto space-y-8">
            {/* Page Header */}
            <div className="text-center space-y-3">
              <div className="w-16 h-16 bg-indigo-100 rounded-2xl flex items-center justify-center mx-auto">
                <HelpCircle className="w-8 h-8 text-indigo-600" />
              </div>
              <h1 className="text-3xl font-bold text-slate-900">Help Center</h1>
              <p className="text-slate-600 max-w-xl mx-auto">
                Find answers to common questions, learn how to use VisibilityCore features, and get support.
              </p>
            </div>

            {/* Search */}
            <div className="relative max-w-lg mx-auto">
              <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-slate-400" />
              <Input
                placeholder="Search for help topics..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-12 h-12 text-base rounded-xl"
              />
            </div>

            {/* Quick Links - Feature Guides */}
            <div>
              <h2 className="text-lg font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <BookOpen className="w-5 h-5 text-indigo-600" />
                Feature Guide
              </h2>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3">
                {featureGuides.map((guide) => (
                  <Card
                    key={guide.path}
                    className="group cursor-pointer transition-all hover:-translate-y-0.5 hover:shadow-md"
                    onClick={() => router.push(guide.path)}
                  >
                    <CardContent className="p-4 text-center">
                      {/* The icon in its own tinted disc: ten grey glyphs in a
                          row are hard to tell apart at a glance, and this grid
                          is meant to be scanned, not read. */}
                      <div className={`mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-xl ${guide.tint}`}>
                        <guide.icon className="h-6 w-6" />
                      </div>
                      <div className="text-sm font-medium text-slate-900">{guide.title}</div>
                      <div className="mt-1 hidden text-xs text-slate-500 sm:block">{guide.description}</div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </div>

            {/* FAQ Section */}
            <div>
              <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
                <h2 className="flex items-center gap-2 text-lg font-semibold text-slate-900">
                  <HelpCircle className="w-5 h-5 text-indigo-600" />
                  Frequently Asked Questions
                  <span className="text-sm font-normal text-slate-500">
                    {filteredFAQs.length} {filteredFAQs.length === 1 ? "answer" : "answers"}
                  </span>
                </h2>
                {filteredFAQs.length > 0 && (
                  <button
                    className="text-xs font-medium text-indigo-600 hover:underline"
                    onClick={() => setClosedFAQs(allOpen ? new Set(filteredFAQs.map((f) => f.question)) : new Set())}
                  >
                    {allOpen ? "Collapse all" : "Expand all"}
                  </button>
                )}
              </div>

              {/* Category Filters */}
              <div className="flex flex-wrap gap-2 mb-4">
                {categories.map((cat) => {
                  const tone = cat === "All" ? FALLBACK_TONE : toneFor(cat)
                  const on = selectedCategory === cat
                  return (
                    <Badge
                      key={cat}
                      variant={on ? "default" : "outline"}
                      className={`cursor-pointer px-3 py-1 transition-colors ${on ? tone.chipOn : tone.chip}`}
                      onClick={() => setSelectedCategory(cat)}
                    >
                      {cat}
                      <span className={`ml-1.5 text-[10px] ${on ? "opacity-80" : "text-slate-400"}`}>
                        {cat === "All" ? faqData.length : faqData.filter((f) => f.category === cat).length}
                      </span>
                    </Badge>
                  )
                })}
              </div>

              {/* FAQ Items */}
              <div className="space-y-2">
                {filteredFAQs.length === 0 ? (
                  <Card>
                    <CardContent className="py-8 text-center text-slate-500">
                      No results found for &quot;{searchQuery}&quot;. Try a different search term.
                    </CardContent>
                  </Card>
                ) : (
                  filteredFAQs.map((faq) => {
                    const tone = toneFor(faq.category)
                    const open = !closedFAQs.has(faq.question)
                    return (
                      <Card key={faq.question} className={`border-l-4 transition-all ${tone.rail} ${open ? "shadow-sm" : ""}`}>
                        <CardContent className="p-0">
                          <button
                            className="w-full rounded-xl px-4 py-4 text-left transition-colors hover:bg-slate-50 sm:px-5"
                            onClick={() => toggleFAQ(faq.question)}
                            aria-expanded={open}
                          >
                            <div className="flex items-start justify-between gap-3">
                              {/* The category badge sits ABOVE the question on a
                                  phone: inline, it took half the width and left
                                  the question wrapping in a two-word column. */}
                              <div className="min-w-0 flex-1">
                                <Badge variant="outline" className={`mb-1.5 text-[10px] font-medium ${tone.badge}`}>
                                  {faq.category}
                                </Badge>
                                <div className="font-medium text-slate-900">{faq.question}</div>
                              </div>
                              {open ? (
                                <ChevronUp className="mt-0.5 h-5 w-5 shrink-0 text-slate-400" />
                              ) : (
                                <ChevronDown className="mt-0.5 h-5 w-5 shrink-0 text-slate-400" />
                              )}
                            </div>
                          </button>
                          {open && (
                            <div className="px-4 pb-4 pt-0 sm:px-5">
                              <div className="border-t border-slate-100 pt-3 text-sm leading-relaxed text-slate-600">
                                {faq.answer}
                              </div>
                            </div>
                          )}
                        </CardContent>
                      </Card>
                    )
                  })
                )}
              </div>
            </div>

            {/* Contact Support */}
            <Card className="border-indigo-200 bg-indigo-50/50">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-indigo-900">
                  <Mail className="w-5 h-5" />
                  Need More Help?
                </CardTitle>
                <CardDescription className="text-indigo-700">
                  Can't find what you're looking for? Reach out to our support team.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-6">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center">
                      <Mail className="w-5 h-5 text-indigo-600" />
                    </div>
                    <div>
                      <div className="text-sm font-medium text-slate-900">Email Support</div>
                      <div className="text-sm text-slate-600">techretainer@gmail.com</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center">
                      <Phone className="w-5 h-5 text-indigo-600" />
                    </div>
                    <div>
                      <div className="text-sm font-medium text-slate-900">Phone Support</div>
                      <div className="text-sm text-slate-600">+1 (917) 420-2946 / 0533431086</div>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  )
}

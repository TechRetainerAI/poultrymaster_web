"use client"

import { useState } from "react"
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
      "The Egg Production page shows detailed records with filtering by flock, date range, and time period. The Reports page provides charts and analytics for production trends over time.",
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

const featureGuides = [
  { icon: Bird, title: "Flocks", description: "Manage your flocks, batches, and bird tracking", path: "/flocks" },
  { icon: Egg, title: "Production", description: "Log daily egg production and track metrics", path: "/production-records" },
  { icon: Package, title: "Feed Usage", description: "Record and monitor feed consumption", path: "/feed-usage" },
  { icon: ShoppingCart, title: "Sales", description: "Record sales and track revenue", path: "/sales" },
  { icon: DollarSign, title: "Expenses", description: "Track costs and financial records", path: "/expenses" },
  { icon: Users, title: "Customers", description: "Manage your customer database", path: "/customers" },
  { icon: BarChart3, title: "Reports", description: "View analytics and generate reports", path: "/reports" },
  { icon: Activity, title: "Health Records", description: "Track vaccinations and treatments", path: "/health" },
  { icon: FileText, title: "Inventory", description: "Manage farm supplies and stock", path: "/inventory" },
  { icon: Settings, title: "Settings", description: "Configure farm preferences", path: "/settings" },
]

export default function HelpPage() {
  const router = useRouter()
  const [searchQuery, setSearchQuery] = useState("")
  const [openFAQ, setOpenFAQ] = useState<number | null>(null)
  const [selectedCategory, setSelectedCategory] = useState<string>("All")

  const categories = ["All", ...Array.from(new Set(faqData.map((f) => f.category)))]

  const filteredFAQs = faqData.filter((faq) => {
    const matchesSearch =
      !searchQuery ||
      faq.question.toLowerCase().includes(searchQuery.toLowerCase()) ||
      faq.answer.toLowerCase().includes(searchQuery.toLowerCase())
    const matchesCategory = selectedCategory === "All" || faq.category === selectedCategory
    return matchesSearch && matchesCategory
  })

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
      <div className="flex-1 flex flex-col">
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
                Find answers to common questions, learn how to use Poultry Master features, and get support.
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
                    className="cursor-pointer hover:shadow-md hover:border-indigo-200 transition-all group"
                    onClick={() => router.push(guide.path)}
                  >
                    <CardContent className="p-4 text-center">
                      <guide.icon className="w-8 h-8 mx-auto mb-2 text-slate-500 group-hover:text-indigo-600 transition-colors" />
                      <div className="text-sm font-medium text-slate-900">{guide.title}</div>
                      <div className="text-xs text-slate-500 mt-1 hidden sm:block">{guide.description}</div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </div>

            {/* FAQ Section */}
            <div>
              <h2 className="text-lg font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <HelpCircle className="w-5 h-5 text-indigo-600" />
                Frequently Asked Questions
              </h2>

              {/* Category Filters */}
              <div className="flex flex-wrap gap-2 mb-4">
                {categories.map((cat) => (
                  <Badge
                    key={cat}
                    variant={selectedCategory === cat ? "default" : "outline"}
                    className={`cursor-pointer transition-colors ${
                      selectedCategory === cat
                        ? "bg-indigo-600 hover:bg-indigo-700"
                        : "hover:bg-slate-100"
                    }`}
                    onClick={() => setSelectedCategory(cat)}
                  >
                    {cat}
                  </Badge>
                ))}
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
                  filteredFAQs.map((faq, idx) => (
                    <Card
                      key={idx}
                      className={`transition-all ${
                        openFAQ === idx ? "border-indigo-200 shadow-sm" : ""
                      }`}
                    >
                      <CardContent className="p-0">
                        <button
                          className="w-full px-5 py-4 flex items-center justify-between text-left hover:bg-slate-50 transition-colors rounded-xl"
                          onClick={() => setOpenFAQ(openFAQ === idx ? null : idx)}
                        >
                          <div className="flex items-start gap-3 flex-1">
                            <Badge variant="outline" className="text-xs shrink-0 mt-0.5">
                              {faq.category}
                            </Badge>
                            <span className="font-medium text-slate-900">{faq.question}</span>
                          </div>
                          {openFAQ === idx ? (
                            <ChevronUp className="w-5 h-5 text-slate-400 shrink-0 ml-2" />
                          ) : (
                            <ChevronDown className="w-5 h-5 text-slate-400 shrink-0 ml-2" />
                          )}
                        </button>
                        {openFAQ === idx && (
                          <div className="px-5 pb-4 pt-0">
                            <div className="pl-[calc(theme(spacing.3)+4.5rem)] text-sm text-slate-600 leading-relaxed">
                              {faq.answer}
                            </div>
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  ))
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
                      <div className="text-sm text-slate-600">support@poultrymaster.com</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center">
                      <Phone className="w-5 h-5 text-indigo-600" />
                    </div>
                    <div>
                      <div className="text-sm font-medium text-slate-900">Phone Support</div>
                      <div className="text-sm text-slate-600">Available Mon-Fri, 9am-5pm</div>
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
